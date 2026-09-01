"""Cooperative configuration: routes, fares, policies, schedules.

This is what makes the system portable. A different cooperative sets up
its own terminals, routes, fare matrix and policy values through these
endpoints -- no code change, no migration, no redeploy.
"""

from __future__ import annotations

import datetime as dt
import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy import select

from app.api.v1.deps import SessionDep, require_roles
from app.application.scheduling.generate_trips import (
    CreateSpecialTripUseCase,
    GenerateDailyTripsUseCase,
)
from app.core.exceptions import ConflictError, NotFoundError
from app.core.timezone import APP_TZ
from app.domain.enums import Role
from app.infrastructure.models import (
    CooperativePolicy,
    FareMatrix,
    Route,
    RouteStop,
    ScheduleTemplate,
    Terminal,
)

router = APIRouter(prefix="/config", tags=["configuration"])
OPERATOR = require_roles(Role.OPERATOR, Role.ADMIN)


# ===================================================================
# Policies
# ===================================================================
class PolicyOut(BaseModel):
    policy_key: str
    policy_value: str
    data_type: str
    description: str
    updated_at: dt.datetime


class PolicyIn(BaseModel):
    policy_value: str


@router.get("/policies", response_model=list[PolicyOut],
            dependencies=[Depends(OPERATOR)])
async def list_policies(session: SessionDep) -> list[PolicyOut]:
    """Every configurable cooperative policy.

    These are rows precisely so a cooperative can revise them without a
    deployment -- reschedule cutoff, advance-booking cap, geofence radius,
    hold TTL, variance threshold.
    """
    result = await session.execute(
        select(CooperativePolicy).order_by(CooperativePolicy.policy_key)
    )
    return [PolicyOut(**{c: getattr(p, c) for c in PolicyOut.model_fields})
            for p in result.scalars()]


@router.put("/policies/{policy_key}", response_model=PolicyOut,
            dependencies=[Depends(OPERATOR)])
async def update_policy(
    policy_key: str, payload: PolicyIn, session: SessionDep
) -> PolicyOut:
    policy = await session.get(CooperativePolicy, policy_key)
    if policy is None:
        raise NotFoundError(f"Policy '{policy_key}' does not exist.")

    # Validate against the declared type before storing. A malformed value
    # here would fail much later, inside a booking, as an opaque ValueError.
    value = payload.policy_value.strip()
    try:
        if policy.data_type == "int":
            int(value)
        elif policy.data_type == "decimal":
            Decimal(value)
        elif policy.data_type == "bool":
            if value.lower() not in ("true", "false", "1", "0", "yes", "no"):
                raise ValueError
    except (ValueError, ArithmeticError):
        raise ConflictError(
            f"'{value}' is not a valid {policy.data_type} for {policy_key}."
        ) from None

    policy.policy_value = value
    policy.updated_at = dt.datetime.now(APP_TZ)
    await session.commit()

    # Existing trips are unaffected: seat capacity, advance cap and
    # reschedule cutoff are snapshotted onto each trip at generation time.
    return PolicyOut(**{c: getattr(policy, c) for c in PolicyOut.model_fields})


# ===================================================================
# Terminals and routes
# ===================================================================
class TerminalIn(BaseModel):
    terminal_name: str
    city: str
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    location_address: str | None = None
    geofence_radius_m: int | None = Field(default=None, ge=25, le=2000)
    is_staffed: bool = True


@router.post("/terminals", status_code=201, dependencies=[Depends(OPERATOR)])
async def create_terminal(payload: TerminalIn, session: SessionDep) -> dict:
    terminal_id = str(uuid.uuid4())
    session.add(
        Terminal(
            terminal_id=terminal_id,
            terminal_name=payload.terminal_name.strip(),
            city=payload.city.strip(),
            location_address=payload.location_address,
            latitude=Decimal(str(round(payload.latitude, 6))),
            longitude=Decimal(str(round(payload.longitude, 6))),
            geofence_radius_m=payload.geofence_radius_m,
            is_staffed=payload.is_staffed,
            is_active=True,
            created_at=dt.datetime.now(APP_TZ),
        )
    )
    await session.commit()
    return {"terminal_id": terminal_id, "terminal_name": payload.terminal_name}


class RouteStopIn(BaseModel):
    terminal_id: str
    stop_sequence: int = Field(ge=1)
    offset_minutes: int = Field(default=0, ge=0)


class RouteIn(BaseModel):
    route_code: str = Field(max_length=32)
    route_name: str
    ltfrb_case_no: str | None = None
    stops: list[RouteStopIn] = Field(min_length=2)


