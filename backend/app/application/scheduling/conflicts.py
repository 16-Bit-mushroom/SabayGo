"""Scheduling conflict detection.

A van cannot be in two places at once, and neither can a driver. The trip
generator happily produced a 05:30 and an 06:00 departure on the same unit
for a five-hour route -- physically impossible, and nothing caught it.

Trip duration comes from the route's last stop offset: an Ecoland ->
Cotabato run with a 300-minute offset on stop 4 occupies its van for five
hours from departure, plus a turnaround allowance.

The check is advisory for generation (the trip is still created, but
unassigned and flagged) and blocking for manual assignment. Reasoning: a
nightly job that silently skips departures leaves passengers unable to
book, while an operator assigning by hand should be told immediately.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.enums import TripStatus
from app.infrastructure.models import RouteStop, Trip

log = logging.getLogger(__name__)

# Minutes a van needs between arriving and departing again: unloading,
# refuelling, the driver's break. Deliberately generous -- a false
# conflict warning is cheaper than a double-booked van.
TURNAROUND_MINUTES = 45


@dataclass(frozen=True)
class Conflict:
    resource: str          # "van", "driver" or "conductor"
    resource_id: str
    conflicting_trip_id: str
    conflicting_departure: datetime
    message: str


class ScheduleConflictChecker:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def route_duration_minutes(self, route_id: str) -> int:
        """How long the route occupies a vehicle, end to end."""
        result = await self.session.execute(
            select(func.max(RouteStop.offset_minutes)).where(
                RouteStop.route_id == route_id
            )
        )
        return int(result.scalar_one() or 0)

    async def find_conflicts(
        self,
        *,
        route_id: str,
        departure: datetime,
        van_id: str | None = None,
        driver_id: str | None = None,
        conductor_id: str | None = None,
        exclude_trip_id: str | None = None,
    ) -> list[Conflict]:
        """Every resource already committed during this trip's window."""
        if not any([van_id, driver_id, conductor_id]):
            return []

        duration = await self.route_duration_minutes(route_id)
        window_start = departure
        window_end = departure + timedelta(minutes=duration + TURNAROUND_MINUTES)

        # Candidate trips on the same day sharing any of these resources.
        # Same-day is a safe narrowing: a route long enough to spill past
        # midnight would need a different check, and none in scope do.
        conditions = []
        if van_id:
            conditions.append(Trip.van_id == van_id)
        if driver_id:
            conditions.append(Trip.driver_id == driver_id)
        if conductor_id:
            conditions.append(Trip.conductor_id == conductor_id)

        stmt = select(Trip).where(
            or_(*conditions),
            Trip.service_date == departure.date(),
            Trip.status.notin_(
                [TripStatus.CANCELLED.value, TripStatus.COMPLETED.value]
            ),
        )
        if exclude_trip_id:
            stmt = stmt.where(Trip.trip_id != exclude_trip_id)

        result = await self.session.execute(stmt)
        conflicts: list[Conflict] = []

        for other in result.scalars():
            other_duration = await self.route_duration_minutes(other.route_id)
            other_start = other.departure_datetime
            other_end = other_start + timedelta(
                minutes=other_duration + TURNAROUND_MINUTES
            )

            # Two windows overlap unless one ends before the other begins.
            if window_end <= other_start or other_end <= window_start:
                continue

            for resource, wanted, held in (
                ("van", van_id, other.van_id),
                ("driver", driver_id, other.driver_id),
                ("conductor", conductor_id, other.conductor_id),
            ):
                if wanted and wanted == held:
                    conflicts.append(
                        Conflict(
                            resource=resource,
                            resource_id=wanted,
                            conflicting_trip_id=other.trip_id,
                            conflicting_departure=other_start,
                            message=(
                                f"This {resource} is already on trip "
                                f"{other.trip_label or other.trip_id} departing "
                                f"{other_start:%H:%M}, which runs until about "
                                f"{other_end:%H:%M}."
                            ),
                        )
                    )
        return conflicts
