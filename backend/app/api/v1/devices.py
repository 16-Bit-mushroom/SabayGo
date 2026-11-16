"""The terminal's phone pool (brief 5.5; Tables 37 and 38).

The in-van edge phones are kept in the office. The Terminal Manager adds
a phone to the pool; the Cashier or the Terminal Manager checks it out to
a Dispatcher and a van after the setup check, and records its return and
condition. A phone is out with at most one van and a van has at most one
phone out: the server will match every door event to a van through the
open check-out, so two would make that match ambiguous. The database
enforces both (functional unique indexes, 018); the checks here say why.

The setup check is a person looking at the phone. What the server knows
is the phone's own last status report, which comes back as warnings and
never as a refusal: no phone check blocks the service (brief 4.4).

Each phone authenticates its uploads (api/v1/edge.py) with its own token,
shown once when the phone is added and again only when the Terminal
Manager issues a new one, which revokes the old.
"""

from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import case, func, select

from app.api.v1.deps import MANAGER, OFFICE, CurrentUser, SessionDep
from app.core.db import commit_or_conflict
from app.core.exceptions import ConflictError, NotFoundError
from app.core.security import new_device_token
from app.core.timezone import now
from app.domain.enums import Role
from app.infrastructure.models import (
    Booking,
    DeviceCheckout,
    DeviceHeartbeat,
    EdgeDevice,
    PassengerEvent,
    StaffProfile,
    Trip,
    User,
    Van,
)
from app.infrastructure.repositories.policy_repository import PolicyRepository

router = APIRouter(prefix="/devices", tags=["devices"])


def _now() -> dt.datetime:
    return now().replace(tzinfo=None)


class DeviceIn(BaseModel):
    device_model: str = Field(min_length=2, max_length=100)
    android_version: str | None = Field(default=None, max_length=20)
    app_version: str | None = Field(default=None, max_length=20)


class CheckoutIn(BaseModel):
    van_id: str
    dispatcher_id: str


class ReturnIn(BaseModel):
    # The phone's condition on return.
    return_note: str | None = Field(default=None, max_length=255)


class CheckoutOut(BaseModel):
    checkout_id: str
    van_id: str
    plate_number: str
    dispatcher_id: str
    dispatcher_name: str
    checked_out_by: str
    checked_out_at: dt.datetime


class DeviceOut(BaseModel):
    device_id: str
    device_model: str
    android_version: str | None
    app_version: str | None
    status: str
    registered_by: str
    registered_at: dt.datetime
    last_heartbeat_at: dt.datetime | None
    battery_pct: int | None
    battery_temp_c: float | None
    camera_ok: bool | None
    gps_ok: bool | None
    # No report within heartbeat_gap_seconds, or none ever.
    silent: bool
    checkout: CheckoutOut | None


class DeviceWithToken(DeviceOut):
    # Shown once. Enter it in the edge app; the server keeps only a hash.
    device_token: str


class CheckoutResult(BaseModel):
    device: DeviceOut
    warnings: list[str]


async def _open_checkouts(session, device_ids: list[str]) -> dict[str, CheckoutOut]:
    if not device_ids:
        return {}
    result = await session.execute(
        select(DeviceCheckout, Van.plate_number, StaffProfile.first_name,
               StaffProfile.last_name)
        .join(Van, Van.van_id == DeviceCheckout.van_id)
        .join(StaffProfile, StaffProfile.user_id == DeviceCheckout.dispatcher_id)
        .where(DeviceCheckout.device_id.in_(device_ids),
               DeviceCheckout.returned_at.is_(None))
    )
    return {
        c.device_id: CheckoutOut(
            checkout_id=c.checkout_id, van_id=c.van_id, plate_number=plate,
            dispatcher_id=c.dispatcher_id, dispatcher_name=f"{first} {last}",
            checked_out_by=c.checked_out_by, checked_out_at=c.checked_out_at,
        )
        for c, plate, first, last in result.all()
    }


async def _out(session, devices: list[EdgeDevice]) -> list[DeviceOut]:
    gap = dt.timedelta(
        seconds=await PolicyRepository(session).get_int("heartbeat_gap_seconds")
    )
    checkouts = await _open_checkouts(session, [d.device_id for d in devices])
    at = _now()
    return [
        DeviceOut(
            **{c: getattr(d, c) for c in DeviceOut.model_fields if hasattr(EdgeDevice, c)},
            silent=d.last_heartbeat_at is None or at - d.last_heartbeat_at > gap,
            checkout=checkouts.get(d.device_id),
        )
        for d in devices
    ]


async def _device(session, device_id: str) -> EdgeDevice:
    device = await session.get(EdgeDevice, device_id)
    if device is None:
        raise NotFoundError("Phone not found.")
    return device


@router.get("", response_model=list[DeviceOut], dependencies=[Depends(OFFICE)])
async def list_devices(session: SessionDep, include_retired: bool = False) -> list[DeviceOut]:
    stmt = select(EdgeDevice).order_by(EdgeDevice.registered_at)
    if not include_retired:
        stmt = stmt.where(EdgeDevice.status != "retired")
    return await _out(session, list((await session.execute(stmt)).scalars()))


