"""Cooperative configuration: routes, fares, policies, schedules.

This is what makes the system portable. A different cooperative sets up
its own terminals, routes, fare matrix and policy values through these
endpoints -- no code change, no migration, no redeploy.
"""

from __future__ import annotations

import datetime as dt
import uuid
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy import case, func, select

from app.api.v1.deps import MANAGER, OFFICE, CurrentUser, SessionDep
from app.application.scheduling.generate_trips import (
    CreateSpecialTripUseCase,
    GenerateDailyTripsUseCase,
)
from app.application.tracking.geometry import haversine_m
from app.core.exceptions import ConflictError, InvalidInputError, NotFoundError
from app.core.timezone import APP_TZ
from app.infrastructure.models import (
    Booking,
    CooperativePolicy,
    FareMatrix,
    Operator,
    Route,
    RouteStop,
    RouteStretch,
    ScheduleTemplate,
    StaffProfile,
    Terminal,
    Trip,
    User,
)
from app.infrastructure.repositories.policy_repository import PolicyRepository

router = APIRouter(prefix="/config", tags=["configuration"])


# ===================================================================
# Policies
# ===================================================================
class PolicyOut(BaseModel):
    policy_key: str
    policy_value: str
    data_type: str
    description: str
    # In force since; who set it (NULL for values set before 021).
    effective_from: dt.datetime
    updated_by: str | None
    updated_at: dt.datetime


class PolicyIn(BaseModel):
    policy_value: str


def _policy_out(p: CooperativePolicy) -> PolicyOut:
    return PolicyOut(**{c: getattr(p, c) for c in PolicyOut.model_fields})


@router.get("/policies", response_model=list[PolicyOut],
            dependencies=[Depends(OFFICE)])
async def list_policies(session: SessionDep) -> list[PolicyOut]:
    """Every configurable cooperative policy, at the value in force now.

    These are rows precisely so a cooperative can revise them without a
    deployment -- reschedule cutoff, advance-booking cap, geofence radius,
    hold TTL, variance threshold, start window, remittance rate.
    """
    return [_policy_out(p) for p in await PolicyRepository(session).current_rows()]


@router.get("/policies/{policy_key}/history", response_model=list[PolicyOut],
            dependencies=[Depends(OFFICE)])
async def policy_history(policy_key: str, session: SessionDep) -> list[PolicyOut]:
    """Every value the key has held, newest first, with who set it."""
    return [_policy_out(p) for p in await PolicyRepository(session).history(policy_key)]


@router.put("/policies/{policy_key}", response_model=PolicyOut,
            dependencies=[Depends(MANAGER)])
async def update_policy(
    policy_key: str, payload: PolicyIn, session: SessionDep, user: CurrentUser
) -> PolicyOut:
    """Put a new value in force from now; the old one stays on record."""
    try:
        policy = await PolicyRepository(session).set(
            policy_key, payload.policy_value, user.user_id
        )
    except ValueError as exc:
        raise ConflictError(
            f"'{payload.policy_value.strip()}' is not valid for {policy_key}: {exc}."
        ) from None
    await session.commit()

    # Existing trips are unaffected: seat capacity, advance cap and
    # reschedule cutoff are snapshotted onto each trip at generation time.
    return _policy_out(policy)


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


@router.post("/terminals", status_code=201, dependencies=[Depends(MANAGER)])
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


class RouteOut(BaseModel):
    route_id: str
    route_code: str
    route_name: str
    is_active: bool
    stop_count: int


@router.get("/routes", response_model=list[RouteOut],
            dependencies=[Depends(OFFICE)])
async def list_routes(session: SessionDep) -> list[RouteOut]:
    """Routes for pickers -- dispatching a special trip, assigning a van.

    `stops` is eager-loaded (see the Route model), so this is one query,
    not N+1.
    """
    result = await session.execute(select(Route).order_by(Route.route_name))
    return [
        RouteOut(
            route_id=r.route_id,
            route_code=r.route_code,
            route_name=r.route_name,
            is_active=r.is_active,
            stop_count=len(r.stops),
        )
        for r in result.scalars()
    ]


@router.post("/routes", status_code=201, dependencies=[Depends(MANAGER)])
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


@router.post("/fares", status_code=201, dependencies=[Depends(MANAGER)])
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


@router.get("/routes/{route_id}/fares", dependencies=[Depends(OFFICE)])
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


class StretchesIn(BaseModel):
    """A2Z's speed limit for each stretch in route order, and one stop-zone
    radius for the route's stops (brief 6.3; 100 m in the sample)."""
    speed_limits_kmh: list[int] = Field(min_length=1)
    stop_zone_radius_m: int = Field(default=100, ge=1, le=2000)


class StretchOut(BaseModel):
    stretch_no: int
    from_stop: str
    to_stop: str
    from_distance_m: Decimal
    length_m: Decimal
    speed_limit_kmh: int
    stop_zone_radius_m: int
    expected_time_s: int


