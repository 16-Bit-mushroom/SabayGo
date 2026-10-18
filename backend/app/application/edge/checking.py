"""Checking door events against the passenger list (rev 603, change
brief 2.4, 6.1; phase 3 of 6.2).

Before departure. A boarding the phone saw is *listed* when a QR scan or
a Dispatcher's cash entry on the trip was made within `match_window_
seconds` before or after it and was not already used for another
boarding: 'matched_qr' or 'matched_log'. Otherwise it is 'unlisted', and
its resolution is 'pending' until the Dispatcher either fixes the list
(lists the person with a destination, `mark_listed`) or types a reason
(`explain`). Matching is by time and recomputed from the stored rows on
every check, so the order in which scans, entries and a phone's offline
uploads arrive does not change the result; the Dispatcher's fixes and
reasons are kept.

The count that gates Depart is the brief's comparison: aboard (door
boardings minus alightings before departure, minus the Dispatcher once
they mark themselves crew) against listed (the paid seats on the list,
leaving out home-pickup seats not yet boarded) plus explained boardings.
Fewer aboard is a no-show and needs nothing. More aboard stops a
person's Depart (`boarding.DepartTripUseCase`); a van that leaves anyway
raises 'Departed with more aboard than listed' -- at the departure, or
when a phone that was offline uploads boardings from before it.

After departure nothing is matched or priced: the camera only holds the
van to 14. Alightings are never matched to people, and nothing here sets
a fare: the camera's count alone prices no one.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.finance.statement import CASH, LISTED
from app.application.notifications.service import NotificationService, trip_label
from app.core import timezone as app_tz
from app.core.exceptions import ConflictError, NotFoundError
from app.domain.enums import BookingStatus, Role, TripStatus
from app.infrastructure.models import (
    Booking,
    BoardingScan,
    Notification,
    PassengerEvent,
    Trip,
    User,
)
from app.infrastructure.repositories.policy_repository import PolicyRepository

BEFORE_DEPARTURE = (TripStatus.SCHEDULED.value, TripStatus.BOARDING.value)


def _now() -> datetime:
    return app_tz.now().replace(tzinfo=None)


@dataclass
class Check:
    aboard: int
    listed: int
    explained: int
    crew_aboard: bool
    unlisted: list[PassengerEvent] = field(default_factory=list)

    @property
    def excess(self) -> int:
        """More aboard than listed, less those the Dispatcher explained."""
        return max(0, self.aboard - self.listed - self.explained)


class ListCheck:
    def __init__(self, session: AsyncSession):
        self.session = session

    # ------------------------------------------------------------ check
    async def recheck(self, trip: Trip) -> Check:
        """Match the trip's boardings before departure to its scans and
        entries, and count aboard against listed. The caller commits."""
        events = list((await self.session.execute(
            select(PassengerEvent).where(PassengerEvent.trip_id == trip.trip_id)
            .order_by(PassengerEvent.event_at)
        )).scalars().all())
        departed = _naive(trip.departed_at) if trip.departed_at else None
        for e in events:
            e.pre_departure = departed is None or e.event_at < departed
        boards = [e for e in events if e.event_type == "board" and e.pre_departure]
        for e in events:
            if e not in boards:
                self._clear(e)

        # A booking the Dispatcher added to fix the list is that boarding's.
        fixes = {e.matched_booking_id for e in boards if e.resolution_status == "listed"}
        window = timedelta(seconds=await PolicyRepository(self.session).get_int(
            "match_window_seconds"))
        free = [c for c in await self._records(trip) if c[2] not in fixes]
        for e in boards:
            if e.resolution_status == "listed":
                continue
            near = [c for c in free if abs(c[0] - e.event_at) <= window]
            if near:
                best = min(near, key=lambda c: abs(c[0] - e.event_at))
                free.remove(best)
                self._clear(e)
                e.match_status, e.matched_booking_id = best[1], best[2]
            else:
                e.match_status, e.matched_booking_id = "unlisted", None
                if e.resolution_status == "not_needed":
                    e.resolution_status = "pending"
        await self.session.flush()

        moves = sum(1 if e.event_type == "board" else -1 for e in events if e.pre_departure)
        crew = bool(trip.crew_aboard)
        return Check(
            aboard=max(0, moves - (1 if crew else 0)),
            listed=await self._listed(trip),
            explained=sum(1 for e in boards if e.resolution_status == "explained"),
            crew_aboard=crew,
            unlisted=[e for e in boards if e.match_status == "unlisted"],
        )

    @staticmethod
    def _clear(e: PassengerEvent) -> None:
        e.match_status = None
        e.matched_booking_id = None
        e.resolution_status = "not_needed"
        e.resolved_by = None
        e.resolved_at = None
        e.resolution_note = None

    async def _records(self, trip: Trip) -> list[tuple[datetime, str, str]]:
        """(time, kind, booking) of each QR scan and cash entry on the
        trip: the first valid scan of a ticket, the entry of a cash seat."""
        scans = (await self.session.execute(
            select(func.min(BoardingScan.scanned_at), BoardingScan.booking_id)
            .join(Booking, Booking.booking_id == BoardingScan.booking_id)
            .where(Booking.trip_id == trip.trip_id, BoardingScan.result == "valid")
            .group_by(BoardingScan.booking_id)
        )).all()
        entries = (await self.session.execute(
            select(Booking.created_at, Booking.booking_id).where(
                Booking.trip_id == trip.trip_id,
                Booking.booking_type.in_(CASH),
                Booking.status.in_(LISTED),
            )
        )).all()
        return ([(_naive(at), "matched_qr", b) for at, b in scans]
                + [(_naive(at), "matched_log", b) for at, b in entries])

    async def _listed(self, trip: Trip) -> int:
        return (await self.session.execute(
            select(func.count()).select_from(Booking).where(
                Booking.trip_id == trip.trip_id,
                Booking.status.in_(LISTED),
                # A home-pickup seat counts once its passenger is aboard.
                (Booking.is_home_pickup_seat.is_(False))
                | (Booking.status == BookingStatus.BOARDED.value),
            )
        )).scalar_one()

    # ------------------------------------------------ the Dispatcher's fix
    async def pending_event(self, event_id: str, *, by: User) -> PassengerEvent:
        """An unlisted boarding the Dispatcher of its trip may still resolve."""
        event = await self.session.get(PassengerEvent, event_id)
        trip = await self.session.get(Trip, event.trip_id) if event else None
        if trip is None or (by.role == Role.DISPATCHER.value and trip.dispatcher_id != by.user_id):
            raise NotFoundError("Door event not found.")
        if trip.status not in BEFORE_DEPARTURE:
            raise ConflictError(f"This trip is {trip.status}: the list was checked at departure.")
        await self.recheck(trip)
        if event.match_status != "unlisted" or event.resolution_status != "pending":
            raise ConflictError("This boarding needs nothing: it is on the list or resolved.")
        return event

    async def mark_listed(self, event_id: str, *, booking_id: str, by: User) -> None:
        """The Dispatcher listed the person this boarding was (brief 2.4)."""
        event = await self.pending_event(event_id, by=by)
        event.resolution_status = "listed"
        event.matched_booking_id = booking_id
        event.resolved_by, event.resolved_at = by.user_id, _now()
        await self.session.commit()

    async def explain(self, event_id: str, *, by: User, note: str) -> PassengerEvent:
        """The Dispatcher's reason for a boarding not on the list."""
        event = await self.pending_event(event_id, by=by)
        event.resolution_status = "explained"
        event.resolution_note = note
        event.resolved_by, event.resolved_at = by.user_id, _now()
        await self.session.commit()
        return event

    # ---------------------------------------------------- after the fact
    async def alert_if_left_with_more(self, trip: Trip, check: Check) -> None:
        """'Departed With More Than Listed' to the Terminal Manager, once
        per trip. The caller commits."""
        if not check.excess:
            return
        already = (await self.session.execute(
            select(Notification.notification_id).where(
                Notification.type == "departed_more_than_listed",
                Notification.related_entity_id == trip.trip_id,
            ).limit(1)
        )).first()
        if already:
            return
        await NotificationService(self.session).notify_trip(
            trip=trip, type="departed_more_than_listed",
            title="Departed with more aboard than listed",
            message=(f"{trip_label(trip)} left with {check.excess} more aboard than its "
                     f"passenger list ({check.aboard} aboard, {check.listed} listed), and the "
                     "Dispatcher neither fixed the list nor gave a reason. No fare is priced "
                     "from the camera's count."),
            roles=(Role.TERMINAL_MANAGER,),
        )


def _naive(at: datetime) -> datetime:
    return at.astimezone(app_tz.APP_TZ).replace(tzinfo=None) if at.tzinfo else at
