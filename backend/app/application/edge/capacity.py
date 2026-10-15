"""The van held to 14, and the trip ending when nobody is left aboard
(rev 603, change brief 2.3, 4.1 'Completed', 6.2 phase 4; T25, T47).

Aboard is the door count minus the crew: every boarding less every
alighting the phone saw, in time order, less the Dispatcher once they
mark themselves crew. Before and after departure alike.

  capacity   each time aboard rises above the van's seat capacity, the
             event that crossed it raises a 'Capacity Alert' to the
             Terminal Manager, the Cashier and the trip's Dispatcher, once
             per crossing, with its time and the general place on the
             route (`TrackingService.geotag`, stored on the event). A
             phone that was offline raises it when its events arrive.
  complete   after departure, an alighting that leaves nobody aboard
             completes the trip, dated by that alighting, as the
             Dispatcher's Arrived does; the phone then pauses.

Neither prices anything: the remittance comes from the passenger list.
"""

from __future__ import annotations

from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.notifications.service import NotificationService, trip_label
from app.application.operations.trip_lifecycle import TripLifecycle
from app.application.tracking.nahgm import TrackingService
from app.core import timezone as app_tz
from app.domain.enums import Role, TripStatus
from app.infrastructure.models import Notification, PassengerEvent, Trip


def aboard_after(events: list[PassengerEvent], *, crew: int) -> list[tuple[PassengerEvent, int]]:
    """Each event, in time order, with the number aboard after it: every
    boarding less every alighting so far, less the crew."""
    running, out = 0, []
    for e in events:
        running += 1 if e.event_type == "board" else -1
        out.append((e, max(0, running - crew)))
    return out


class Ride:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def follow(self, trip: Trip) -> None:
        """Alert each crossing above capacity not yet alerted, and complete
        a departed trip its phone saw empty. The caller commits; a
        completion commits itself."""
        events = list((await self.session.execute(
            select(PassengerEvent).where(PassengerEvent.trip_id == trip.trip_id)
            .order_by(PassengerEvent.event_at)
        )).scalars().all())
        if not events:
            return
        counted = aboard_after(events, crew=1 if trip.crew_aboard else 0)
        above = False
        for e, aboard in counted:
            if aboard > trip.seat_capacity and not above:
                await self._alert(trip, e, aboard)
            above = aboard > trip.seat_capacity

        last, aboard = counted[-1]
        departed = trip.departed_at
        if departed is not None and departed.tzinfo is not None:
            departed = departed.astimezone(app_tz.APP_TZ).replace(tzinfo=None)
        if (trip.status == TripStatus.DEPARTED.value and departed is not None
                and last.event_type == "alight" and last.event_at >= departed
                and aboard == 0):
            await TripLifecycle(self.session).arrive(trip.trip_id, at=last.event_at)

    async def _alert(self, trip: Trip, event: PassengerEvent, aboard: int) -> None:
        already = (await self.session.execute(
            select(Notification.notification_id).where(
                Notification.type == "capacity_alert",
                Notification.related_entity_id == event.event_id,
            ).limit(1)
        )).first()
        if already:
            return
        tag = await TrackingService(self.session).geotag(
            trip, event.event_at,
            latitude=None if event.latitude is None else float(event.latitude),
            longitude=None if event.longitude is None else float(event.longitude),
        )
        if tag is not None:
            # The place, not the phone's fix: latitude and longitude are what
            # the phone sent, and are chained (`edge.chain`).
            event.distance_from_start_m = _dec(tag.distance_from_start_m, 2)
            event.stretch_no = tag.stretch_no
            event.nearest_stop_sequence = tag.nearest_stop_sequence
            event.nearest_stop_dist_m = _dec(tag.nearest_stop_dist_m, 2)
        where = tag.general if tag is not None and tag.general else "place not known (no GPS reading)"
        await NotificationService(self.session).notify_staff(
            type="capacity_alert", title="Capacity alert",
            message=(f"{trip_label(trip)}: {aboard} aboard at {event.event_at:%H:%M:%S}, above "
                     f"the van's {trip.seat_capacity}, {where}."),
            roles=(Role.TERMINAL_MANAGER, Role.CASHIER),
            entity=("passenger_event", event.event_id),
            also=[trip.dispatcher_id] if trip.dispatcher_id else [],
        )


def _dec(value: float | None, places: int) -> Decimal | None:
    return None if value is None else Decimal(str(round(value, places)))
