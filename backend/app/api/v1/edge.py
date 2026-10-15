"""The edge phone's API (brief step 5).

Not a user session: each phone sends its own token in `X-Device-Token`,
issued when the Terminal Manager adds it to the pool. A retired phone, or
one whose token was re-issued, is refused. Everything is a batch, because
the phone stores what it sees while offline and sends it on reconnecting;
sending the same batch again changes nothing.

    GET  /edge/session              server time (for the clock), the
                                    phone's van and Dispatcher, the gap,
                                    and whether to count or pause
    POST /edge/heartbeats           status reports
    POST /edge/events               door events
    PUT  /edge/events/{id}/snapshot the blurred still of one event
    POST /edge/fixes                GPS readings
"""

from __future__ import annotations

import datetime as dt
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, File, Header, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import select

from app.api.v1.deps import SessionDep
from app.application.edge.ingestion import (
    MAX_SNAPSHOT_BYTES,
    DoorEvent,
    EdgeIngestion,
    Fix,
    Report,
)
from app.application.edge.ledger import trip_for
from app.core import timezone as app_tz
from app.core.exceptions import AuthenticationError
from app.core.security import hash_device_token
from app.infrastructure.models import DeviceCheckout, EdgeDevice, StaffProfile, Van
from app.infrastructure.repositories.policy_repository import PolicyRepository

router = APIRouter(prefix="/edge", tags=["edge phone"])

MAX_BATCH = 500


async def current_device(
    session: SessionDep, x_device_token: Annotated[str | None, Header()] = None,
) -> EdgeDevice:
    if not x_device_token:
        raise AuthenticationError("Missing X-Device-Token.")
    device = (await session.execute(
        select(EdgeDevice).where(EdgeDevice.token_hash == hash_device_token(x_device_token))
    )).scalar_one_or_none()
    if device is None or device.status == "retired":
        raise AuthenticationError("This phone's token is not valid. Ask the office for a new one.")
    return device


Device = Annotated[EdgeDevice, Depends(current_device)]


# ------------------------------------------------------------- session
class SessionOut(BaseModel):
    # The phone sets its clock offset from this; every timestamp it sends
    # must be in this clock (Manila time).
    server_time: dt.datetime
    device_id: str
    status: str
    heartbeat_gap_seconds: int
    # Shown at mounting, so the Dispatcher can check the phone is in the
    # van the office recorded.
    van_id: str | None
    plate_number: str | None
    dispatcher_name: str | None
    # Count from the van's assignment until it arrives; pause otherwise,
    # and ask again (rule 13). The way back is not counted.
    counting: bool
    trip_id: str | None


@router.get("/session", response_model=SessionOut)
async def edge_session(session: SessionDep, device: Device) -> SessionOut:
    row = (await session.execute(
        select(DeviceCheckout, Van.plate_number, StaffProfile.first_name, StaffProfile.last_name)
        .join(Van, Van.van_id == DeviceCheckout.van_id)
        .join(StaffProfile, StaffProfile.user_id == DeviceCheckout.dispatcher_id)
        .where(DeviceCheckout.device_id == device.device_id,
               DeviceCheckout.returned_at.is_(None))
    )).first()
    checkout, plate, first, last = row if row else (None, None, None, None)
    now = app_tz.now().replace(tzinfo=None)
    trip = await trip_for(session, checkout.van_id, now) if checkout else None
    return SessionOut(
        server_time=now,
        device_id=device.device_id,
        status=device.status,
        heartbeat_gap_seconds=await PolicyRepository(session).get_int("heartbeat_gap_seconds"),
        van_id=checkout.van_id if checkout else None,
        plate_number=plate,
        dispatcher_name=f"{first} {last}" if checkout else None,
        counting=trip is not None,
        trip_id=trip.trip_id if trip else None,
    )


# ---------------------------------------------------------- heartbeats
class HeartbeatIn(BaseModel):
    recorded_at: dt.datetime
    camera_ok: bool
    gps_ok: bool
    lens_blocked: bool = False
    battery_pct: int | None = Field(default=None, ge=0, le=100)
    battery_temp_c: float | None = Field(default=None, ge=-20, le=99)
    charging: bool | None = None
    detection_rate_hz: float | None = Field(default=None, ge=0, le=999)


class HeartbeatBatch(BaseModel):
    reports: list[HeartbeatIn] = Field(min_length=1, max_length=MAX_BATCH)


@router.post("/heartbeats")
async def heartbeats(payload: HeartbeatBatch, session: SessionDep, device: Device) -> dict:
    """Status reports, live or stored while offline. A stored batch that
    shows the camera and GPS working through a silence keeps the trip
    Audited (brief 4.4)."""
    return await EdgeIngestion(session, device).heartbeats(
        [Report(**r.model_dump()) for r in payload.reports]
    )


# -------------------------------------------------------------- events
class DoorEventIn(BaseModel):
    # Generated on the phone: the key that makes a resend harmless.
    event_id: str = Field(min_length=36, max_length=36)
    event_type: Literal["board", "alight"]
    event_at: dt.datetime
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    # The count aboard after this event, as the phone reckons it.
    occupancy_after: int | None = Field(default=None, ge=0, le=255)
    # The tracker's id within the trip; not a passenger identity (5.2).
    track_id: int | None = Field(default=None, ge=0)
    # SHA-256 of the blurred still, when there is one: it is chained with
    # the event, and the image uploaded later must match it.
    snapshot_hash: str | None = Field(default=None, pattern="^[0-9a-f]{64}$")


class DoorEventBatch(BaseModel):
    events: list[DoorEventIn] = Field(min_length=1, max_length=MAX_BATCH)


@router.post("/events")
async def door_events(payload: DoorEventBatch, session: SessionDep, device: Device) -> dict:
    """Door events. Each goes on the trip of the phone's van at its time;
    with no such trip it is held until one starts (rule 12). 'ignored' are
    events from before the phone's check-out or after its return."""
    return await EdgeIngestion(session, device).events(
        [DoorEvent(**e.model_dump()) for e in payload.events]
    )


@router.put("/events/{event_id}/snapshot")
async def snapshot(
    event_id: str, session: SessionDep, device: Device, image: UploadFile = File(...),
) -> dict:
    """The blurred cabin still for one event; blurred on the phone, never
    video. Stored outside the public media folder."""
    data = await image.read(MAX_SNAPSHOT_BYTES + 1)
    return await EdgeIngestion(session, device).snapshot(event_id, data)


# ---------------------------------------------------------------- GPS
class FixIn(BaseModel):
    recorded_at: dt.datetime
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy_m: float | None = Field(default=None, ge=0)
    speed_kph: float | None = Field(default=None, ge=0, le=200)
    heading_deg: float | None = Field(default=None, ge=0, lt=360)


class FixBatch(BaseModel):
    fixes: list[FixIn] = Field(min_length=1, max_length=MAX_BATCH)


@router.post("/fixes")
async def fixes(payload: FixBatch, session: SessionDep, device: Device) -> dict:
    """GPS readings from the phone's receiver. They go on the trip of its
    van by time, through the same tracking as before; leaving a terminal
    with passengers aboard can start and depart a trip (rules 7, 9)."""
    return await EdgeIngestion(session, device).fixes(
        [Fix(**f.model_dump()) for f in payload.fixes]
    )
