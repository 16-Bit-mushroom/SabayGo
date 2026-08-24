"""Operations endpoints: check-in, boarding, manifest, headcount."""

from __future__ import annotations

import datetime as dt
import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select

from app.api.v1.deps import CurrentUser, SessionDep, require_roles
from app.application.operations.boarding import (
    DepartTripUseCase,
    ManifestUseCase,
    ScanTicketUseCase,
)
from app.application.operations.check_in import CheckInCommand, CheckInUseCase
from app.core.exceptions import NotFoundError
from app.core.timezone import APP_TZ
from app.domain.enums import Role
from app.infrastructure.models import DriverHeadcount, Trip

router = APIRouter(tags=["operations"])

CREW = require_roles(Role.CONDUCTOR, Role.DRIVER, Role.OPERATOR)


# ----------------------------------------------------------------- check-in
class CheckInRequest(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    gps_accuracy_m: float | None = None


class CheckInResponse(BaseModel):
    check_in_id: str
    booking_id: str
    status: str
    terminal_name: str
    distance_m: float
    geofence_radius_m: int
    message: str


@router.post("/bookings/{booking_id}/check-in", response_model=CheckInResponse)
async def check_in(
    booking_id: str,
    payload: CheckInRequest,
    session: SessionDep,
    user: CurrentUser,
) -> CheckInResponse:
    """Confirm physical presence at the boarding terminal.

    The app sends a coordinate; the server decides. A client that computed
    its own geofence verdict could simply report success from anywhere.
    """
    result = await CheckInUseCase(session).execute(
        CheckInCommand(
            booking_id=booking_id,
            latitude=payload.latitude,
            longitude=payload.longitude,
            gps_accuracy_m=payload.gps_accuracy_m,
        ),
        passenger_user_id=user.user_id,
    )
    return CheckInResponse(
        check_in_id=result.check_in_id,
        booking_id=result.booking_id,
        status=result.status,
        terminal_name=result.terminal_name,
        distance_m=result.distance_m,
        geofence_radius_m=result.geofence_radius_m,
        message=f"Checked in at {result.terminal_name} ({result.distance_m:.0f}m).",
    )


# --------------------------------------------------------------------- scan
class ScanRequest(BaseModel):
    qr_payload: str
    trip_id: str
    stop_sequence: int = Field(ge=1)
    # Set by an offline client so queued scans can be ordered on sync.
    client_recorded_at: dt.datetime | None = None


class ScanResponse(BaseModel):
    scan_id: str
    result: str
    accepted: bool
    booking_id: str | None
    ticket_number: str | None
    seat_number: int | None
    boarding_stop: int | None
    alighting_stop: int | None
    message: str


@router.post("/scans", response_model=ScanResponse, dependencies=[Depends(CREW)])
async def scan_ticket(
    payload: ScanRequest, session: SessionDep, user: CurrentUser
) -> ScanResponse:
    """Validate a QR code at the van door.

    Always 200, even for an invalid ticket -- the conductor needs a verdict
    on screen, not an error dialog, while a queue waits. Read `accepted`.
    """
    result = await ScanTicketUseCase(session).execute(
        qr_payload=payload.qr_payload,
        trip_id=payload.trip_id,
        stop_sequence=payload.stop_sequence,
        scanned_by_user_id=user.user_id,
        client_recorded_at=payload.client_recorded_at,
    )
    return ScanResponse(**{k: v for k, v in result.__dict__.items()
                           if k != "passenger_name"})


# ----------------------------------------------------------------- manifest
class ManifestPassenger(BaseModel):
    booking_id: str
    ticket_number: str
    seat_number: int
    boarding_stop: int
    alighting_stop: int
    booking_type: str
    status: str
    fare_amount: Decimal
    name: str | None


class ManifestResponse(BaseModel):
    trip_id: str
    trip_label: str | None
    departure_datetime: dt.datetime
    status: str
    seat_capacity: int
    total_bookings: int
    boarded: int
    checked_in: int
    awaiting: int
    unpaid: int
    passengers: list[ManifestPassenger]


@router.get(
    "/trips/{trip_id}/manifest",
    response_model=ManifestResponse,
    dependencies=[Depends(CREW)],
)
async def manifest(trip_id: str, session: SessionDep) -> ManifestResponse:
    return ManifestResponse(**await ManifestUseCase(session).for_trip(trip_id))


# ---------------------------------------------------------------- headcount
class HeadcountRequest(BaseModel):
    stop_sequence: int = Field(ge=1)
    confirmed_count: int = Field(ge=0, le=14)


class HeadcountResponse(BaseModel):
    headcount_id: str
    trip_id: str
    stop_sequence: int
    confirmed_count: int
    manifest_count: int
    variance: int
    message: str


@router.post(
    "/trips/{trip_id}/headcount",
    response_model=HeadcountResponse,
    dependencies=[Depends(require_roles(Role.DRIVER, Role.CONDUCTOR))],
)
async def confirm_headcount(
    trip_id: str,
    payload: HeadcountRequest,
    session: SessionDep,
    user: CurrentUser,
) -> HeadcountResponse:
    """Driver confirms how many people are physically aboard.

    A single number, deliberately -- asking a driver to itemise passengers
    before departure guarantees it will not be done. This is the human
    cross-check on the YOLOv8 count: two independent observations of the
    same reality, and disagreement between them is itself a signal.
    """
    trip = await session.get(Trip, trip_id)
    if trip is None:
        raise NotFoundError("Trip not found.")

    manifest_count = await ManifestUseCase(session).booked_count_on_leg(
        trip_id, payload.stop_sequence
    )
    variance = payload.confirmed_count - manifest_count

    now = dt.datetime.now(APP_TZ)

    # driver_headcounts has UNIQUE (trip_id, stop_sequence): one
    # authoritative figure per stop. A driver correcting their own count is
    # legitimate, so update in place rather than letting the constraint
    # raise an IntegrityError the caller cannot interpret.
    existing = await session.execute(
        select(DriverHeadcount).where(
            DriverHeadcount.trip_id == trip_id,
            DriverHeadcount.stop_sequence == payload.stop_sequence,
        )
    )
    record = existing.scalar_one_or_none()

    if record is not None:
        record.confirmed_count = payload.confirmed_count
        record.manifest_count = manifest_count
        record.variance = variance
        record.confirmed_by_user_id = user.user_id
        record.confirmed_at = now
        headcount_id = record.headcount_id
    else:
        headcount_id = str(uuid.uuid4())
        session.add(
            DriverHeadcount(
                headcount_id=headcount_id,
                trip_id=trip_id,
                stop_sequence=payload.stop_sequence,
                confirmed_count=payload.confirmed_count,
                manifest_count=manifest_count,
                variance=variance,
                confirmed_by_user_id=user.user_id,
                confirmed_at=now,
            )
        )

    await session.commit()

    return HeadcountResponse(
        headcount_id=headcount_id,
        trip_id=trip_id,
        stop_sequence=payload.stop_sequence,
        confirmed_count=payload.confirmed_count,
        manifest_count=manifest_count,
        variance=variance,
        message=(
            "Headcount matches the manifest."
            if variance == 0
            else f"Headcount differs from the manifest by {variance:+d}."
        ),
    )


# ------------------------------------------------------------------- depart
@router.post("/trips/{trip_id}/depart", dependencies=[Depends(CREW)])
async def depart(trip_id: str, session: SessionDep) -> dict:
    """Close boarding. Anyone confirmed but unscanned becomes a no-show."""
    return await DepartTripUseCase(session).execute(trip_id=trip_id)


@router.post("/trips/{trip_id}/start-boarding", dependencies=[Depends(CREW)])
async def start_boarding(trip_id: str, session: SessionDep) -> dict:
    trip = await session.get(Trip, trip_id)
    if trip is None:
        raise NotFoundError("Trip not found.")
    trip.status = "boarding"
    trip.updated_at = dt.datetime.now(APP_TZ)
    await session.commit()
    return {"trip_id": trip_id, "status": "boarding"}
