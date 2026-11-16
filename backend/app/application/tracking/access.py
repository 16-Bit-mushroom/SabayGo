"""Who may see where a van is (the group's decision C5, 12 Nov).

A van's position is a person's position. The operator owns the van and
always drives it, and its plate is on every trip, so the map and the GPS
trail say where one named person is and has been. The Data Privacy Act
(RA 10173) asks for a legitimate purpose and no more than that purpose
needs; until 12 Nov both tracking reads were open to anyone, and the open
trip search hands out every trip's id and plate, so anyone could follow
any van and pull the whole trail of a trip that had already arrived.

The purpose, and so the rule:

- **The office and the crew** (Dispatcher, Terminal Manager, Cashier,
  admin) see every van, live and afterwards: they run the fleet, and the
  trail is what a driving flag or a dispute is checked against. The fleet
  map was already theirs alone.
- **A passenger** sees the van of a trip they hold a seat on (confirmed,
  checked in or boarded; not cancelled, not a no-show), and only while
  that trip is boarding or on the road. Before boarding there is nothing
  to watch; after arrival the reason to watch is gone, so the trail goes
  with it.
- **Nobody signed out** sees any van. The app already sends the
  passenger's sign-in, so a rider loses nothing.

Before boarding and after the trip ends the answer is "not found" with a
sentence, not "forbidden": the app's map already reads a 404 as "the van
has not reported yet" and keeps its last fix, so a rider whose trip ends
while the map is open sees the van stop, not an error page.

A share link for family that ends at arrival (option D) is not built.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import NotFoundError, PermissionDeniedError
from app.domain.enums import BookingStatus, Role, TripStatus
from app.infrastructure.models import Booking, Trip, User

STAFF = frozenset(
    r.value for r in (Role.DISPATCHER, Role.TERMINAL_MANAGER, Role.CASHIER, Role.ADMIN)
)
HOLDS_A_SEAT = (
    BookingStatus.CONFIRMED.value,
    BookingStatus.CHECKED_IN.value,
    BookingStatus.BOARDED.value,
)
LIVE = frozenset((TripStatus.BOARDING.value, TripStatus.DEPARTED.value))


async def ensure_can_see_van(session: AsyncSession, user: User, trip_id: str) -> None:
    """Return quietly when `user` may see this trip's van; raise otherwise."""
    if user.role in STAFF:
        return
    trip = await session.get(Trip, trip_id)
    if trip is None:
        raise NotFoundError("Trip not found.")
    seat = await session.scalar(
        select(Booking.booking_id)
        .where(
            Booking.trip_id == trip_id,
            Booking.passenger_user_id == user.user_id,
            Booking.status.in_(HOLDS_A_SEAT),
        )
        .limit(1)
    )
    if seat is None:
        raise PermissionDeniedError(
            "Only a passenger with a seat on this trip can see where its van is."
        )
    if trip.status == TripStatus.SCHEDULED.value:
        raise NotFoundError("The van shows here once the trip starts boarding.")
    if trip.status not in LIVE:
        raise NotFoundError("This trip has ended, so its van is no longer shown.")
