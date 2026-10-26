"""Live van tracking endpoints (NAHGM)."""

from __future__ import annotations

import datetime as dt
import logging

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field

from app.api.v1.deps import SessionDep, require_roles
from app.application.tracking.flags import DrivingFlags
from app.application.tracking.nahgm import TrackingService
from app.config import settings
from app.core.exceptions import NotFoundError
from app.domain.enums import Role

log = logging.getLogger(__name__)

router = APIRouter(prefix="/tracking", tags=["tracking"])

CREW = require_roles(Role.DISPATCHER, Role.TERMINAL_MANAGER, Role.CASHIER, Role.ADMIN)


class PingRequest(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0)
    speed_kph: float | None = Field(default=None, ge=0, le=200)
    heading_deg: float | None = Field(default=None, ge=0, lt=360)
    # Set by the device. A unit that buffers through a dead zone and
    # uploads later must not have its history collapsed to the upload
    # moment, so the device's own clock wins.
    recorded_at: dt.datetime | None = None


class StopEtaOut(BaseModel):
    stop_sequence: int
    terminal_id: str
    terminal_name: str
    distance_m: float
    eta: dt.datetime | None
    minutes_away: int | None


class PositionOut(BaseModel):
    trip_id: str
    van_id: str | None
    plate_number: str | None
    latitude: float
    longitude: float
    speed_kph: float | None
    heading_deg: float | None
    nearest_stop_sequence: int | None
    nearest_stop_name: str | None
    distance_to_stop_m: float | None
    recorded_at: dt.datetime
    is_stale: bool
    seconds_since_report: int
    etas: list[StopEtaOut]


def development_only() -> None:
    """The ping endpoint exists in development only, for
    `scripts/tracking_simulator.py` (the demo's moving vans) and the test
    scripts. The in-van phone reports through `POST /edge/fixes` with its
    own device token, so nothing in a deployed system posts here, and an
    unauthenticated position could depart a trip or raise driving flags.
    """
    if settings.environment != "development":
        raise NotFoundError("Not found.")


@router.post("/trips/{trip_id}/ping", status_code=201)
async def record_ping(
    trip_id: str,
    payload: PingRequest,
    session: SessionDep,
    _: None = Depends(development_only),
) -> dict:
    """Accept one simulated position report (development only)."""
    stored = await TrackingService(session).record_ping(
        trip_id=trip_id,
        latitude=payload.latitude,
        longitude=payload.longitude,
        accuracy_m=payload.accuracy_m,
        speed_kph=payload.speed_kph,
        heading_deg=payload.heading_deg,
        recorded_at=payload.recorded_at,
    )
    # Brief 6.4; the reading is kept whatever happens here.
    try:
        await DrivingFlags(session).review(trip_id)
    except Exception:
        await session.rollback()
        log.exception("Driving flags failed for trip %s.", trip_id)
    return stored


@router.get("/trips/{trip_id}/position", response_model=PositionOut)
async def current_position(trip_id: str, session: SessionDep) -> PositionOut:
    """Where the van is now, and when it reaches the stops ahead.

    Unauthenticated on purpose: a passenger waiting at Digos should be
    able to see the van without an account, and the response exposes only
    a vehicle position on a public fixed route.
    """
    pos = await TrackingService(session).current_position(trip_id=trip_id)
    return PositionOut(
        **{k: v for k, v in pos.__dict__.items() if k != "etas"},
        etas=[StopEtaOut(**e.__dict__) for e in pos.etas],
    )


@router.get("/trips/{trip_id}/history")
async def track_history(
    trip_id: str, session: SessionDep, limit: int = Query(500, le=2000)
) -> list[dict]:
    """Breadcrumb trail for drawing the path travelled."""
    return await TrackingService(session).track_history(trip_id=trip_id, limit=limit)


@router.get("/fleet", dependencies=[Depends(CREW)])
async def active_fleet(session: SessionDep) -> list[dict]:
    """Every van currently reporting -- the console's fleet map."""
    return await TrackingService(session).active_fleet()