"""Scheduling conflict detection.

A van cannot be in two places at once, and neither can a Dispatcher. The trip
generator happily produced a 05:30 and an 06:00 departure on the same unit
for a five-hour route -- physically impossible, and nothing caught it.

Trip duration comes from the route's last stop offset: an Ecoland ->
Cotabato run with a 300-minute offset on stop 4 occupies its van for five
hours from departure, plus a turnaround allowance.

The check is advisory for generation (the trip is still created, but
unassigned and flagged) and blocking for manual assignment. Reasoning: a
nightly job that silently skips departures leaves passengers unable to
book, while the Terminal Manager assigning by hand should be told immediately.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.domain.enums import TripStatus
from app.infrastructure.models import Route, RouteStop, StaffProfile, Trip, Van

log = logging.getLogger(__name__)

# Minutes a van needs between arriving and departing again: unloading,
# refuelling, the operator's break. Deliberately generous -- a false
# conflict warning is cheaper than a double-booked van.
TURNAROUND_MINUTES = 45


@dataclass(frozen=True)
class Conflict:
    resource: str          # "van" or "dispatcher"
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
        dispatcher_id: str | None = None,
        exclude_trip_id: str | None = None,
    ) -> list[Conflict]:
        """Every resource already committed during this trip's window."""
        if not any([van_id, dispatcher_id]):
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
        # The operator always drives their own one van, so a van clash is
        # the operator clash too.
        if dispatcher_id:
            conditions.append(Trip.dispatcher_id == dispatcher_id)

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
                ("dispatcher", dispatcher_id, other.dispatcher_id),
            ):
                if wanted and wanted == held:
                    conflicts.append(
                        Conflict(
                            resource=resource,
                            resource_id=wanted,
                            conflicting_trip_id=other.trip_id,
                            conflicting_departure=other_start,
                            message=await self._words(resource, other, other_end, departure),
                        )
                    )
        return conflicts

    async def _words(self, resource: str, other: Trip, free_at: datetime, departure: datetime) -> str:
        """The clash as the office says it (11 Nov): who or which van, the
        trip they are on by its time and route, when they are free again,
        and what to do. Never the trip's database id -- a timetable trip
        has no label, and the id is all the old message had to show."""
        route = await self.session.get(Route, other.route_id) if other.route_id else None
        trip = f"the {_clock(other.departure_datetime)} {route.route_name if route else 'van rental'} trip"
        if other.trip_label:
            trip += f" ({other.trip_label})"
        if resource == "van":
            plate = other.van_plate_number
            if plate is None and other.van_id:
                van = await self.session.get(Van, other.van_id)
                plate = van.plate_number if van else None
            who, role, other_choice = plate or "This van", "is already on", "another van"
        else:
            profile = await self.session.get(StaffProfile, other.dispatcher_id) if other.dispatcher_id else None
            who = f"{profile.first_name} {profile.last_name}" if profile else "This Dispatcher"
            role, other_choice = "is already the Dispatcher on", "another Dispatcher"
        return (
            f"{who} {role} {trip}, and is free again at about {_clock(free_at)} "
            f"(the route plus {TURNAROUND_MINUTES} minutes to turn round). A trip at "
            f"{_clock(departure)} would overlap it: choose {other_choice}, leave it for later, "
            f"or pick a time from {_clock(free_at)}."
        )


def _clock(at: datetime) -> str:
    """'7:30 AM', as the console shows a time."""
    return f"{at:%I:%M %p}".lstrip("0")