@router.post("", response_model=DeviceWithToken, status_code=201,
             dependencies=[Depends(MANAGER)])
async def add_device(payload: DeviceIn, session: SessionDep, user: CurrentUser) -> DeviceWithToken:
    """Add a phone to the pool: the Terminal Manager only (brief 3)."""
    token, token_hash = new_device_token()
    device = EdgeDevice(
        device_id=str(uuid.uuid4()),
        **payload.model_dump(),
        status="in_office",
        token_hash=token_hash,
        token_issued_at=_now(),
        registered_by=user.user_id,
        registered_at=_now(),
    )
    session.add(device)
    await session.commit()
    out = (await _out(session, [device]))[0]
    return DeviceWithToken(**out.model_dump(), device_token=token)


@router.post("/{device_id}/token", response_model=DeviceWithToken,
             dependencies=[Depends(MANAGER)])
async def reissue_token(device_id: str, session: SessionDep) -> DeviceWithToken:
    """A new token for the phone; the old one stops working at once (a
    lost or reset phone)."""
    device = await _device(session, device_id)
    if device.status == "retired":
        raise ConflictError("A retired phone gets no token.")
    token, device.token_hash = new_device_token()
    device.token_issued_at = _now()
    await session.commit()
    out = (await _out(session, [device]))[0]
    return DeviceWithToken(**out.model_dump(), device_token=token)


@router.post("/{device_id}/checkout", response_model=CheckoutResult,
             dependencies=[Depends(OFFICE)])
async def check_out(
    device_id: str, payload: CheckoutIn, session: SessionDep, user: CurrentUser
) -> CheckoutResult:
    """Record a phone leaving the office with a Dispatcher for a van."""
    device = await _device(session, device_id)
    if device.status == "retired":
        raise ConflictError("This phone is retired.")
    if device.status == "checked_out":
        raise ConflictError("This phone is already out. Record its return first.")
    van = await session.get(Van, payload.van_id)
    if van is None:
        raise NotFoundError("Van not found.")
    dispatcher = await session.get(User, payload.dispatcher_id)
    if dispatcher is None or dispatcher.role != Role.DISPATCHER.value:
        raise NotFoundError("Dispatcher not found.")
    if dispatcher.account_status != "active":
        raise ConflictError(f"That Dispatcher's account is {dispatcher.account_status}.")
    other = (await session.execute(
        select(DeviceCheckout.checkout_id).where(
            DeviceCheckout.van_id == van.van_id, DeviceCheckout.returned_at.is_(None)
        )
    )).first()
    if other is not None:
        raise ConflictError(
            f"Van {van.plate_number} already has a phone out. Record its return first."
        )

    session.add(DeviceCheckout(
        checkout_id=str(uuid.uuid4()),
        device_id=device_id,
        van_id=van.van_id,
        dispatcher_id=dispatcher.user_id,
        checked_out_by=user.user_id,
        checked_out_at=_now(),
    ))
    device.status = "checked_out"
    await commit_or_conflict(
        session, "That phone or van was checked out a moment ago. Refresh the list."
    )

    out = (await _out(session, [device]))[0]
    warnings = []
    if device.last_heartbeat_at is None:
        warnings.append("This phone has never sent a status report: "
                        "check that the SabayGo edge app is open.")
    elif out.silent:
        warnings.append("This phone has not reported recently: check that the "
                        "edge app is open and the phone has signal.")
    if device.camera_ok is False:
        warnings.append("The phone's last report says its camera is not working.")
    if device.gps_ok is False:
        warnings.append("The phone's last report says its GPS is not working.")
    return CheckoutResult(device=out, warnings=warnings)


@router.post("/{device_id}/return", response_model=DeviceOut,
             dependencies=[Depends(OFFICE)])
async def check_in(
    device_id: str, payload: ReturnIn, session: SessionDep, user: CurrentUser
) -> DeviceOut:
    """Record the phone back in the office, with its condition."""
    device = await _device(session, device_id)
    checkout = (await session.execute(
        select(DeviceCheckout)
        .where(DeviceCheckout.device_id == device_id,
               DeviceCheckout.returned_at.is_(None))
        .with_for_update()
    )).scalar_one_or_none()
    if checkout is None:
        raise ConflictError("This phone is not checked out.")
    checkout.returned_by = user.user_id
    checkout.returned_at = _now()
    checkout.return_note = (payload.return_note or "").strip() or None
    device.status = "in_office"
    await session.commit()
    return (await _out(session, [device]))[0]


@router.post("/{device_id}/retire", response_model=DeviceOut,
             dependencies=[Depends(MANAGER)])
async def retire(device_id: str, session: SessionDep) -> DeviceOut:
    """Take a phone out of the pool for good. The row stays: its door
    events and check-outs still name it."""
    device = await _device(session, device_id)
    if device.status == "checked_out":
        raise ConflictError("Record the phone's return before retiring it.")
    device.status = "retired"
    device.token_hash = None  # it uploads nothing more
    await session.commit()
    return (await _out(session, [device]))[0]


