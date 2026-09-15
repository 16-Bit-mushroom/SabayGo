"""In-app notification list for the signed-in user."""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from app.api.v1.deps import CurrentUser, SessionDep
from app.application.notifications.service import NotificationService

router = APIRouter(prefix="/notifications", tags=["notifications"])


class NotificationOut(BaseModel):
    notification_id: str
    type: str
    title: str
    message: str
    related_entity_type: str | None
    related_entity_id: str | None
    is_read: bool
    created_at: dt.datetime


class NotificationListOut(BaseModel):
    unread_count: int
    items: list[NotificationOut]


@router.get("", response_model=NotificationListOut)
async def list_notifications(
    session: SessionDep,
    user: CurrentUser,
    unread_only: bool = False,
    limit: int = Query(50, ge=1, le=200),
) -> NotificationListOut:
    rows, unread = await NotificationService(session).list_for_user(
        user.user_id, unread_only=unread_only, limit=limit
    )
    return NotificationListOut(
        unread_count=unread,
        items=[NotificationOut.model_validate(r, from_attributes=True) for r in rows],
    )


@router.post("/read-all")
async def mark_all_read(session: SessionDep, user: CurrentUser) -> dict:
    n = await NotificationService(session).mark_all_read(user.user_id)
    return {"marked": n}


@router.post("/{notification_id}/read")
async def mark_read(notification_id: str, session: SessionDep, user: CurrentUser) -> dict:
    ok = await NotificationService(session).mark_read(user.user_id, notification_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Notification not found.")
    return {"notification_id": notification_id, "is_read": True}
