"""Two-way in-app messaging (spec 2.2.3.1; ERD Conversations/Messages).

Every conversation has exactly two sides, and which roles may pair is
fixed, not left to the client: passenger<->conductor and conductor<->driver
require a shared trip (the passenger's booking, or the crew assignment);
anyone<->coop_admin is an "office" thread with no trip context.

The office kind is a shared inbox rather than a 1:1 thread with one
employee -- `participant_two_id` stays NULL and any active coop_admin may
read and reply, matching a cooperative office where more than one staff
member picks up the desk. `participant_one_id` is always the non-admin
party in that case.

`messages.sender_role` is denormalized (same shape as
`notifications.audience`) so "unread by the other side" doesn't need a
join to `users` for every row.
"""

from __future__ import annotations

import datetime as dt
import uuid

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import timezone as app_tz
from app.core.exceptions import NotFoundError, PermissionDeniedError, PolicyViolationError
from app.domain.enums import BookingStatus, Role, TripStatus
from app.infrastructure.models import Booking, Conversation, Message, Route, Trip, User


def _display_name(user: User) -> str:
    if user.passenger_profile is not None:
        p = user.passenger_profile
        return f"{p.first_name} {p.last_name}".strip()
    if user.staff_profile is not None:
        s = user.staff_profile
        return f"{s.first_name} {s.last_name}".strip()
    return user.email


def _trip_label(route_name: str, departure: dt.datetime) -> str:
    return f"{route_name} · {departure:%b %d, %I:%M %p}"


class ConversationView:
    """One row for the conversation list, with the peer already resolved."""

    def __init__(
        self, conv: Conversation, *, peer_user_id: str | None, peer_name: str,
        peer_role: str, last_message: str | None, unread_count: int,
    ):
        self.conversation = conv
        self.peer_user_id = peer_user_id
        self.peer_name = peer_name
        self.peer_role = peer_role
        self.last_message = last_message
        self.unread_count = unread_count


class ContactRow:
    def __init__(
        self, *, peer_user_id: str | None, peer_role: str, peer_name: str,
        trip_id: str | None, trip_label: str | None,
    ):
        self.peer_user_id = peer_user_id
        self.peer_role = peer_role
        self.peer_name = peer_name
        self.trip_id = trip_id
        self.trip_label = trip_label


