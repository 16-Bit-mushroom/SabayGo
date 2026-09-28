"""Trip search and detail -- how a passenger finds something to book."""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import or_, select

from app.api.v1.deps import CurrentUser, SessionDep, require_roles
from app.core import timezone as app_tz
from app.core.exceptions import NotFoundError, PolicyViolationError
from app.domain.enums import Role, TripStatus
from app.domain.value_objects import Segment
from app.infrastructure.models import FareMatrix, Route, RouteStop, Terminal, Trip
from app.infrastructure.repositories.seat_repository import SeatRepository

router = APIRouter(prefix="/trips", tags=["trips"])


class StopOut(BaseModel):
    stop_sequence: int
    terminal_id: str
    terminal_name: str
    city: str
    offset_minutes: int
    # The node's own position. NAHGM map-matches against these terminals,
    # so a client drawing the route has to plot the same nodes the server
    # measured against -- a separately sourced coordinate would put the
    # van marker beside a pin that is not the node it was matched to.
    latitude: float
    longitude: float

    @classmethod
    def from_row(cls, stop: RouteStop, terminal: Terminal) -> "StopOut":
        return cls(
            stop_sequence=stop.stop_sequence,
            terminal_id=terminal.terminal_id,
            terminal_name=terminal.terminal_name,
            city=terminal.city,
            offset_minutes=stop.offset_minutes,
            latitude=float(terminal.latitude),
            longitude=float(terminal.longitude),
        )


class TripSummary(BaseModel):
    trip_id: str
    route_name: str
    trip_label: str | None
    departure_datetime: dt.datetime
    boarding_stop: int
    alighting_stop: int
    boarding_terminal: str
    alighting_terminal: str
    fare_amount: Decimal
    seats_available: int
    plate_number: str | None
    is_special_trip: bool


class TerminalOut(BaseModel):
    terminal_id: str
    terminal_name: str
    city: str
    # Position on the FIRST route that serves this terminal. Kept for the
    # older client; a terminal has no single sequence once it sits on more
    # than one route, so new clients search by terminal_id instead.
    stop_sequence: int


@router.get("/terminals", response_model=list[TerminalOut])
async def list_terminals(session: SessionDep) -> list[TerminalOut]:
    """Distinct terminals on any active route -- populates the pickers.

    One row per terminal, not per route stop: Ecoland is stop 1 on every
    outbound route and must appear once. Ordered by how early it appears
    on a route, then by name, so a picker still reads roughly outward.
    """
    result = await session.execute(
        select(RouteStop, Terminal, Route.is_active)
        .join(Terminal, Terminal.terminal_id == RouteStop.terminal_id)
        .join(Route, Route.route_id == RouteStop.route_id)
        .where(Terminal.is_active.is_(True), Route.is_active.is_(True))
        .order_by(RouteStop.stop_sequence, Terminal.terminal_name)
    )
    seen: dict[str, TerminalOut] = {}
    for rs, t, _ in result.all():
        if t.terminal_id in seen:
            continue
        seen[t.terminal_id] = TerminalOut(
            terminal_id=t.terminal_id,
            terminal_name=t.terminal_name,
            city=t.city,
            stop_sequence=rs.stop_sequence,
        )
    return list(seen.values())


async def _segments_between(
    session: SessionDep, origin_terminal_id: str, destination_terminal_id: str
) -> dict[str, tuple[int, int]]:
    """route_id -> (boarding_seq, alighting_seq) for every route that passes
    the origin before the destination. Empty when no route links them in
    that direction -- the reverse direction is a different LTFRB route."""
    rows = await session.execute(
        select(RouteStop.route_id, RouteStop.terminal_id, RouteStop.stop_sequence)
        .join(Route, Route.route_id == RouteStop.route_id)
        .where(
            Route.is_active.is_(True),
            RouteStop.terminal_id.in_([origin_terminal_id, destination_terminal_id]),
        )
    )
    by_route: dict[str, dict[str, int]] = {}
    for route_id, terminal_id, seq in rows.all():
        by_route.setdefault(route_id, {})[terminal_id] = seq
    out: dict[str, tuple[int, int]] = {}
    for route_id, seqs in by_route.items():
        a, b = seqs.get(origin_terminal_id), seqs.get(destination_terminal_id)
        if a is not None and b is not None and a < b:
            out[route_id] = (a, b)
    return out