@router.post("/routes", status_code=201, dependencies=[Depends(OPERATOR)])
async def create_route(payload: RouteIn, session: SessionDep) -> dict:
    """Create a route with its ordered stop sequence.

    The sequence must be contiguous and start at 1 -- leg k is defined as
    spanning stop k to k+1, so a gap would silently create a leg nobody can
    book across.
    """
    sequences = sorted(s.stop_sequence for s in payload.stops)
    if sequences != list(range(1, len(sequences) + 1)):
        raise ConflictError(
            "Stop sequences must be contiguous and start at 1 "
            f"(received {sequences})."
        )
    if len({s.terminal_id for s in payload.stops}) != len(payload.stops):
        raise ConflictError("A terminal cannot appear twice on one route.")

    code = payload.route_code.upper().strip()
    existing = await session.execute(select(Route).where(Route.route_code == code))
    if existing.scalar_one_or_none() is not None:
        raise ConflictError(f"Route code {code} is already in use.")

    route_id = str(uuid.uuid4())
    session.add(
        Route(
            route_id=route_id,
            route_code=code,
            route_name=payload.route_name.strip(),
            ltfrb_case_no=payload.ltfrb_case_no,
            is_active=True,
            created_at=dt.datetime.now(APP_TZ),
        )
    )
    await session.flush()

    for stop in payload.stops:
        if await session.get(Terminal, stop.terminal_id) is None:
            raise NotFoundError(f"Terminal {stop.terminal_id} not found.")
        session.add(
            RouteStop(
                route_stop_id=str(uuid.uuid4()),
                route_id=route_id,
                terminal_id=stop.terminal_id,
                stop_sequence=stop.stop_sequence,
                offset_minutes=stop.offset_minutes,
            )
        )

    await session.commit()
    return {
        "route_id": route_id,
        "route_code": code,
        "stops": len(payload.stops),
        "legs": len(payload.stops) - 1,
        "fare_pairs_required": len(payload.stops) * (len(payload.stops) - 1) // 2,
    }


# ===================================================================
# Fares
# ===================================================================
class FareIn(BaseModel):
    from_stop_sequence: int = Field(ge=1)
    to_stop_sequence: int = Field(ge=2)
    fare_amount: Decimal = Field(ge=0)
    effective_from: dt.date | None = None


class FareBulkIn(BaseModel):
    route_id: str
    fares: list[FareIn] = Field(min_length=1)


@router.post("/fares", status_code=201, dependencies=[Depends(OPERATOR)])
async def set_fares(payload: FareBulkIn, session: SessionDep) -> dict:
    """Set the pairwise fare matrix for a route.

    Fares mirror the LTFRB-approved matrix per terminal pair -- this is a
    regulatory structure, not a pricing choice, which is why it is a table
    of pairs rather than a rate formula.

    `effective_from` versions the matrix: raising fares adds rows rather
    than overwriting, so historic trips keep the fares they were sold at.
    """
    if await session.get(Route, payload.route_id) is None:
        raise NotFoundError("Route not found.")

    stops = await session.execute(
        select(RouteStop)
        .where(RouteStop.route_id == payload.route_id)
        .order_by(RouteStop.stop_sequence)
    )
    max_seq = max((s.stop_sequence for s in stops.scalars()), default=0)

    today = dt.date.today()
    created = 0
    for fare in payload.fares:
        if fare.to_stop_sequence <= fare.from_stop_sequence:
            raise ConflictError(
                f"Fare {fare.from_stop_sequence}->{fare.to_stop_sequence}: "
                "the alighting stop must come after the boarding stop."
            )
        if fare.to_stop_sequence > max_seq:
            raise ConflictError(
                f"Stop {fare.to_stop_sequence} is beyond this route "
                f"(it has {max_seq} stops)."
            )
        session.add(
            FareMatrix(
                fare_id=str(uuid.uuid4()),
                route_id=payload.route_id,
                from_stop_sequence=fare.from_stop_sequence,
                to_stop_sequence=fare.to_stop_sequence,
                fare_amount=fare.fare_amount,
                effective_from=fare.effective_from or today,
            )
        )
        created += 1

    await session.commit()
    return {"route_id": payload.route_id, "fares_created": created}


@router.get("/routes/{route_id}/fares", dependencies=[Depends(OPERATOR)])
async def list_fares(route_id: str, session: SessionDep) -> list[dict]:
    result = await session.execute(
        select(FareMatrix)
        .where(FareMatrix.route_id == route_id)
        .order_by(
            FareMatrix.from_stop_sequence,
            FareMatrix.to_stop_sequence,
            FareMatrix.effective_from.desc(),
        )
    )
    return [
        {
            "fare_id": f.fare_id,
            "from_stop_sequence": f.from_stop_sequence,
            "to_stop_sequence": f.to_stop_sequence,
            "fare_amount": f.fare_amount,
            "effective_from": f.effective_from,
        }
        for f in result.scalars()
    ]