class MessagingService:
    def __init__(self, session: AsyncSession):
        self.session = session

    # ------------------------------------------------------------------
    # Access
    # ------------------------------------------------------------------
    def _can_access(self, user: User, conv: Conversation) -> bool:
        if user.role == Role.COOP_ADMIN.value:
            return conv.kind == "office"
        return user.user_id in (conv.participant_one_id, conv.participant_two_id)

    def is_mine(self, user: User, msg: Message) -> bool:
        if user.role == Role.COOP_ADMIN.value:
            return msg.sender_role == Role.COOP_ADMIN.value
        return msg.sender_id == user.user_id

    async def _get_conversation_for(self, conversation_id: str, user: User) -> Conversation:
        conv = await self.session.get(Conversation, conversation_id)
        if conv is None:
            raise NotFoundError("Conversation not found.")
        if not self._can_access(user, conv):
            raise PermissionDeniedError("Not a participant in that conversation.")
        return conv

    # ------------------------------------------------------------------
    # Starting a conversation
    # ------------------------------------------------------------------
    async def start_conversation(
        self, current_user: User, *, peer_user_id: str | None, trip_id: str | None,
    ) -> Conversation:
        if current_user.role == Role.COOP_ADMIN.value:
            if not peer_user_id:
                raise PolicyViolationError("Choose which user to message.")
            peer = await self.session.get(User, peer_user_id)
            if peer is None:
                raise NotFoundError("User not found.")
            if peer.role == Role.COOP_ADMIN.value:
                raise PermissionDeniedError("Message another coop_admin outside the app.")
            return await self._get_or_create(kind="office", trip_id=None, p1=peer.user_id, p2=None)

        if peer_user_id is None:
            return await self._get_or_create(
                kind="office", trip_id=None, p1=current_user.user_id, p2=None
            )

        peer = await self.session.get(User, peer_user_id)
        if peer is None:
            raise NotFoundError("User not found.")

        if peer.role == Role.COOP_ADMIN.value:
            return await self._get_or_create(
                kind="office", trip_id=None, p1=current_user.user_id, p2=None
            )

        pair = frozenset({current_user.role, peer.role})
        if pair == frozenset({Role.PASSENGER.value, Role.CONDUCTOR.value}):
            kind = "passenger_conductor"
        elif pair == frozenset({Role.CONDUCTOR.value, Role.DRIVER.value}):
            kind = "conductor_driver"
        else:
            raise PermissionDeniedError(
                f"A {current_user.role} may not message a {peer.role} directly."
            )

        if not trip_id:
            raise PolicyViolationError("A shared trip is required to start this conversation.")
        trip = await self.session.get(Trip, trip_id)
        if trip is None:
            raise NotFoundError("Trip not found.")

        if kind == "conductor_driver":
            crew = {trip.conductor_id, trip.driver_id}
            if None in crew or current_user.user_id not in crew or peer.user_id not in crew:
                raise PermissionDeniedError("Not crewed together on that trip.")
            p1, p2 = trip.conductor_id, trip.driver_id
        else:
            is_passenger = current_user.role == Role.PASSENGER.value
            conductor_id = peer.user_id if is_passenger else current_user.user_id
            passenger_id = current_user.user_id if is_passenger else peer.user_id
            if trip.conductor_id != conductor_id:
                raise PermissionDeniedError("That conductor is not assigned to this trip.")
            has_booking = await self.session.scalar(
                select(Booking.booking_id)
                .where(
                    Booking.trip_id == trip_id,
                    Booking.passenger_user_id == passenger_id,
                    Booking.status.notin_(
                        [BookingStatus.CANCELLED.value, BookingStatus.RESCHEDULED.value]
                    ),
                )
                .limit(1)
            )
            if has_booking is None:
                raise PermissionDeniedError("No active booking on that trip.")
            p1, p2 = passenger_id, conductor_id

        return await self._get_or_create(kind=kind, trip_id=trip_id, p1=p1, p2=p2)

    async def _get_or_create(
        self, *, kind: str, trip_id: str | None, p1: str, p2: str | None,
    ) -> Conversation:
        conditions = [Conversation.kind == kind, Conversation.participant_one_id == p1]
        conditions.append(
            Conversation.trip_id == trip_id if trip_id is not None else Conversation.trip_id.is_(None)
        )
        conditions.append(
            Conversation.participant_two_id == p2
            if p2 is not None
            else Conversation.participant_two_id.is_(None)
        )
        existing = await self.session.scalar(select(Conversation).where(*conditions))
        if existing is not None:
            return existing
        conv = Conversation(
            conversation_id=str(uuid.uuid4()),
            kind=kind,
            trip_id=trip_id,
            participant_one_id=p1,
            participant_two_id=p2,
            created_at=app_tz.now(),
        )
        self.session.add(conv)
        await self.session.commit()
        await self.session.refresh(conv)
        return conv

    # ------------------------------------------------------------------
    # Reading
    # ------------------------------------------------------------------
    async def list_conversations(self, user: User) -> list[ConversationView]:
        if user.role == Role.COOP_ADMIN.value:
            stmt = select(Conversation).where(Conversation.kind == "office")
        else:
            stmt = select(Conversation).where(
                or_(
                    Conversation.participant_one_id == user.user_id,
                    Conversation.participant_two_id == user.user_id,
                )
            )
        rows = list(await self.session.scalars(stmt))
        rows.sort(key=lambda c: c.last_message_at or c.created_at, reverse=True)
        return [await self._to_view(user, conv) for conv in rows]

    async def _to_view(self, user: User, conv: Conversation) -> ConversationView:
        if conv.kind == "office" and user.role != Role.COOP_ADMIN.value:
            peer_id, peer_name, peer_role = None, "Cooperative Office", Role.COOP_ADMIN.value
        else:
            peer_id = (
                conv.participant_one_id
                if conv.kind == "office"
                else (
                    conv.participant_two_id
                    if conv.participant_one_id == user.user_id
                    else conv.participant_one_id
                )
            )
            peer = await self.session.get(User, peer_id)
            peer_name = _display_name(peer) if peer else "Unknown user"
            peer_role = peer.role if peer else "unknown"

        last = await self.session.scalar(
            select(Message)
            .where(Message.conversation_id == conv.conversation_id)
            .order_by(Message.created_at.desc())
            .limit(1)
        )
        unread = 0
        for m in await self.session.scalars(
            select(Message).where(
                Message.conversation_id == conv.conversation_id,
                Message.read_at.is_(None),
            )
        ):
            if not self.is_mine(user, m):
                unread += 1

        return ConversationView(
            conv,
            peer_user_id=peer_id,
            peer_name=peer_name,
            peer_role=peer_role,
            last_message=last.body if last else None,
            unread_count=unread,
        )

    async def get_view(self, user: User, conversation_id: str) -> ConversationView:
        conv = await self._get_conversation_for(conversation_id, user)
        return await self._to_view(user, conv)

    async def list_messages(
        self, user: User, conversation_id: str, *, before: dt.datetime | None, limit: int,
    ) -> list[Message]:
        conv = await self._get_conversation_for(conversation_id, user)
        stmt = select(Message).where(Message.conversation_id == conv.conversation_id)
        if before is not None:
            stmt = stmt.where(Message.created_at < before)
        rows = list(await self.session.scalars(stmt.order_by(Message.created_at.desc()).limit(limit)))
        rows.reverse()

        now = app_tz.now()
        changed = False
        for m in rows:
            if m.read_at is None and not self.is_mine(user, m):
                m.read_at = now
                changed = True
        if changed:
            await self.session.commit()
        return rows

    async def send_message(self, user: User, conversation_id: str, body: str) -> Message:
        conv = await self._get_conversation_for(conversation_id, user)
        body = body.strip()
        if not body:
            raise PolicyViolationError("Message cannot be empty.")
        now = app_tz.now()
        msg = Message(
            message_id=str(uuid.uuid4()),
            conversation_id=conv.conversation_id,
            sender_id=user.user_id,
            sender_role=user.role,
            body=body[:1000],
            created_at=now,
        )
        conv.last_message_at = now
        self.session.add(msg)
        await self.session.commit()
        await self.session.refresh(msg)
        return msg

    # ------------------------------------------------------------------
    # Who can this user start a conversation with
    # ------------------------------------------------------------------
    async def list_contacts(self, user: User) -> list[ContactRow]:
        if user.role == Role.COOP_ADMIN.value:
            return []

        contacts = [
            ContactRow(
                peer_user_id=None, peer_role=Role.COOP_ADMIN.value,
                peer_name="Cooperative Office", trip_id=None, trip_label=None,
            )
        ]

        if user.role == Role.PASSENGER.value:
            rows = await self.session.execute(
                select(Trip.trip_id, Trip.conductor_id, Trip.departure_datetime, Route.route_name)
                .join(Booking, Booking.trip_id == Trip.trip_id)
                .join(Route, Route.route_id == Trip.route_id)
                .where(
                    Booking.passenger_user_id == user.user_id,
                    Booking.status.notin_(
                        [BookingStatus.CANCELLED.value, BookingStatus.RESCHEDULED.value]
                    ),
                    Trip.conductor_id.is_not(None),
                    Trip.status != TripStatus.CANCELLED.value,
                )
                .distinct()
            )
            seen: set[str] = set()
            for trip_id, conductor_id, departure, route_name in rows:
                if conductor_id in seen:
                    continue
                seen.add(conductor_id)
                conductor = await self.session.get(User, conductor_id)
                if conductor is None:
                    continue
                contacts.append(
                    ContactRow(
                        peer_user_id=conductor_id, peer_role=Role.CONDUCTOR.value,
                        peer_name=_display_name(conductor), trip_id=trip_id,
                        trip_label=_trip_label(route_name, departure),
                    )
                )

        elif user.role == Role.CONDUCTOR.value:
            trip_rows = (
                await self.session.execute(
                    select(Trip.trip_id, Trip.driver_id, Trip.departure_datetime, Route.route_name)
                    .join(Route, Route.route_id == Trip.route_id)
                    .where(
                        Trip.conductor_id == user.user_id,
                        Trip.status != TripStatus.CANCELLED.value,
                    )
                )
            ).all()
            seen_drivers: set[str] = set()
            trip_ids = []
            for trip_id, driver_id, departure, route_name in trip_rows:
                trip_ids.append(trip_id)
                if driver_id and driver_id not in seen_drivers:
                    seen_drivers.add(driver_id)
                    driver = await self.session.get(User, driver_id)
                    if driver is not None:
                        contacts.append(
                            ContactRow(
                                peer_user_id=driver_id, peer_role=Role.DRIVER.value,
                                peer_name=_display_name(driver), trip_id=trip_id,
                                trip_label=_trip_label(route_name, departure),
                            )
                        )
            if trip_ids:
                trip_label_by_id = {t[0]: _trip_label(t[3], t[2]) for t in trip_rows}
                pax_rows = await self.session.execute(
                    select(Booking.passenger_user_id, Booking.trip_id)
                    .where(
                        Booking.trip_id.in_(trip_ids),
                        Booking.passenger_user_id.is_not(None),
                        Booking.status.notin_(
                            [BookingStatus.CANCELLED.value, BookingStatus.RESCHEDULED.value]
                        ),
                    )
                    .distinct()
                )
                seen_pax: set[str] = set()
                for passenger_id, trip_id in pax_rows:
                    if passenger_id in seen_pax:
                        continue
                    seen_pax.add(passenger_id)
                    passenger = await self.session.get(User, passenger_id)
                    if passenger is not None:
                        contacts.append(
                            ContactRow(
                                peer_user_id=passenger_id, peer_role=Role.PASSENGER.value,
                                peer_name=_display_name(passenger), trip_id=trip_id,
                                trip_label=trip_label_by_id.get(trip_id),
                            )
                        )

        elif user.role == Role.DRIVER.value:
            rows = await self.session.execute(
                select(Trip.trip_id, Trip.conductor_id, Trip.departure_datetime, Route.route_name)
                .join(Route, Route.route_id == Trip.route_id)
                .where(
                    Trip.driver_id == user.user_id,
                    Trip.conductor_id.is_not(None),
                    Trip.status != TripStatus.CANCELLED.value,
                )
            )
            seen: set[str] = set()
            for trip_id, conductor_id, departure, route_name in rows:
                if conductor_id in seen:
                    continue
                seen.add(conductor_id)
                conductor = await self.session.get(User, conductor_id)
                if conductor is not None:
                    contacts.append(
                        ContactRow(
                            peer_user_id=conductor_id, peer_role=Role.CONDUCTOR.value,
                            peer_name=_display_name(conductor), trip_id=trip_id,
                            trip_label=_trip_label(route_name, departure),
                        )
                    )

        return contacts