@router.get("/search", response_model=list[TripSummary])
async def search_trips(
    session: SessionDep,
    origin_terminal_id: str | None = None,
    destination_terminal_id: str | None = None,
    boarding_stop: int | None = Query(None, ge=1),
    alighting_stop: int | None = Query(None, ge=2),
    route_id: str | None = None,
    service_date: dt.date | None = None,
) -> list[TripSummary]:
    """Find bookable trips between two terminals on a given date.

    Pass `origin_terminal_id` + `destination_terminal_id`; the server works
    out, per route, which stop sequences those are. A terminal is stop 2
    on one route and stop 5 on another, so raw sequence numbers only make
    sense once a route is known. `boarding_stop`/`alighting_stop` remain
    for the older client and the test scripts and apply the same pair to
    every route -- fine with one route, ambiguous with several -- unless
    `route_id` pins them, which is what reschedule does: same journey,
    same route, different departure.

    `seats_available` is a non-locking read -- a display hint, not a
    reservation. Availability can change between this call and the reserve
    call, which is exactly why the authoritative check happens under lock
    in allocate_seat() rather than here.
    """
    target = service_date or app_tz.now().date()

    segment_by_route: dict[str, tuple[int, int]] | None
    if origin_terminal_id and destination_terminal_id:
        segment_by_route = await _segments_between(
            session, origin_terminal_id, destination_terminal_id
        )
        if not segment_by_route:
            return []
    elif boarding_stop is not None and alighting_stop is not None:
        Segment(boarding_stop, alighting_stop)  # validates the pair
        segment_by_route = None
    else:
        raise PolicyViolationError(
            "Pass origin_terminal_id and destination_terminal_id."
        )

    where = [
        Trip.service_date == target,
        Trip.status == TripStatus.SCHEDULED.value,
        Trip.departure_datetime > app_tz.now().replace(tzinfo=None),
    ]
    if segment_by_route is not None:
        where.append(Trip.route_id.in_(segment_by_route))
    if route_id is not None:
        where.append(Trip.route_id == route_id)
    result = await session.execute(
        select(Trip).where(*where).order_by(Trip.departure_datetime)
    )
    trips = list(result.scalars().all())
    if not trips:
        return []

    stop_names = await _stop_name_map(session)
    seats = SeatRepository(session)
    out: list[TripSummary] = []

    for trip in trips:
        if segment_by_route is not None:
            boarding_stop, alighting_stop = segment_by_route[trip.route_id]
        segment = Segment(boarding_stop, alighting_stop)
        fare = await session.execute(
            select(FareMatrix)
            .where(
                FareMatrix.route_id == trip.route_id,
                FareMatrix.from_stop_sequence == boarding_stop,
                FareMatrix.to_stop_sequence == alighting_stop,
            )
            .order_by(FareMatrix.effective_from.desc())
            .limit(1)
        )
        fare_row = fare.scalar_one_or_none()
        if fare_row is None:
            continue  # route does not serve this pair

        available = await seats.count_available(trip_id=trip.trip_id, segment=segment)

        out.append(
            TripSummary(
                trip_id=trip.trip_id,
                route_name=trip.route.route_name if trip.route else "",
                trip_label=trip.trip_label,
                departure_datetime=trip.departure_datetime,
                boarding_stop=boarding_stop,
                alighting_stop=alighting_stop,
                boarding_terminal=stop_names.get((trip.route_id, boarding_stop), ""),
                alighting_terminal=stop_names.get((trip.route_id, alighting_stop), ""),
                fare_amount=fare_row.fare_amount,
                seats_available=available,
                plate_number=trip.van.plate_number if trip.van else None,
                is_special_trip=trip.is_special_trip,
            )
        )
    return out


class AssignedTrip(BaseModel):
    trip_id: str
    trip_label: str | None
    route_name: str
    service_date: dt.date
    departure_datetime: dt.datetime
    status: str
    plate_number: str | None
    seat_capacity: int
    role_on_trip: str
    stops: list[StopOut]


@router.get(
    "/assigned",
    response_model=list[AssignedTrip],
    dependencies=[Depends(require_roles(Role.CONDUCTOR, Role.DRIVER))],
)
async def assigned_trips(session: SessionDep, user: CurrentUser) -> list[AssignedTrip]:
    """The trips this crew member is rostered to, today onward.

    This list is the boundary of what the crew app can act on: every
    scan, walk-in and headcount is guarded server-side by the same
    assignment, so there is no point offering a trip the guard would
    refuse. Stops ride along because the scanner and the walk-in form
    need the sequence numbers immediately.
    """
    today = app_tz.now().date()
    result = await session.execute(
        select(Trip)
        .where(
            or_(Trip.conductor_id == user.user_id, Trip.driver_id == user.user_id),
            Trip.service_date >= today,
            Trip.status != TripStatus.CANCELLED.value,
        )
        .order_by(Trip.departure_datetime)
        .limit(20)
    )
    trips = result.scalars().all()

    route_ids = {t.route_id for t in trips}
    stops_by_route: dict[str, list[StopOut]] = {}
    if route_ids:
        rows = await session.execute(
            select(RouteStop, Terminal)
            .join(Terminal, Terminal.terminal_id == RouteStop.terminal_id)
            .where(RouteStop.route_id.in_(route_ids))
            .order_by(RouteStop.route_id, RouteStop.stop_sequence)
        )
        for rs, t in rows.all():
            stops_by_route.setdefault(rs.route_id, []).append(
                StopOut.from_row(rs, t)
            )

    return [
        AssignedTrip(
            trip_id=t.trip_id,
            trip_label=t.trip_label,
            route_name=t.route.route_name if t.route else "",
            service_date=t.service_date,
            departure_datetime=t.departure_datetime,
            status=t.status,
            plate_number=t.van.plate_number if t.van else None,
            seat_capacity=t.seat_capacity,
            role_on_trip="driver" if t.driver_id == user.user_id else "conductor",
            stops=stops_by_route.get(t.route_id, []),
        )
        for t in trips
    ]


@router.get("/{trip_id}/stops", response_model=list[StopOut])
async def trip_stops(trip_id: str, session: SessionDep) -> list[StopOut]:
    trip = await session.get(Trip, trip_id)
    if trip is None:
        raise NotFoundError("Trip not found.")

    result = await session.execute(
        select(RouteStop, Terminal)
        .join(Terminal, Terminal.terminal_id == RouteStop.terminal_id)
        .where(RouteStop.route_id == trip.route_id)
        .order_by(RouteStop.stop_sequence)
    )
    return [StopOut.from_row(rs, t) for rs, t in result.all()]


async def _stop_name_map(session: SessionDep) -> dict[tuple[str, int], str]:
    """(route_id, stop_sequence) -> terminal name. Keyed by route because
    the same sequence number is a different terminal on every route."""
    result = await session.execute(
        select(RouteStop.route_id, RouteStop.stop_sequence, Terminal.terminal_name).join(
            Terminal, Terminal.terminal_id == RouteStop.terminal_id
        )
    )
    return {(rid, seq): name for rid, seq, name in result.all()}
