"""Passenger self-service: notification preferences and saved destinations.

Both tables (`passenger_settings`, `saved_destinations`) existed in the
schema since migration 002 -- a passenger just had no endpoint to reach
them until now (G.8).
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select

from app.api.v1.deps import SessionDep, require_roles
from app.core import timezone as app_tz
from app.core.exceptions import NotFoundError
from app.domain.enums import Role
from app.infrastructure.models import PassengerSettings, SavedDestination, User

router = APIRouter(prefix="/users/me", tags=["users"])
PASSENGER = require_roles(Role.PASSENGER)
CurrentPassenger = Annotated[User, Depends(PASSENGER)]


class SettingsOut(BaseModel):
    push_enabled: bool
    trip_updates: bool
    tailored_schedules: bool


class SettingsUpdate(BaseModel):
    push_enabled: bool | None = None
    trip_updates: bool | None = None
    tailored_schedules: bool | None = None


@router.get("/settings", response_model=SettingsOut)
async def get_settings(session: SessionDep, user: CurrentPassenger) -> SettingsOut:
    settings = await session.get(PassengerSettings, user.user_id)
    return SettingsOut.model_validate(settings, from_attributes=True)


@router.patch("/settings", response_model=SettingsOut)
async def update_settings(
    payload: SettingsUpdate, session: SessionDep, user: CurrentPassenger
) -> SettingsOut:
    settings = await session.get(PassengerSettings, user.user_id)
    if payload.push_enabled is not None:
        settings.push_enabled = payload.push_enabled
    if payload.trip_updates is not None:
        settings.trip_updates = payload.trip_updates
    if payload.tailored_schedules is not None:
        settings.tailored_schedules = payload.tailored_schedules
    await session.commit()
    return SettingsOut.model_validate(settings, from_attributes=True)


class SavedDestinationOut(BaseModel):
    destination_id: str
    label: str
    terminal_id: str | None
    address: str | None


class SavedDestinationCreate(BaseModel):
    label: str
    terminal_id: str | None = None
    address: str | None = None


@router.get("/saved-destinations", response_model=list[SavedDestinationOut])
async def list_saved_destinations(
    session: SessionDep, user: CurrentPassenger
) -> list[SavedDestination]:
    rows = await session.execute(
        select(SavedDestination)
        .where(SavedDestination.user_id == user.user_id)
        .order_by(SavedDestination.created_at)
    )
    return list(rows.scalars().all())


@router.post(
    "/saved-destinations", response_model=SavedDestinationOut, status_code=201
)
async def add_saved_destination(
    payload: SavedDestinationCreate, session: SessionDep, user: CurrentPassenger
) -> SavedDestination:
    row = SavedDestination(
        destination_id=str(uuid.uuid4()),
        user_id=user.user_id,
        label=payload.label.strip(),
        terminal_id=payload.terminal_id,
        address=(payload.address or "").strip() or None,
        created_at=app_tz.now(),
    )
    session.add(row)
    await session.commit()
    await session.refresh(row)
    return row


@router.delete("/saved-destinations/{destination_id}", status_code=204)
async def delete_saved_destination(
    destination_id: str, session: SessionDep, user: CurrentPassenger
) -> None:
    row = await session.get(SavedDestination, destination_id)
    if row is None or row.user_id != user.user_id:
        raise NotFoundError("Saved destination not found.")
    await session.delete(row)
    await session.commit()
