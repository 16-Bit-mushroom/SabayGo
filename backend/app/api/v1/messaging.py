"""Two-way in-app messaging: passenger<->conductor, conductor<->driver,
anyone<->coop_admin (a shared office inbox). See
app/application/messaging/service.py for the role-pair and trip-scoping
rules.
"""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Query
from pydantic import BaseModel, Field

from app.api.v1.deps import CurrentUser, SessionDep
from app.application.messaging.service import MessagingService

router = APIRouter(prefix="/conversations", tags=["messaging"])


class ConversationOut(BaseModel):
    conversation_id: str
    kind: str
    trip_id: str | None
    peer_user_id: str | None
    peer_role: str
    peer_name: str
    last_message: str | None
    last_message_at: dt.datetime | None
    unread_count: int
    created_at: dt.datetime


class MessageOut(BaseModel):
    message_id: str
    conversation_id: str
    sender_id: str
    sender_role: str
    body: str
    is_mine: bool
    read_at: dt.datetime | None
    created_at: dt.datetime


class ContactOut(BaseModel):
    peer_user_id: str | None
    peer_role: str
    peer_name: str
    trip_id: str | None
    trip_label: str | None


class StartConversationIn(BaseModel):
    peer_user_id: str | None = None
    trip_id: str | None = None


class SendMessageIn(BaseModel):
    body: str = Field(min_length=1, max_length=1000)


def _out(view) -> ConversationOut:
    conv = view.conversation
    return ConversationOut(
        conversation_id=conv.conversation_id,
        kind=conv.kind,
        trip_id=conv.trip_id,
        peer_user_id=view.peer_user_id,
        peer_role=view.peer_role,
        peer_name=view.peer_name,
        last_message=view.last_message,
        last_message_at=conv.last_message_at,
        unread_count=view.unread_count,
        created_at=conv.created_at,
    )


@router.get("", response_model=list[ConversationOut])
async def list_conversations(session: SessionDep, user: CurrentUser) -> list[ConversationOut]:
    views = await MessagingService(session).list_conversations(user)
    return [_out(v) for v in views]


@router.get("/contacts", response_model=list[ContactOut])
async def list_contacts(session: SessionDep, user: CurrentUser) -> list[ContactOut]:
    rows = await MessagingService(session).list_contacts(user)
    return [
        ContactOut(
            peer_user_id=r.peer_user_id, peer_role=r.peer_role, peer_name=r.peer_name,
            trip_id=r.trip_id, trip_label=r.trip_label,
        )
        for r in rows
    ]


@router.post("", response_model=ConversationOut)
async def start_conversation(
    body: StartConversationIn, session: SessionDep, user: CurrentUser,
) -> ConversationOut:
    svc = MessagingService(session)
    conv = await svc.start_conversation(
        user, peer_user_id=body.peer_user_id, trip_id=body.trip_id
    )
    view = await svc.get_view(user, conv.conversation_id)
    return _out(view)


@router.get("/{conversation_id}/messages", response_model=list[MessageOut])
async def list_messages(
    conversation_id: str, session: SessionDep, user: CurrentUser,
    before: dt.datetime | None = None, limit: int = Query(50, ge=1, le=200),
) -> list[MessageOut]:
    svc = MessagingService(session)
    rows = await svc.list_messages(user, conversation_id, before=before, limit=limit)
    return [
        MessageOut(
            message_id=m.message_id, conversation_id=m.conversation_id,
            sender_id=m.sender_id, sender_role=m.sender_role, body=m.body,
            is_mine=svc.is_mine(user, m), read_at=m.read_at, created_at=m.created_at,
        )
        for m in rows
    ]


@router.post("/{conversation_id}/messages", response_model=MessageOut)
async def send_message(
    conversation_id: str, body: SendMessageIn, session: SessionDep, user: CurrentUser,
) -> MessageOut:
    svc = MessagingService(session)
    m = await svc.send_message(user, conversation_id, body.body)
    return MessageOut(
        message_id=m.message_id, conversation_id=m.conversation_id,
        sender_id=m.sender_id, sender_role=m.sender_role, body=m.body,
        is_mine=True, read_at=m.read_at, created_at=m.created_at,
    )
