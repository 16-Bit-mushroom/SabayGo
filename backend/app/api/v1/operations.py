"""Operations endpoints: check-in, boarding, manifest."""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.api.v1.deps import CurrentUser, SessionDep, require_roles
from app.application.operations.boarding import (
    DepartTripUseCase,
    ManifestUseCase,
    ScanTicketUseCase,
)
from app.application.operations.check_in import (
    CheckInCommand,
    CheckInUseCase,
    UndoCheckInUseCase,
)
from app.application.operations.guards import assert_assigned_to_trip
from app.core.exceptions import NotFoundError
from app.core.timezone import APP_TZ
from app.domain.enums import Role
from app.infrastructure.models import Trip

router = APIRouter(tags=["operations"])

CREW = require_roles(Role.DISPATCHER, Role.TERMINAL_MANAGER)


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


class UndoCheckInResponse(BaseModel):
    booking_id: str
    status: str
    message: str


@router.delete("/bookings/{booking_id}/check-in", response_model=UndoCheckInResponse)
async def undo_check_in(
    booking_id: str,
    session: SessionDep,
    user: CurrentUser,
) -> UndoCheckInResponse:
    """Withdraw a check-in (D.2). Only while the booking is still `checked_in`."""
    result = await UndoCheckInUseCase(session).execute(
        booking_id=booking_id, passenger_user_id=user.user_id
    )
    return UndoCheckInResponse(
        booking_id=result.booking_id, status=result.status, message=result.message
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
    boarding_stop: int | None
    alighting_stop: int | None
    message: str


@router.post("/scans", response_model=ScanResponse, dependencies=[Depends(CREW)])
async def scan_ticket(
    payload: ScanRequest, session: SessionDep, user: CurrentUser
) -> ScanResponse:
    """Validate a QR code at the van door.

    Always 200, even for an invalid ticket -- the Dispatcher needs a verdict
    on screen, not an error dialog, while a queue waits. Read `accepted`.
    """
    # A Dispatcher may only scan the trip they are rostered to. Without
    # this the remittance record is meaningless: the fares a person is
    # accountable for would not match the runs they actually worked.
    await assert_assigned_to_trip(session, trip_id=payload.trip_id, user=user)
    result = await ScanTicketUseCase(session).execute(
        qr_payload=payload.qr_payload,
        trip_id=payload.trip_id,
        stop_sequence=payload.stop_sequence,
        scanned_by_user_id=user.user_id,
        client_recorded_at=payload.client_recorded_at,
    )
    return ScanResponse(**{k: v for k, v in result.__dict__.items()
                           if k not in ("passenger_name", "seat_number")})


# ----------------------------------------------------------------- manifest
class ManifestPassenger(BaseModel):
    booking_id: str
    ticket_number: str
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
