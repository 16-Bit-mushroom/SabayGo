"""Geofenced passenger check-in.

The passenger proves physical presence at the boarding terminal within a
time window before departure. Distance is computed server-side from the
raw coordinate -- the app sends a position, never a verdict, because a
client that decides its own geofence result can simply lie.

Both the raw coordinate and the computed distance are stored. The verdict
drives business logic; the distance is what lets you report GPS accuracy
in the Results chapter.
"""

from __future__ import annotations

import logging
import math
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.timezone import APP_TZ
from app.core.exceptions import ConflictError, NotFoundError, PolicyViolationError
from app.domain.enums import BookingStatus
from app.infrastructure.models import Booking as BookingRow
from app.infrastructure.models import CheckIn, RouteStop, Terminal, Trip
from app.infrastructure.repositories.policy_repository import PolicyRepository

log = logging.getLogger(__name__)

EARTH_RADIUS_M = 6_371_000.0


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in metres.

    Haversine rather than a planar approximation: at Davao's latitude the
    error from treating degrees as flat is small, but haversine costs
    nothing and removes a caveat you would otherwise have to defend.
    """
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


@dataclass(frozen=True)
class CheckInCommand:
    booking_id: str
    latitude: float
    longitude: float
    gps_accuracy_m: float | None = None


@dataclass(frozen=True)
class CheckInResult:
    check_in_id: str
    booking_id: str
    status: str
    terminal_name: str
    distance_m: float
    geofence_radius_m: int
    accepted: bool
    reason: str | None


class CheckInUseCase:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.policies = PolicyRepository(session)

    async def execute(
        self, cmd: CheckInCommand, *, passenger_user_id: str
    ) -> CheckInResult:
        booking = await self.session.get(BookingRow, cmd.booking_id)
        if booking is None or booking.passenger_user_id != passenger_user_id:
            raise NotFoundError("Booking not found.")

        if booking.status == BookingStatus.CHECKED_IN.value:
            raise ConflictError("You have already checked in for this trip.")
        if booking.status != BookingStatus.CONFIRMED.value:
            raise ConflictError(
                f"Only confirmed bookings can check in; this one is "
                f"{booking.status}."
            )

        trip = await self.session.get(Trip, booking.trip_id)
        if trip is None:
            raise NotFoundError("Trip not found.")

        terminal = await self._boarding_terminal(
            trip.route_id, booking.boarding_stop_sequence
        )

        distance = haversine_m(
            cmd.latitude, cmd.longitude,
            float(terminal.latitude), float(terminal.longitude),
        )

        radius = terminal.geofence_radius_m or await self.policies.get_int(
            "default_geofence_radius_m"
        )
        within_fence = distance <= radius

        window_minutes = await self.policies.get_int("checkin_window_minutes")
        departure = trip.departure_datetime
        if departure.tzinfo is None:
            departure = departure.replace(tzinfo=APP_TZ)
        now = datetime.now(APP_TZ)
        opens = departure - timedelta(minutes=window_minutes)
        within_window = opens <= now <= departure

        reason: str | None = None
        if not within_fence:
            reason = (
                f"You are {distance:.0f}m from {terminal.terminal_name}; "
                f"check-in requires being within {radius}m."
            )
        elif not within_window:
            reason = (
                f"Check-in opens {window_minutes} minutes before departure."
                if now < opens
                else "Check-in has closed; the trip has departed."
            )

        # The attempt is recorded either way. A rejected check-in is
        # evidence too -- it tells the cooperative administrator a passenger tried, and it
        # gives you the distance distribution for accuracy analysis.
        check_in_id = str(uuid.uuid4())
        self.session.add(
            CheckIn(
                check_in_id=check_in_id,
                booking_id=booking.booking_id,
                terminal_id=terminal.terminal_id,
                latitude=Decimal(str(round(cmd.latitude, 6))),
                longitude=Decimal(str(round(cmd.longitude, 6))),
                gps_accuracy_m=(
                    Decimal(str(round(cmd.gps_accuracy_m, 2)))
                    if cmd.gps_accuracy_m is not None
                    else None
                ),
                distance_m=Decimal(str(round(distance, 2))),
                geofence_radius_m=radius,
                is_within_geofence=within_fence,
                is_within_window=within_window,
                rejection_reason=reason,
                checked_in_at=now,
            )
        )

        accepted = within_fence and within_window
        if accepted:
            booking.status = BookingStatus.CHECKED_IN.value
            booking.updated_at = now

        await self.session.commit()
        log.info(
            "Check-in %s for booking %s: %.0fm / %dm -> %s",
            check_in_id, booking.booking_id, distance, radius,
            "accepted" if accepted else "rejected",
        )

        if not accepted:
            raise PolicyViolationError(reason or "Check-in rejected.")

        return CheckInResult(
            check_in_id=check_in_id,
            booking_id=booking.booking_id,
            status=BookingStatus.CHECKED_IN.value,
            terminal_name=terminal.terminal_name,
            distance_m=round(distance, 2),
            geofence_radius_m=radius,
            accepted=True,
            reason=None,
        )

    async def _boarding_terminal(self, route_id: str, stop_sequence: int) -> Terminal:
        result = await self.session.execute(
            select(Terminal)
            .join(RouteStop, RouteStop.terminal_id == Terminal.terminal_id)
            .where(
                RouteStop.route_id == route_id,
                RouteStop.stop_sequence == stop_sequence,
            )
        )
        terminal = result.scalar_one_or_none()
        if terminal is None:
            raise NotFoundError("Boarding terminal not found for this route.")
        return terminal
