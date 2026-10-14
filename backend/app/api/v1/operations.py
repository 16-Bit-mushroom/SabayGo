"""Operations endpoints: check-in, boarding, manifest, trip lifecycle."""

from __future__ import annotations

import datetime as dt
from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from app.api.v1.deps import MANAGER, OFFICE, CurrentUser, SessionDep, require_roles
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
from app.application.operations.trip_lifecycle import TripLifecycle
from app.domain.enums import Role
from app.infrastructure.models import Trip, User

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


# ----------------------------------------------------------- lifecycle
# Brief 4.2 and the permission table (section 3): the office assigns,
# starts and departs; only the Terminal Manager reviews an automatic
# start, changes a started trip's van or voids a trip; the Dispatcher
# taps Arrived. The rules are in application/operations/trip_lifecycle.py.
class TripStateOut(BaseModel):
    trip_id: str
    status: str
    van_id: str | None
    dispatcher_id: str | None
    plate_number: str | None
    start_mode: str | None
    start_review_status: str
    audit_status: str
    unaudited_reason: str | None
    departure_source: str | None
    change_note: str | None
    # Shown to whoever started the trip; a start is never refused for these.
    warnings: list[str] = []


def _state(trip: Trip, warnings: list[str] | None = None) -> TripStateOut:
    return TripStateOut(
        trip_id=trip.trip_id,
        status=trip.status,
        van_id=trip.van_id,
        dispatcher_id=trip.dispatcher_id,
        plate_number=trip.van_plate_number or (trip.van.plate_number if trip.van else None),
        start_mode=trip.start_mode,
        start_review_status=trip.start_review_status,
        audit_status=trip.audit_status,
        unaudited_reason=trip.unaudited_reason,
        departure_source=trip.departure_source,
        change_note=trip.change_note,
        warnings=warnings or [],
    )


class AssignmentIn(BaseModel):
    van_id: str | None = None
    dispatcher_id: str | None = None


@router.put("/trips/{trip_id}/assignment", response_model=TripStateOut)
async def assign(
    trip_id: str, payload: AssignmentIn, session: SessionDep,
    user: Annotated[User, Depends(OFFICE)],
) -> TripStateOut:
    """Assign the van and the Dispatcher at the van's turn. The Cashier's
    assignment always works and alerts the Terminal Manager."""
    trip = await TripLifecycle(session).assign(
        trip_id, van_id=payload.van_id, dispatcher_id=payload.dispatcher_id, by=user
    )
    return _state(trip)


class StartIn(BaseModel):
    # Confirm the assigned van (omit), or start with another validated van.
    van_id: str | None = None


@router.post("/trips/{trip_id}/start", response_model=TripStateOut)
async def start(
    trip_id: str, session: SessionDep, user: Annotated[User, Depends(OFFICE)],
    payload: StartIn | None = None,
) -> TripStateOut:
    outcome = await TripLifecycle(session).start(
        trip_id, by=user, van_id=payload.van_id if payload else None
    )
    return _state(outcome.trip, outcome.warnings)


@router.post("/trips/{trip_id}/depart", dependencies=[Depends(OFFICE)])
async def depart(trip_id: str, session: SessionDep) -> dict:
    """Close boarding. Anyone confirmed but unscanned becomes a no-show."""
    return await DepartTripUseCase(session).execute(trip_id=trip_id)


@router.post("/trips/{trip_id}/arrive", response_model=TripStateOut,
             dependencies=[Depends(CREW)])
async def arrive(trip_id: str, session: SessionDep, user: CurrentUser) -> TripStateOut:
    """The Dispatcher taps Arrived: the trip is completed."""
    await assert_assigned_to_trip(session, trip_id=trip_id, user=user)
    return _state(await TripLifecycle(session).arrive(trip_id))


class StartReviewIn(BaseModel):
    # Confirm the van (omit), or change it -- then the note says why.
    van_id: str | None = None
    note: str | None = Field(default=None, max_length=200)


@router.post("/trips/{trip_id}/start-review", response_model=TripStateOut)
async def review_start(
    trip_id: str, session: SessionDep, user: Annotated[User, Depends(MANAGER)],
    payload: StartReviewIn | None = None,
) -> TripStateOut:
    payload = payload or StartReviewIn()
    trip = await TripLifecycle(session).review_start(
        trip_id, by=user, van_id=payload.van_id, note=payload.note
    )
    return _state(trip)


class ChangeVanIn(BaseModel):
    van_id: str
    reason: str = Field(min_length=3, max_length=200)


@router.post("/trips/{trip_id}/change-van", response_model=TripStateOut)
async def change_van(
    trip_id: str, payload: ChangeVanIn, session: SessionDep,
    user: Annotated[User, Depends(MANAGER)],
) -> TripStateOut:
    trip = await TripLifecycle(session).change_van(
        trip_id, by=user, van_id=payload.van_id, reason=payload.reason
    )
    return _state(trip)


class VoidIn(BaseModel):
    reason: str = Field(min_length=3, max_length=200)


@router.post("/trips/{trip_id}/void", response_model=TripStateOut)
async def void(
    trip_id: str, payload: VoidIn, session: SessionDep,
    user: Annotated[User, Depends(MANAGER)],
) -> TripStateOut:
    return _state(await TripLifecycle(session).void(trip_id, by=user, reason=payload.reason))
