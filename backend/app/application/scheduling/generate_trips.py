"""Daily trip generation from recurring schedule templates.

Consultation: "Creating trips should be automatic everyday - set regular
schedule."

A TEMPLATE is a recurring pattern (route, departure time, days of week).
A TRIP is one dated instance. This job materialises tomorrow's trips from
today's templates, along with their legs and seat inventory.

Idempotency comes from UNIQUE (template_id, service_date) on `trips`: the
job can run twice, or be re-run after a partial failure, without producing
duplicate departures. That matters because a cron job that cannot safely
be retried is a cron job that will eventually corrupt a day's schedule.

Special trips are the complement -- rows with template_id NULL and
is_special_trip TRUE, created by hand through the operator console.
"""

from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta

from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import ConflictError, NotFoundError
from app.core.timezone import APP_TZ
from app.domain.enums import TripStatus
from app.infrastructure.models import (
    RouteStop,
    ScheduleTemplate,
    Trip,
    TripLeg,
    Van,
)
from app.application.scheduling.conflicts import ScheduleConflictChecker
from app.infrastructure.repositories.policy_repository import PolicyRepository

log = logging.getLogger(__name__)


@dataclass
class GenerationReport:
    service_date: date
    templates_considered: int = 0
    trips_created: int = 0
    trips_skipped: int = 0
    seat_legs_created: int = 0
    warnings: list[str] = field(default_factory=list)
    created_trip_ids: list[str] = field(default_factory=list)