async def _stretches(session, route_id: str) -> list[StretchOut]:
    names = dict((await session.execute(
        select(RouteStop.stop_sequence, Terminal.terminal_name)
        .join(Terminal, Terminal.terminal_id == RouteStop.terminal_id)
        .where(RouteStop.route_id == route_id)
    )).all())
    rows = (await session.execute(
        select(RouteStretch).where(RouteStretch.route_id == route_id)
        .order_by(RouteStretch.stretch_no)
    )).scalars()
    return [StretchOut(
        stretch_no=s.stretch_no, from_stop=names[s.stretch_no], to_stop=names[s.stretch_no + 1],
        from_distance_m=s.from_distance_m, length_m=s.length_m,
        speed_limit_kmh=s.speed_limit_kmh, stop_zone_radius_m=s.stop_zone_radius_m,
        expected_time_s=s.expected_time_s,
    ) for s in rows]


@router.get("/routes/{route_id}/stretches", response_model=list[StretchOut],
            dependencies=[Depends(OFFICE)])
async def list_stretches(route_id: str, session: SessionDep) -> list[StretchOut]:
    """The route's stretches as NAHGM measures them. Empty until the
    Terminal Manager sets the speed limits: no overspeed or slow-stretch
    flag is raised on a route without them."""
    return await _stretches(session, route_id)


@router.put("/routes/{route_id}/stretches", response_model=list[StretchOut],
            dependencies=[Depends(MANAGER)])
async def set_stretches(
    route_id: str, payload: StretchesIn, session: SessionDep,
) -> list[StretchOut]:
    """Set the speed limits. Lengths are measured stop to stop along the
    straight route line, as NAHGM snaps to it; each expected time is
    (length - the stop zone at each end) / `expected_speed_kmh` in force
    now, and stays with the stretch until it is saved again."""
    stops = (await session.execute(
        select(RouteStop.stop_sequence, Terminal.latitude, Terminal.longitude)
        .join(Terminal, Terminal.terminal_id == RouteStop.terminal_id)
        .where(RouteStop.route_id == route_id).order_by(RouteStop.stop_sequence)
    )).all()
    if len(stops) < 2:
        raise NotFoundError("Route not found, or it has fewer than two stops.")
    if len(payload.speed_limits_kmh) != len(stops) - 1:
        raise InvalidInputError(
            f"The route has {len(stops) - 1} stretches: give one speed limit for each.")
    if any(not 1 <= limit <= 200 for limit in payload.speed_limits_kmh):
        raise InvalidInputError("A speed limit is between 1 and 200 km/h.")
    speed = await PolicyRepository(session).get_int("expected_speed_kmh")
    radius = payload.stop_zone_radius_m

    existing = {s.stretch_no: s for s in (await session.execute(
        select(RouteStretch).where(RouteStretch.route_id == route_id)
    )).scalars()}
    travelled = 0.0
    for (seq, alat, alon), (_, blat, blon), limit in zip(stops, stops[1:], payload.speed_limits_kmh):
        length = haversine_m(float(alat), float(alon), float(blat), float(blon))
        row = existing.get(seq) or RouteStretch(stretch_id=str(uuid.uuid4()), route_id=route_id,
                                                stretch_no=seq)
        row.from_distance_m = Decimal(f"{travelled:.2f}")
        row.length_m = Decimal(f"{length:.2f}")
        row.speed_limit_kmh = limit
        row.stop_zone_radius_m = radius
        row.expected_time_s = max(0, round((length - 2 * radius) / (speed / 3.6)))
        session.add(row)
        travelled += length
    await session.commit()
    return await _stretches(session, route_id)


# ===================================================================
# Schedule templates
# ===================================================================
class TemplateIn(BaseModel):
    route_id: str
    departure_time: dt.time
    # Monday-first 7-char mask: '1111100' = weekdays only.
    days_of_week: str = Field(default="1111111", pattern="^[01]{7}$")
    # No van or Dispatcher: the timetable has no usual crew (brief 4.2).
    trip_label: str | None = None
    valid_from: dt.date | None = None
    valid_until: dt.date | None = None


@router.get("/schedule-templates", dependencies=[Depends(OFFICE)])
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
            "is_active": t.is_active,
            "valid_from": t.valid_from,
            "valid_until": t.valid_until,
        }
        for t in result.scalars()
    ]


@router.post("/schedule-templates", status_code=201,
             dependencies=[Depends(MANAGER)])
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
              dependencies=[Depends(MANAGER)])
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
@router.post("/trips/generate", dependencies=[Depends(MANAGER)])
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
    dispatcher_id: str | None = None
    trip_label: str | None = None
    advance_booking_seat_cap: int | None = Field(default=None, ge=0, le=14)


@router.post("/trips/special", status_code=201)
async def create_special_trip(
    payload: SpecialTripIn, session: SessionDep,
    user: Annotated[User, Depends(MANAGER)],
) -> dict:
    """Create an ad-hoc departure outside the regular schedule."""
    return await CreateSpecialTripUseCase(session).execute(
        route_id=payload.route_id,
        departure_datetime=payload.departure_datetime,
        van_id=payload.van_id,
        dispatcher_id=payload.dispatcher_id,
        trip_label=payload.trip_label,
        advance_booking_seat_cap=payload.advance_booking_seat_cap,
        by=user,
    )


