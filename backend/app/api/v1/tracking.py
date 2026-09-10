"""Live van tracking endpoints (NAHGM)."""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, Header, Query
from pydantic import BaseModel, Field

from app.api.v1.deps import SessionDep, require_roles
from app.application.tracking.nahgm import TrackingService
from app.config import settings
from app.core.exceptions import AuthenticationError
from app.domain.enums import Role

router = APIRouter(prefix="/tracking", tags=["tracking"])

CREW = require_roles(Role.CONDUCTOR, Role.DRIVER, Role.COOP_ADMIN, Role.ADMIN)
COOP_ADMIN = require_roles(Role.COOP_ADMIN, Role.ADMIN)


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


def verify_tracker(x_tracker_key: str | None = Header(default=None)) -> None:
    """Authenticate an in-vehicle unit.

    Devices cannot hold a user session, so a shared key authenticates the
    fleet the same way the YOLOv8 node is authenticated. A per-device key
    stored against `vans.camera_device_id` would be stronger and is worth
    noting as future work -- with one shared key, a leak means re-keying
    every unit.
    """
    if not settings.tracker_api_key:
        return  # unset in development; the endpoint stays open
    if x_tracker_key != settings.tracker_api_key:
        raise AuthenticationError("Invalid tracker key.")


@router.post("/trips/{trip_id}/ping", status_code=201)
async def record_ping(
    trip_id: str,
    payload: PingRequest,
    session: SessionDep,
    _: None = Depends(verify_tracker),
) -> dict:
    """Accept one position report from an in-vehicle unit.

    Deliberately source-agnostic: the same endpoint serves a GPS dongle on
    the edge computer, a crew handset, or the replay simulator used for
    demonstration. Where the reading came from is not the API's concern.
    """
    return await TrackingService(session).record_ping(
        trip_id=trip_id,
        latitude=payload.latitude,
        longitude=payload.longitude,
        accuracy_m=payload.accuracy_m,
        speed_kph=payload.speed_kph,
        heading_deg=payload.heading_deg,
        recorded_at=payload.recorded_at,
    )


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