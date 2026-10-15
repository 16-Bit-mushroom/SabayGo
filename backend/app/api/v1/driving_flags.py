"""Driving flags: the Terminal Manager's fleet screen (rev 603, change
brief 6.4, Table 30).

The flags are computed from the trip's GPS readings
(`application/tracking/flags.py`); here they are listed and reviewed.
Every flag is an indicator for review, not proof of misconduct, and ties
to a person only through the operator name, licence and plate copied onto
the trip at the start.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal
from typing import Annotated, Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select

from app.api.v1.deps import MANAGER, SessionDep, require_roles
from app.application.identity.naming import display_name
from app.application.notifications.service import trip_label
from app.application.operations.guards import assert_assigned_to_trip
from app.application.tracking.flags import DrivingFlags
from app.application.tracking.nahgm import TrackingService
from app.core.exceptions import InvalidInputError
from app.domain.enums import Role
from app.infrastructure.models import Dispute, DrivingEvent, Trip, User

router = APIRouter(prefix="/driving-flags", tags=["driving flags"])

# The office reads them; a Dispatcher reads their own trip's, to record
# the operator's dispute (brief 3).
READS = require_roles(Role.DISPATCHER, Role.CASHIER, Role.TERMINAL_MANAGER, Role.ADMIN)


class FlagOut(BaseModel):
    driving_event_id: str
    trip_id: str
    trip_label: str
    service_date: dt.date
    operator_name: str | None
    operator_licence: str | None
    plate_number: str | None
    flag_type: str
    # False for an en-route stop: recorded, not flagged.
    flagged: bool
    start_at: dt.datetime
    end_at: dt.datetime | None
    duration_s: int | None
    stretch_no: int | None
    place: str | None
    distance_from_start_m: Decimal | None
    max_speed_kmh: Decimal | None
    limit_kmh: Decimal | None
    time_ratio: Decimal | None
    nearest_stop_dist_m: Decimal | None
    review_status: str
    reviewed_by: str | None
    reviewed_at: dt.datetime | None
    review_note: str | None
    dispute_id: str | None
    dispute_status: str | None


class ReviewIn(BaseModel):
    status: Literal["reviewed", "dismissed"]
    note: str | None = Field(default=None, max_length=255)


async def _out(session, rows: list[DrivingEvent]) -> list[FlagOut]:
    trips = {t.trip_id: t for t in (await session.execute(
        select(Trip).where(Trip.trip_id.in_({r.trip_id for r in rows}))
    )).scalars()} if rows else {}
    disputes: dict[str, Dispute] = {}
    if rows:
        # The standing dispute: an open one, else the latest decided.
        for d in (await session.execute(
            select(Dispute).where(Dispute.driving_event_id.in_([r.driving_event_id for r in rows]),
                                  Dispute.status != "withdrawn")
            .order_by(Dispute.raised_at)
        )).scalars():
            if disputes.get(d.driving_event_id) is None or disputes[d.driving_event_id].status != "open":
                disputes[d.driving_event_id] = d
    reviewers = {u.user_id: display_name(u) for u in (await session.execute(
        select(User).where(User.user_id.in_({r.reviewed_by for r in rows} - {None}))
    )).scalars()} if rows else {}
    tracking = TrackingService(session)
    out = []
    for r in rows:
        trip, dispute = trips[r.trip_id], disputes.get(r.driving_event_id)
        out.append(FlagOut(
            driving_event_id=r.driving_event_id, trip_id=r.trip_id, trip_label=trip_label(trip),
            service_date=trip.service_date, operator_name=trip.driver_name,
            operator_licence=trip.driver_license_no, plate_number=trip.van_plate_number,
            flag_type=r.flag_type, flagged=r.flag_type != "en_route_stop",
            start_at=r.start_at, end_at=r.end_at, duration_s=r.duration_s,
            stretch_no=r.stretch_no, place=await tracking.place(trip.route_id, r.stretch_no),
            distance_from_start_m=r.distance_from_start_m, max_speed_kmh=r.max_speed_kmh,
            limit_kmh=r.limit_kmh, time_ratio=r.time_ratio,
            nearest_stop_dist_m=r.nearest_stop_dist_m, review_status=r.review_status,
            reviewed_by=reviewers.get(r.reviewed_by), reviewed_at=r.reviewed_at,
            review_note=r.review_note,
            dispute_id=dispute.dispute_id if dispute else None,
            dispute_status=dispute.status if dispute else None,
        ))
    return out


@router.get("", response_model=list[FlagOut])
async def list_flags(
    session: SessionDep, user: Annotated[User, Depends(READS)],
    status: Literal["open", "reviewed", "dismissed"] | None = None,
    trip_id: str | None = None, date: dt.date | None = None,
) -> list[FlagOut]:
    """Driving flags, newest first, en-route stops included (recorded, not
    flagged). By review status, trip or service date. A Dispatcher names
    their own trip."""
    if user.role == Role.DISPATCHER.value:
        if trip_id is None:
            raise InvalidInputError("Name the trip.")
        await assert_assigned_to_trip(session, trip_id=trip_id, user=user)
    query = select(DrivingEvent).order_by(DrivingEvent.start_at.desc())
    if status is not None:
        query = query.where(DrivingEvent.review_status == status)
    if trip_id is not None:
        query = query.where(DrivingEvent.trip_id == trip_id)
    if date is not None:
        query = query.join(Trip, Trip.trip_id == DrivingEvent.trip_id) \
            .where(Trip.service_date == date)
    return await _out(session, list((await session.execute(query.limit(500))).scalars().all()))


@router.post("/{driving_event_id}/review", response_model=FlagOut)
async def review_flag(
    driving_event_id: str, payload: ReviewIn, session: SessionDep,
    user: Annotated[User, Depends(MANAGER)],
) -> FlagOut:
    """The Terminal Manager marks an open flag reviewed (it stands) or
    dismissed (with the reason). A disputed flag is reviewed by deciding
    its dispute."""
    note = payload.note.strip() if payload.note else None
    flag = await DrivingFlags(session).mark(driving_event_id, by=user, status=payload.status,
                                            note=note or None)
    return (await _out(session, [flag]))[0]