# ------------------------------------------------------------- trip board
class TripBoardOut(BaseModel):
    trip_id: str
    trip_label: str | None
    route_name: str
    departure_datetime: dt.datetime
    status: str
    departed_at: dt.datetime | None
    van_id: str | None
    dispatcher_id: str | None
    plate_number: str | None
    # The van's owner, who drives it. On a trip the operator is only ever
    # a name beside the plate, never a user (brief 9). From the copy made
    # at the start once the trip has started.
    operator_name: str | None
    dispatcher_name: str | None
    # The lifecycle (brief 4): who assigned and started it, and how.
    assigned_by_name: str | None
    start_opens_at: dt.datetime
    start_mode: str | None
    started_by_name: str | None
    started_at: dt.datetime | None
    start_review_status: str
    audit_status: str
    unaudited_reason: str | None
    departure_source: str | None
    payment_status: str
    change_note: str | None
    seat_capacity: int
    booked: int
    checked_in: int
    boarded: int
    no_show: int


@router.get("/trips", response_model=list[TripBoardOut], dependencies=[Depends(OFFICE)])
async def trip_board(session: SessionDep, date: dt.date | None = None) -> list[TripBoardOut]:
    """Every trip on one service date with its live status and crew -- the
    office's view of what the Dispatcher sees on each van. Per-trip detail
    is the Dispatcher's own manifest, GET /trips/{id}/manifest.

    A separate endpoint, not a column on the revenue view, because status
    is operational and the view is a reconciliation: adding it there would
    put a moving value into a figure the office signs off."""
    day = date or dt.datetime.now(APP_TZ).date()
    trips = (
        await session.execute(
            select(Trip).where(Trip.service_date == day).order_by(Trip.departure_datetime)
        )
    ).scalars().all()
    if not trips:
        return []

    ids = [t.trip_id for t in trips]
    counts = {
        row.trip_id: row
        for row in (
            await session.execute(
                select(
                    Booking.trip_id,
                    func.sum(case((Booking.status.in_(("confirmed", "checked_in", "boarded")), 1), else_=0)).label("booked"),
                    func.sum(case((Booking.status == "checked_in", 1), else_=0)).label("checked_in"),
                    func.sum(case((Booking.status == "boarded", 1), else_=0)).label("boarded"),
                    func.sum(case((Booking.status == "no_show", 1), else_=0)).label("no_show"),
                )
                .where(Booking.trip_id.in_(ids))
                .group_by(Booking.trip_id)
            )
        ).all()
    }
    people = {t.dispatcher_id for t in trips} | {t.assigned_by for t in trips} \
        | {t.started_by for t in trips}
    dispatcher_ids = people - {None}
    names = {
        p.user_id: f"{p.first_name} {p.last_name}"
        for p in (
            await session.execute(select(StaffProfile).where(StaffProfile.user_id.in_(dispatcher_ids)))
        ).scalars()
    } if dispatcher_ids else {}
    operator_ids = {t.van.operator_id for t in trips if t.van and t.van.operator_id}
    operators = {
        o.operator_id: o.full_name
        for o in (
            await session.execute(select(Operator).where(Operator.operator_id.in_(operator_ids)))
        ).scalars()
    } if operator_ids else {}

    opens = dt.timedelta(minutes=await PolicyRepository(session).get_int("start_opens_minutes"))
    out = []
    for t in trips:
        c = counts.get(t.trip_id)
        out.append(TripBoardOut(
            trip_id=t.trip_id,
            trip_label=t.trip_label,
            route_name=t.route.route_name if t.route else "Van rental",
            departure_datetime=t.departure_datetime,
            status=t.status,
            departed_at=t.departed_at,
            van_id=t.van_id,
            dispatcher_id=t.dispatcher_id,
            plate_number=t.van_plate_number or (t.van.plate_number if t.van else None),
            operator_name=t.driver_name or (operators.get(t.van.operator_id) if t.van else None),
            dispatcher_name=names.get(t.dispatcher_id),
            assigned_by_name=names.get(t.assigned_by),
            start_opens_at=t.departure_datetime - opens,
            start_mode=t.start_mode,
            started_by_name=names.get(t.started_by),
            started_at=t.started_at,
            start_review_status=t.start_review_status,
            audit_status=t.audit_status,
            unaudited_reason=t.unaudited_reason,
            departure_source=t.departure_source,
            payment_status=t.payment_status,
            change_note=t.change_note,
            seat_capacity=t.seat_capacity,
            booked=int(c.booked or 0) if c else 0,
            checked_in=int(c.checked_in or 0) if c else 0,
            boarded=int(c.boarded or 0) if c else 0,
            no_show=int(c.no_show or 0) if c else 0,
        ))
    return out
