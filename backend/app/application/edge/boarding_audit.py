"""Boarding Audit: the Terminal Manager's review of a day's door events
(rev 603, change brief 9; replaces Passenger Count Checks).

For each trip of the service date that has something to review:
  unlisted   each boarding before departure that matched no QR scan or
             cash entry (`checking.py`), with its time, whether its blurred
             still is kept, and the Dispatcher's fix (the person listed,
             with a destination) or reason, or neither ('pending');
  capacity   each crossing above the van's seat capacity that raised a
             'Capacity Alert' (`capacity.py`), with the number aboard and
             the general place on the route;
  departed   the 'Departed With More Than Listed' alert, when one was raised;
  chain      the trip's hash chain, recomputed (`chain.verify`).
Read only: nothing here matches, prices or alerts. The stills themselves
go to the Terminal Manager alone, through `GET /door-events/{id}/snapshot`.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.edge import chain
from app.application.edge.capacity import aboard_after
from app.application.identity.naming import display_name
from app.application.notifications.service import trip_label
from app.application.tracking.nahgm import TrackingService
from app.infrastructure.models import Booking, Notification, PassengerEvent, Trip, User


@dataclass
class Unlisted:
    event_id: str
    event_at: datetime
    resolution_status: str            # pending | listed | explained
    resolution_note: str | None
    listed_booking_id: str | None
    listed_destination: str | None
    resolved_by: str | None
    resolved_at: datetime | None
    has_snapshot: bool
    snapshot_deleted: bool


@dataclass
class CapacityAlert:
    event_id: str
    event_at: datetime
    aboard: int
    seat_capacity: int
    place: str | None


@dataclass
class TripAudit:
    trip_id: str
    trip_label: str
    departure_datetime: datetime
    status: str
    plate_number: str | None
    operator_name: str | None
    operator_licence: str | None
    dispatcher_name: str | None
    # The Dispatcher marked themselves crew: one unmatched boarding is theirs.
    crew_aboard: bool
    departed_with_more: str | None
    chain_events: int
    chain_verified: bool
    chain_broken_at: int | None
    unlisted: list[Unlisted] = field(default_factory=list)
    capacity_alerts: list[CapacityAlert] = field(default_factory=list)


class BoardingAudit:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.tracking = TrackingService(session)

    async def day(self, service_date: date) -> list[TripAudit]:
        trips = {t.trip_id: t for t in (await self.session.execute(
            select(Trip).where(Trip.service_date == service_date)
            .order_by(Trip.departure_datetime)
        )).scalars()}
        if not trips:
            return []
        ids = list(trips)
        unlisted: dict[str, list[PassengerEvent]] = {}
        for e in (await self.session.execute(
            select(PassengerEvent).where(
                PassengerEvent.trip_id.in_(ids), PassengerEvent.event_type == "board",
                PassengerEvent.pre_departure.is_(True),
                PassengerEvent.match_status == "unlisted",
            ).order_by(PassengerEvent.event_at)
        )).scalars():
            unlisted.setdefault(e.trip_id, []).append(e)
        crossings: dict[str, set[str]] = {}
        for trip_id, event_id in (await self.session.execute(
            select(PassengerEvent.trip_id, PassengerEvent.event_id).distinct()
            .join(Notification, Notification.related_entity_id == PassengerEvent.event_id)
            .where(Notification.type == "capacity_alert", PassengerEvent.trip_id.in_(ids))
        )).all():
            crossings.setdefault(trip_id, set()).add(event_id)
        departed: dict[str, str] = dict((await self.session.execute(
            select(Notification.related_entity_id, Notification.message).where(
                Notification.type == "departed_more_than_listed",
                Notification.related_entity_id.in_(ids),
            )
        )).all())

        flagged = [t for t in trips.values()
                   if t.trip_id in unlisted or t.trip_id in crossings or t.trip_id in departed]
        names = await self._names({t.dispatcher_id for t in flagged} | {
            e.resolved_by for events in unlisted.values() for e in events})
        return [await self._trip(t, unlisted.get(t.trip_id, []),
                                 crossings.get(t.trip_id, set()), departed.get(t.trip_id), names)
                for t in flagged]

    async def _trip(self, trip: Trip, unlisted: list[PassengerEvent], crossings: set[str],
                    departed: str | None, names: dict[str, str]) -> TripAudit:
        check = await chain.verify(self.session, trip.trip_id)
        audit = TripAudit(
            trip_id=trip.trip_id, trip_label=trip_label(trip),
            departure_datetime=trip.departure_datetime, status=trip.status,
            plate_number=trip.van_plate_number or (trip.van.plate_number if trip.van else None),
            operator_name=trip.driver_name, operator_licence=trip.driver_license_no,
            dispatcher_name=names.get(trip.dispatcher_id), crew_aboard=bool(trip.crew_aboard),
            departed_with_more=departed,
            chain_events=check.events, chain_verified=check.verified,
            chain_broken_at=check.broken_at,
        )
        destinations = await self._destinations(trip, [e.matched_booking_id for e in unlisted
                                                       if e.resolution_status == "listed"])
        audit.unlisted = [Unlisted(
            event_id=e.event_id, event_at=e.event_at, resolution_status=e.resolution_status,
            resolution_note=e.resolution_note,
            listed_booking_id=e.matched_booking_id if e.resolution_status == "listed" else None,
            listed_destination=destinations.get(e.matched_booking_id),
            resolved_by=names.get(e.resolved_by), resolved_at=e.resolved_at,
            has_snapshot=e.snapshot_url is not None,
            snapshot_deleted=e.snapshot_deleted_at is not None,
        ) for e in unlisted]
        if crossings:
            events = list((await self.session.execute(
                select(PassengerEvent).where(PassengerEvent.trip_id == trip.trip_id)
                .order_by(PassengerEvent.event_at)
            )).scalars().all())
            for e, aboard in aboard_after(events, crew=1 if trip.crew_aboard else 0):
                if e.event_id in crossings:
                    audit.capacity_alerts.append(CapacityAlert(
                        event_id=e.event_id, event_at=e.event_at, aboard=aboard,
                        seat_capacity=trip.seat_capacity,
                        place=await self.tracking.place(
                            trip.route_id, e.stretch_no, e.nearest_stop_sequence,
                            None if e.nearest_stop_dist_m is None else float(e.nearest_stop_dist_m)),
                    ))
        return audit

    async def _destinations(self, trip: Trip, booking_ids: list[str]) -> dict[str, str]:
        if not booking_ids or trip.route_id is None:
            return {}
        stops = {rs.stop_sequence: t.terminal_name
                 for rs, t in await self.tracking._route_stops(trip.route_id)}
        return {b: stops.get(seq) for b, seq in (await self.session.execute(
            select(Booking.booking_id, Booking.alighting_stop_sequence)
            .where(Booking.booking_id.in_(booking_ids))
        )).all()}

    async def _names(self, user_ids: set[str | None]) -> dict[str, str]:
        user_ids = user_ids - {None}
        if not user_ids:
            return {}
        return {u.user_id: display_name(u) for u in (await self.session.execute(
            select(User).where(User.user_id.in_(user_ids))
        )).scalars()}