class GenerateDailyTripsUseCase:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.policies = PolicyRepository(session)

    async def execute(
        self, *, service_date: date | None = None, days_ahead: int = 1
    ) -> list[GenerationReport]:
        """Generate trips for one or more upcoming service dates.

        days_ahead > 1 keeps a rolling window materialised, so passengers
        can book further out than tomorrow and a missed cron run does not
        leave a hole in the schedule.
        """
        start = service_date or datetime.now(APP_TZ).date()
        return [
            await self._generate_for_date(start + timedelta(days=offset))
            for offset in range(days_ahead)
        ]

    async def _generate_for_date(self, target: date) -> GenerationReport:
        report = GenerationReport(service_date=target)

        # Monday=0 in Python; days_of_week is a Monday-first 7-char mask.
        weekday_index = target.weekday()

        result = await self.session.execute(
            select(ScheduleTemplate).where(
                ScheduleTemplate.is_active.is_(True),
                ScheduleTemplate.valid_from <= target,
            )
        )
        templates = [
            t
            for t in result.scalars().all()
            if t.valid_until is None or t.valid_until >= target
        ]
        report.templates_considered = len(templates)

        default_capacity = await self.policies.get_int("default_seat_capacity")
        default_cap = await self.policies.get_int("advance_booking_seat_cap")
        default_cutoff = await self.policies.get_int("reschedule_cutoff_hours")

        for template in templates:
            if template.days_of_week[weekday_index] != "1":
                report.trips_skipped += 1
                continue

            # Idempotency check mirrors UNIQUE (template_id, service_date).
            # Checking first gives a clean report instead of an
            # IntegrityError the caller has to interpret.
            exists = await self.session.execute(
                select(func.count())
                .select_from(Trip)
                .where(
                    Trip.template_id == template.template_id,
                    Trip.service_date == target,
                )
            )
            if int(exists.scalar_one()) > 0:
                report.trips_skipped += 1
                continue

            stops = await self._route_stops(template.route_id)
            if len(stops) < 2:
                report.warnings.append(
                    f"Template {template.template_id}: route has fewer than "
                    "two stops; skipped."
                )
                continue

            capacity = default_capacity
            if template.default_van_id:
                van = await self.session.get(Van, template.default_van_id)
                if van is None:
                    report.warnings.append(
                        f"Template {template.template_id}: default van missing."
                    )
                elif van.operational_status != "active":
                    # Fleet management is monitoring-only, but a van flagged
                    # out of service must not be dispatched. The trip is
                    # still created -- unassigned -- so the operator sees a
                    # gap to fill rather than a silently missing departure.
                    report.warnings.append(
                        f"Van {van.plate_number} is {van.operational_status}; "
                        f"trip created without a van assignment."
                    )
                else:
                    capacity = van.seat_capacity

            assign_van = (
                template.default_van_id
                if capacity != default_capacity or template.default_van_id is None
                else template.default_van_id
            )
            # Re-resolve: only assign the van if it is actually active.
            if template.default_van_id:
                van = await self.session.get(Van, template.default_van_id)
                assign_van = (
                    template.default_van_id
                    if van and van.operational_status == "active"
                    else None
                )

            departure = datetime.combine(target, template.departure_time)

            # A van cannot be in two places at once. The trip is still
            # created -- skipping it would leave passengers unable to
            # book a scheduled departure -- but the clashing resource is
            # dropped and the operator is warned, so they see a roster
            # gap rather than an impossible assignment.
            clashes = await ScheduleConflictChecker(self.session).find_conflicts(
                route_id=template.route_id,
                departure=departure,
                van_id=assign_van,
                driver_id=template.default_driver_id,
                conductor_id=template.default_conductor_id,
            )
            drop = {c.resource for c in clashes}
            for c in clashes:
                report.warnings.append(f"{target}: {c.message}")
            if "van" in drop:
                assign_van = None

            trip_id = str(uuid.uuid4())
            now = datetime.now(APP_TZ)

            self.session.add(
                Trip(
                    trip_id=trip_id,
                    template_id=template.template_id,
                    route_id=template.route_id,
                    service_date=target,
                    departure_datetime=departure,
                    van_id=assign_van,
                    driver_id=(
                        None if "driver" in drop else template.default_driver_id
                    ),
                    conductor_id=(
                        None if "conductor" in drop
                        else template.default_conductor_id
                    ),
                    trip_label=template.trip_label,
                    is_special_trip=False,
                    # Policy snapshot: a later change never alters terms a
                    # passenger already booked under.
                    seat_capacity=capacity,
                    advance_booking_seat_cap=min(default_cap, capacity),
                    reschedule_cutoff_hours=default_cutoff,
                    status=TripStatus.SCHEDULED.value,
                    created_at=now,
                    updated_at=now,
                )
            )
            await self.session.flush()

            seat_legs = await self._materialise_legs_and_seats(
                trip_id, stops, departure, capacity
            )
            report.trips_created += 1
            report.seat_legs_created += seat_legs
            report.created_trip_ids.append(trip_id)

        await self.session.commit()
        log.info(
            "Generated %d trip(s) for %s (%d skipped, %d seat-legs)",
            report.trips_created, target, report.trips_skipped,
            report.seat_legs_created,
        )
        return report

    # ------------------------------------------------------------------
    async def _route_stops(self, route_id: str) -> list[RouteStop]:
        result = await self.session.execute(
            select(RouteStop)
            .where(RouteStop.route_id == route_id)
            .order_by(RouteStop.stop_sequence)
        )
        return list(result.scalars().all())

    async def _materialise_legs_and_seats(
        self,
        trip_id: str,
        stops: list[RouteStop],
        departure: datetime,
        capacity: int,
    ) -> int:
        """Create N-1 legs and capacity x legs seat-inventory rows."""
        for stop in stops[:-1]:
            self.session.add(
                TripLeg(
                    trip_id=trip_id,
                    leg_sequence=stop.stop_sequence,
                    from_stop_sequence=stop.stop_sequence,
                    to_stop_sequence=stop.stop_sequence + 1,
                    departs_at=departure + timedelta(minutes=stop.offset_minutes),
                )
            )
        await self.session.flush()

        # Bulk insert via a cross join. Doing this row by row would issue
        # capacity x legs INSERTs per trip -- 42 for a 4-stop route, and
        # far more once a cooperative runs a dozen departures a day.
        result = await self.session.execute(
            text(
                """
                INSERT INTO seat_inventory (trip_id, seat_number, leg_sequence)
                WITH RECURSIVE seats AS (
                    SELECT 1 AS seat_number
                    UNION ALL
                    SELECT seat_number + 1 FROM seats WHERE seat_number < :capacity
                )
                SELECT l.trip_id, s.seat_number, l.leg_sequence
                  FROM trip_legs l CROSS JOIN seats s
                 WHERE l.trip_id = :trip_id
                """
            ),
            {"trip_id": trip_id, "capacity": capacity},
        )
        return result.rowcount or 0