# ------------------------------------------------------------- live monitor
# The door cameras as the Terminal Manager watches them (12 Nov, the
# owner's decision): each phone's latest report, the last two hours of
# reports for a chart, today's door counts, and the trip its van is on.
# Only what the phone reported: a reading it did not send is None, never a
# zero (the rule the whole design keeps -- no fabricated count).
class ReportPoint(BaseModel):
    at: dt.datetime
    detection_rate_hz: float | None
    battery_temp_c: float | None
    battery_pct: int | None


class LiveTrip(BaseModel):
    trip_id: str
    departure_datetime: dt.datetime
    trip_label: str | None
    status: str
    listed: int
    boarded: int
    alighted: int
    aboard: int


class DeviceLiveOut(DeviceOut):
    charging: bool | None
    lens_blocked: bool | None
    detection_rate_hz: float | None
    report_count_window: int
    history: list[ReportPoint]
    boarded_today: int
    alighted_today: int
    trip: LiveTrip | None


@router.get("/live", response_model=list[DeviceLiveOut], dependencies=[Depends(OFFICE)])
async def live_devices(session: SessionDep, minutes: int = 120) -> list[DeviceLiveOut]:
    minutes = max(10, min(minutes, 720))
    devices = list((await session.execute(
        select(EdgeDevice).where(EdgeDevice.status != "retired").order_by(EdgeDevice.registered_at)
    )).scalars())
    base = {d.device_id: d for d in await _out(session, devices)}
    at = _now()
    since = at - dt.timedelta(minutes=minutes)
    today = at.date()
    out: list[DeviceLiveOut] = []
    for device in devices:
        reports = list((await session.execute(
            select(DeviceHeartbeat)
            .where(DeviceHeartbeat.device_id == device.device_id, DeviceHeartbeat.recorded_at >= since)
            .order_by(DeviceHeartbeat.recorded_at)
        )).scalars())
        latest = reports[-1] if reports else (await session.execute(
            select(DeviceHeartbeat).where(DeviceHeartbeat.device_id == device.device_id)
            .order_by(DeviceHeartbeat.recorded_at.desc()).limit(1)
        )).scalar_one_or_none()
        # At most 60 points for the chart, evenly picked, the last kept.
        step = max(1, len(reports) // 60)
        picked = reports[::step]
        if reports and picked[-1] is not reports[-1]:
            picked.append(reports[-1])
        history = [
            ReportPoint(
                at=r.recorded_at,
                detection_rate_hz=None if r.detection_rate_hz is None else float(r.detection_rate_hz),
                battery_temp_c=None if r.battery_temp_c is None else float(r.battery_temp_c),
                battery_pct=r.battery_pct,
            )
            for r in picked
        ]
        board, alight = (await session.execute(
            select(func.coalesce(func.sum(case((PassengerEvent.event_type == "board", 1), else_=0)), 0),
                   func.coalesce(func.sum(case((PassengerEvent.event_type == "alight", 1), else_=0)), 0))
            .where(PassengerEvent.device_id == device.device_id,
                   func.date(PassengerEvent.event_at) == today)
        )).one()
        info = base[device.device_id]
        trip = await _van_trip(session, info.checkout.van_id, today) if info.checkout else None
        out.append(DeviceLiveOut(
            **info.model_dump(),
            charging=latest.charging if latest else None,
            lens_blocked=latest.lens_blocked if latest else None,
            detection_rate_hz=(None if latest is None or latest.detection_rate_hz is None
                               else float(latest.detection_rate_hz)),
            report_count_window=len(reports),
            history=history,
            boarded_today=int(board),
            alighted_today=int(alight),
            trip=trip,
        ))
    return out


async def _van_trip(session, van_id: str, today: dt.date) -> LiveTrip | None:
    """The van's trip that matters now: one boarding or on the road, else
    today's next one still to leave, else today's last."""
    trips = list((await session.execute(
        select(Trip).where(Trip.van_id == van_id, Trip.service_date == today,
                           Trip.status != "cancelled")
        .order_by(Trip.departure_datetime)
    )).scalars())
    if not trips:
        return None
    live = [t for t in trips if t.status in ("boarding", "departed")]
    ahead = [t for t in trips if t.status == "scheduled" and t.departure_datetime >= _now()]
    trip = (live or ahead or trips[-1:])[0]
    listed = await session.scalar(
        select(func.count()).select_from(Booking).where(
            Booking.trip_id == trip.trip_id,
            Booking.status.in_(("confirmed", "checked_in", "boarded", "completed")),
            Booking.payment_status == "paid",
        ))
    board, alight = (await session.execute(
        select(func.coalesce(func.sum(case((PassengerEvent.event_type == "board", 1), else_=0)), 0),
               func.coalesce(func.sum(case((PassengerEvent.event_type == "alight", 1), else_=0)), 0))
        .where(PassengerEvent.trip_id == trip.trip_id)
    )).one()
    return LiveTrip(
        trip_id=trip.trip_id, departure_datetime=trip.departure_datetime, trip_label=trip.trip_label,
        status=trip.status, listed=int(listed or 0), boarded=int(board), alighted=int(alight),
        aboard=max(0, int(board) - int(alight) - (1 if trip.crew_aboard else 0)),
    )
