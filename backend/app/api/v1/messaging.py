"""Two-way in-app messaging: passenger<->Dispatcher on a shared trip, and
anyone<->the A2Z office (a shared inbox). See
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
    # A home pickup's payment screenshot (brief 2.6); the image itself is
    # served by GET /home-pickups/{id}/photo.
    attachment_type: str | None
    attachment_size_kb: int | None
    retain_until: dt.date | None
    is_mine: bool
    read_at: dt.datetime | None
    # 040: shown as "edited"; a deleted message has an empty body.
    edited_at: dt.datetime | None = None
    deleted_at: dt.datetime | None = None
    # True when this reader sent it themself (not a colleague), it is text
    # and not deleted: the app offers Edit and Delete only then.
    can_change: bool = False
    created_at: dt.datetime

    @classmethod
    def of(cls, m, *, is_mine: bool, reader_id: str | None = None) -> MessageOut:
        return cls(
            message_id=m.message_id, conversation_id=m.conversation_id,
            sender_id=m.sender_id, sender_role=m.sender_role, body=m.body,
            attachment_type=m.attachment_type, attachment_size_kb=m.attachment_size_kb,
            retain_until=m.retain_until, is_mine=is_mine, read_at=m.read_at,
            edited_at=m.edited_at, deleted_at=m.deleted_at,
            can_change=(reader_id is not None and m.sender_id == reader_id
                        and m.attachment_type is None and m.deleted_at is None),
            created_at=m.created_at,
        )


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
    return [MessageOut.of(m, is_mine=svc.is_mine(user, m), reader_id=user.user_id) for m in rows]


@router.post("/{conversation_id}/messages", response_model=MessageOut)
async def send_message(
    conversation_id: str, body: SendMessageIn, session: SessionDep, user: CurrentUser,
) -> MessageOut:
    svc = MessagingService(session)
    m = await svc.send_message(user, conversation_id, body.body)
    return MessageOut.of(m, is_mine=True, reader_id=user.user_id)


class EditMessageIn(BaseModel):
    body: str = Field(min_length=1, max_length=1000)


@router.patch("/{conversation_id}/messages/{message_id}", response_model=MessageOut)
async def edit_message(
    conversation_id: str, message_id: str, body: EditMessageIn, session: SessionDep, user: CurrentUser,
) -> MessageOut:
    """Edit one's own text message (12 Nov)."""
    m = await MessagingService(session).edit_message(user, conversation_id, message_id, body.body)
    return MessageOut.of(m, is_mine=True, reader_id=user.user_id)


@router.delete("/{conversation_id}/messages/{message_id}", response_model=MessageOut)
async def delete_message(
    conversation_id: str, message_id: str, session: SessionDep, user: CurrentUser,
) -> MessageOut:
    """Delete one's own text message: its text is erased (12 Nov)."""
    m = await MessagingService(session).delete_message(user, conversation_id, message_id)
    return MessageOut.of(m, is_mine=True, reader_id=user.user_id)
