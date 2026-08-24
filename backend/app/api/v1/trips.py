"""Trip search and detail -- how a passenger finds something to book."""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from fastapi import APIRouter, Query
from pydantic import BaseModel
from sqlalchemy import select

from app.api.v1.deps import SessionDep
from app.core.exceptions import NotFoundError
from app.domain.enums import TripStatus
from app.domain.value_objects import Segment
from app.infrastructure.models import FareMatrix, RouteStop, Terminal, Trip
from app.infrastructure.repositories.seat_repository import SeatRepository

router = APIRouter(prefix="/trips", tags=["trips"])


class StopOut(BaseModel):
    stop_sequence: int
    terminal_id: str
    terminal_name: str
    city: str
    offset_minutes: int


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
    stop_sequence: int


@router.get("/terminals", response_model=list[TerminalOut])
async def list_terminals(session: SessionDep) -> list[TerminalOut]:
    """Terminals in route order -- populates the origin/destination pickers."""
    result = await session.execute(
        select(RouteStop, Terminal)
        .join(Terminal, Terminal.terminal_id == RouteStop.terminal_id)
        .where(Terminal.is_active.is_(True))
        .order_by(RouteStop.stop_sequence)
    )
    return [
        TerminalOut(
            terminal_id=t.terminal_id,
            terminal_name=t.terminal_name,
            city=t.city,
            stop_sequence=rs.stop_sequence,
        )
        for rs, t in result.all()
    ]


@router.get("/search", response_model=list[TripSummary])
async def search_trips(
    session: SessionDep,
    boarding_stop: int = Query(ge=1),
    alighting_stop: int = Query(ge=2),
    service_date: dt.date | None = None,
) -> list[TripSummary]:
    """Find bookable trips covering a segment on a given date.

    `seats_available` is a non-locking read -- a display hint, not a
    reservation. Availability can change between this call and the reserve
    call, which is exactly why the authoritative check happens under lock
    in allocate_seat() rather than here.
    """
    segment = Segment(boarding_stop, alighting_stop)
    target = service_date or dt.date.today()

    result = await session.execute(
        select(Trip)
        .where(
            Trip.service_date == target,
            Trip.status == TripStatus.SCHEDULED.value,
            Trip.departure_datetime > dt.datetime.now(),
        )
        .order_by(Trip.departure_datetime)
    )
    trips = list(result.scalars().all())
    if not trips:
        return []

    stop_names = await _stop_name_map(session)
    seats = SeatRepository(session)
    out: list[TripSummary] = []

    for trip in trips:
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
                boarding_terminal=stop_names.get(boarding_stop, ""),
                alighting_terminal=stop_names.get(alighting_stop, ""),
                fare_amount=fare_row.fare_amount,
                seats_available=available,
                plate_number=trip.van.plate_number if trip.van else None,
                is_special_trip=trip.is_special_trip,
            )
        )
    return out


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
    return [
        StopOut(
            stop_sequence=rs.stop_sequence,
            terminal_id=t.terminal_id,
            terminal_name=t.terminal_name,
            city=t.city,
            offset_minutes=rs.offset_minutes,
        )
        for rs, t in result.all()
    ]


async def _stop_name_map(session: SessionDep) -> dict[int, str]:
    result = await session.execute(
        select(RouteStop.stop_sequence, Terminal.terminal_name).join(
            Terminal, Terminal.terminal_id == RouteStop.terminal_id
        )
    )
    return {seq: name for seq, name in result.all()}