# ===================================================================
# Schedule templates
# ===================================================================
class TemplateIn(BaseModel):
    route_id: str
    departure_time: dt.time
    # Monday-first 7-char mask: '1111100' = weekdays only.
    days_of_week: str = Field(default="1111111", pattern="^[01]{7}$")
    default_van_id: str | None = None
    default_driver_id: str | None = None
    default_conductor_id: str | None = None
    trip_label: str | None = None
    valid_from: dt.date | None = None
    valid_until: dt.date | None = None


@router.get("/schedule-templates", dependencies=[Depends(OPERATOR)])
async def list_templates(session: SessionDep) -> list[dict]:
    result = await session.execute(
        select(ScheduleTemplate).order_by(ScheduleTemplate.departure_time)
    )
    return [
        {
            "template_id": t.template_id,
            "route_id": t.route_id,
            "departure_time": str(t.departure_time),
            "days_of_week": t.days_of_week,
            "trip_label": t.trip_label,
            "default_van_id": t.default_van_id,
            "is_active": t.is_active,
            "valid_from": t.valid_from,
            "valid_until": t.valid_until,
        }
        for t in result.scalars()
    ]


@router.post("/schedule-templates", status_code=201,
             dependencies=[Depends(OPERATOR)])
async def create_template(payload: TemplateIn, session: SessionDep) -> dict:
    if await session.get(Route, payload.route_id) is None:
        raise NotFoundError("Route not found.")

    template_id = str(uuid.uuid4())
    session.add(
        ScheduleTemplate(
            template_id=template_id,
            route_id=payload.route_id,
            departure_time=payload.departure_time,
            days_of_week=payload.days_of_week,
            default_van_id=payload.default_van_id,
            default_driver_id=payload.default_driver_id,
            default_conductor_id=payload.default_conductor_id,
            trip_label=payload.trip_label,
            is_active=True,
            valid_from=payload.valid_from or dt.date.today(),
            valid_until=payload.valid_until,
            created_at=dt.datetime.now(APP_TZ),
        )
    )
    await session.commit()
    return {"template_id": template_id, "days_of_week": payload.days_of_week}


@router.patch("/schedule-templates/{template_id}/active",
              dependencies=[Depends(OPERATOR)])
async def toggle_template(
    template_id: str, is_active: bool, session: SessionDep
) -> dict:
    template = await session.get(ScheduleTemplate, template_id)
    if template is None:
        raise NotFoundError("Template not found.")
    template.is_active = is_active
    await session.commit()
    return {"template_id": template_id, "is_active": is_active}


# ===================================================================
# Trip generation
# ===================================================================
@router.post("/trips/generate", dependencies=[Depends(OPERATOR)])
async def generate_trips(
    session: SessionDep,
    service_date: dt.date | None = None,
    days_ahead: int = Query(default=1, ge=1, le=30),
) -> list[dict]:
    """Materialise trips from active schedule templates.

    Safe to run repeatedly -- UNIQUE (template_id, service_date) makes
    re-runs idempotent, so a cron job that fires twice, or is retried after
    a partial failure, cannot duplicate a day's departures.
    """
    reports = await GenerateDailyTripsUseCase(session).execute(
        service_date=service_date, days_ahead=days_ahead
    )
    return [
        {
            "service_date": r.service_date,
            "templates_considered": r.templates_considered,
            "trips_created": r.trips_created,
            "trips_skipped": r.trips_skipped,
            "seat_legs_created": r.seat_legs_created,
            "warnings": r.warnings,
        }
        for r in reports
    ]


class SpecialTripIn(BaseModel):
    route_id: str
    departure_datetime: dt.datetime
    van_id: str | None = None
    driver_id: str | None = None
    conductor_id: str | None = None
    trip_label: str | None = None
    advance_booking_seat_cap: int | None = Field(default=None, ge=0, le=14)


@router.post("/trips/special", status_code=201, dependencies=[Depends(OPERATOR)])
async def create_special_trip(
    payload: SpecialTripIn, session: SessionDep
) -> dict:
    """Create an ad-hoc departure outside the regular schedule."""
    return await CreateSpecialTripUseCase(session).execute(
        route_id=payload.route_id,
        departure_datetime=payload.departure_datetime,
        van_id=payload.van_id,
        driver_id=payload.driver_id,
        conductor_id=payload.conductor_id,
        trip_label=payload.trip_label,
        advance_booking_seat_cap=payload.advance_booking_seat_cap,
    )