class CreateSpecialTripUseCase:
    """Ad-hoc departure outside the regular schedule.

    Consultation: "Manage if its Special trip." These carry template_id
    NULL and is_special_trip TRUE, so they are visibly distinct from
    generated trips in every query and report.
    """

    def __init__(self, session: AsyncSession):
        self.session = session
        self.policies = PolicyRepository(session)
        self.generator = GenerateDailyTripsUseCase(session)

    async def execute(
        self,
        *,
        route_id: str,
        departure_datetime: datetime,
        van_id: str | None = None,
        driver_id: str | None = None,
        conductor_id: str | None = None,
        trip_label: str | None = None,
        advance_booking_seat_cap: int | None = None,
    ) -> dict:
        if departure_datetime.tzinfo is None:
            departure_datetime = departure_datetime.replace(tzinfo=APP_TZ)
        if departure_datetime <= datetime.now(APP_TZ):
            raise ConflictError("A special trip must depart in the future.")

        stops = await self.generator._route_stops(route_id)
        if len(stops) < 2:
            raise NotFoundError("Route not found, or it has fewer than two stops.")

        capacity = await self.policies.get_int("default_seat_capacity")
        if van_id:
            van = await self.session.get(Van, van_id)
            if van is None:
                raise NotFoundError("Van not found.")
            if van.operational_status != "active":
                raise ConflictError(f"Van {van.plate_number} is {van.operational_status}.")
            capacity = van.seat_capacity

        # Manual assignment blocks rather than warns: an operator acting
        # deliberately should be told immediately, not discover the clash
        # in a report later.
        clashes = await ScheduleConflictChecker(self.session).find_conflicts(
            route_id=route_id,
            departure=departure_datetime.replace(tzinfo=None),
            van_id=van_id,
            driver_id=driver_id,
            conductor_id=conductor_id,
        )
        if clashes:
            raise ConflictError(clashes[0].message)

        cap = advance_booking_seat_cap
        if cap is None:
            cap = await self.policies.get_int("advance_booking_seat_cap")
        cap = min(cap, capacity)

        trip_id = str(uuid.uuid4())
        now = datetime.now(APP_TZ)
        naive_departure = departure_datetime.replace(tzinfo=None)

        self.session.add(
            Trip(
                trip_id=trip_id,
                template_id=None,
                route_id=route_id,
                service_date=departure_datetime.date(),
                departure_datetime=naive_departure,
                van_id=van_id,
                driver_id=driver_id,
                conductor_id=conductor_id,
                trip_label=trip_label or "Special Trip",
                is_special_trip=True,
                seat_capacity=capacity,
                advance_booking_seat_cap=cap,
                reschedule_cutoff_hours=await self.policies.get_int(
                    "reschedule_cutoff_hours"
                ),
                status=TripStatus.SCHEDULED.value,
                created_at=now,
                updated_at=now,
            )
        )
        await self.session.flush()

        seat_legs = await self.generator._materialise_legs_and_seats(
            trip_id, stops, naive_departure, capacity
        )
        await self.session.commit()

        log.info("Special trip %s created for %s", trip_id, departure_datetime)
        return {
            "trip_id": trip_id,
            "departure_datetime": naive_departure.isoformat(),
            "seat_capacity": capacity,
            "advance_booking_seat_cap": cap,
            "seat_legs_created": seat_legs,
            "is_special_trip": True,
        }
