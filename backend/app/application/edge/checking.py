"""Checking door events against the passenger list (rev 721, change
brief 2.4, 5.2, 6.1; phase 3 of 6.2).

Before departure. A boarding the phone saw is *listed* while an unmatched
**seat the Dispatcher marked as paid** ('matched_booking') or an
unmatched **walk-up entry the Dispatcher listed** ('matched_log') remains
on the trip's list. Each seat or entry is used up by one boarding only.
Otherwise the boarding is 'unlisted', and its resolution is 'pending'
until the Dispatcher either fixes the list (lists the person with a
destination, `mark_listed`) or types a reason (`explain`).

**There is no matching window.** Rev 721 removed it along with the QR
scan: with no ticket to scan there is no moment to match against, and a
passenger may hand over the cash long before or long after stepping
aboard. What remains is a count -- so many paid seats, so many boardings
-- not an identity. `matched_booking_id` names the seat that was used up,
not the person who walked through the door.

Seats are consumed oldest first (a paid seat by `paid_at`, a walk-up
entry by when it was logged) so that the result is the same however the
phone's offline uploads arrive. Which kind is taken first does not
matter: the paper does not say, and the amount owed does not depend on
it. The Dispatcher's fixes and reasons are kept across a recheck.

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
from datetime import datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.finance.statement import CASH, PAID_SEAT
from app.application.notifications.service import NotificationService, trip_label
from app.core import timezone as app_tz
from app.core.exceptions import ConflictError, NotFoundError
from app.domain.enums import BookingStatus, Role, TripStatus
from app.infrastructure.models import (
    Booking,
    Notification,
    PassengerEvent,
    Trip,
    User,
)

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
        free = [c for c in await self._records(trip) if c[2] not in fixes]
        for e in boards:
            # A boarding the Dispatcher has already resolved keeps what
            # they recorded. Without this, a seat marked paid afterwards
            # would be handed to an explained boarding on the next
            # recheck and wipe the reason they typed -- and with no
            # matching window that is no longer a remote coincidence but
            # the ordinary case, because any free seat goes to the
            # earliest unmatched boarding.
            if e.resolution_status in ("listed", "explained"):
                continue
            if free:
                # No window: take the oldest seat still on the list.
                taken = free.pop(0)
                self._clear(e)
                e.match_status, e.matched_booking_id = taken[1], taken[2]
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
        """(when, kind, booking) of every seat on the trip's list.

        A reservation the Dispatcher marked Paid is 'matched_booking';
        a walk-up the Dispatcher listed is 'matched_log'. Oldest first,
        so a recheck gives the same answer every time. An unpaid
        reservation is not here at all: it is not on the list, so a
        passenger who boards on one is an unlisted boarding until the
        Dispatcher takes the cash or types a reason (brief 6.1).
        """
        rows = (await self.session.execute(
            select(
                Booking.paid_at, Booking.created_at,
                Booking.booking_type, Booking.booking_id,
            ).where(
                Booking.trip_id == trip.trip_id,
                *PAID_SEAT,
            )
        )).all()
        records = [
            (_naive(paid_at or created_at),
             "matched_log" if kind in CASH else "matched_booking",
             booking_id)
            for paid_at, created_at, kind, booking_id in rows
        ]
        records.sort(key=lambda r: r[0])
        return records

    async def _listed(self, trip: Trip) -> int:
        return (await self.session.execute(
            select(func.count()).select_from(Booking).where(
                Booking.trip_id == trip.trip_id,
                *PAID_SEAT,
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

    async def mark_listed(
        self, event: PassengerEvent, *, booking_id: str, by: User
    ) -> None:
        """The Dispatcher listed the person this boarding was (brief 2.4).

        Takes the event the caller already validated with `pending_event`,
        and deliberately does not re-validate. With no matching window a
        seat on the list is taken by the earliest unmatched boarding, so
        the seat just created to fix *this* boarding would be consumed by
        it on the next recheck -- and a second `pending_event` would then
        report, correctly but uselessly, that there is nothing left to
        resolve. The fix is recorded first; from then on `recheck` keeps
        the pairing, because a boarding whose resolution is 'listed'
        holds its booking and neither is offered to anything else.
        """
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
