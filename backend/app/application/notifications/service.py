"""In-app notifications.

Rows in `notifications` are the record; FCM delivery is a later concern
(the roadmap's Tier 3 decision: an in-app list is enough for testing, so
`delivery_status` stays 'queued' and `fcm_message_id` stays NULL).

The first producer is the YOLOv8 audit: a flagged variance used to be
written to `yolov8_audit_logs` and told no one. Now the Terminal Manager
and the trip's Dispatcher each get a row pointing at the audit, so the console's
queue is a destination rather than something staff must remember to open.
"""

from __future__ import annotations

import uuid

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import timezone as app_tz
from app.domain.enums import Role
from app.infrastructure.models import Notification, Trip, User


def trip_label(trip: Trip) -> str:
    """'Ecoland - Tagum 14 Oct 06:00 (LAB-4521)' for alert text."""
    route = trip.route.route_name if trip.route is not None else "Van rental"
    plate = trip.van_plate_number or (trip.van.plate_number if trip.van else None)
    when = f"{trip.departure_datetime:%d %b %H:%M}"
    return f"{route} {when}" + (f" ({plate})" if plate else "")


class NotificationService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def _staff(self, *roles: Role) -> list[tuple[str, str]]:
        """Every active account holding one of these roles, as (user_id, audience)."""
        rows = await self.session.execute(
            select(User.user_id, User.role).where(
                User.role.in_([r.value for r in roles]),
                User.account_status == "active",
            )
        )
        return [(uid, role) for uid, role in rows.all()]

    # ------------------------------------------------------------------
    # Producers
    # ------------------------------------------------------------------
    async def notify_variance(
        self, *, audit_id: str, trip: Trip, leg_sequence: int,
        visual_count: int, booked_count: int, variance: int,
    ) -> int:
        """Alert the Terminal Manager and the trip's Dispatcher about a flagged headcount.

        Adds rows to the session without committing; the caller owns the
        transaction so the audit log and its alerts land together.
        Returns the number of recipients.
        """
        if variance > 0:
            headline = f"{variance} more aboard than the passenger list"
            detail = "Possible unrecorded passengers."
        else:
            headline = f"{abs(variance)} fewer aboard than the passenger list"
            detail = "Someone may have got off early or not been marked a no-show."
        plate = trip.van.plate_number if trip.van is not None else "unassigned van"
        route = trip.route.route_name if trip.route is not None else trip.route_id
        message = (
            f"{route} · {plate} · section {leg_sequence}: camera counted "
            f"{visual_count}, passenger list shows {booked_count}. {detail}"
        )

        recipients = await self._staff(Role.TERMINAL_MANAGER)
        if trip.dispatcher_id:
            recipients.append((trip.dispatcher_id, Role.DISPATCHER.value))

        now = app_tz.now()
        for user_id, audience in recipients:
            self.session.add(
                Notification(
                    notification_id=str(uuid.uuid4()),
                    user_id=user_id,
                    audience=audience,
                    type="variance_alert",
                    title=f"Headcount variance: {headline}",
                    message=message[:500],
                    related_entity_type="audit",
                    related_entity_id=audit_id,
                    is_read=False,
                    delivery_status="queued",
                    created_at=now,
                )
            )
        return len(recipients)

    async def notify_sos(
        self, *, alert, raiser_name: str, raiser_role: str, trip: Trip | None,
        where: str,
    ) -> int:
        """Alert the office, and the crew of the trip it came from.

        Same contract as notify_variance: rows are added to the session and
        the caller owns the transaction, so the alert and the notices that
        it happened land together. The person who raised it is not notified
        of their own emergency.
        """
        detail = alert.note.strip() if alert.note else "No details given."
        route = ""
        if trip is not None:
            plate = trip.van.plate_number if trip.van is not None else "unassigned van"
            route_name = trip.route.route_name if trip.route is not None else trip.route_id
            route = f"{route_name} · {plate} · "
        message = (
            f"{raiser_name} ({raiser_role}) raised a {alert.category} SOS. "
            f"{route}{where}. {detail}"
        )

        recipients = await self._staff(Role.TERMINAL_MANAGER, Role.CASHIER)
        if trip is not None and trip.dispatcher_id:
            recipients.append((trip.dispatcher_id, Role.DISPATCHER.value))

        now = app_tz.now()
        sent = 0
        for user_id, audience in recipients:
            if user_id == alert.raised_by_user_id:
                continue
            self.session.add(
                Notification(
                    notification_id=str(uuid.uuid4()),
                    user_id=user_id,
                    audience=audience,
                    type="sos_alert",
                    title=f"SOS · {alert.category.upper()}"[:100],
                    message=message[:500],
                    related_entity_type="sos",
                    related_entity_id=alert.sos_id,
                    is_read=False,
                    delivery_status="queued",
                    created_at=now,
                )
            )
            sent += 1
        return sent

    async def notify_sos_acknowledged(self, *, alert) -> None:
        """Tell the person who pressed the button that a human has it.

        Everything else about an emergency flows away from the raiser --
        to the office, to the crew, to a phone number on a policy row.
        This is the one message that flows back.
        """
        self.session.add(
            Notification(
                notification_id=str(uuid.uuid4()),
                user_id=alert.raised_by_user_id,
                # notifications.audience has no 'admin' member -- the
                # system administrator reads the office's queue.
                audience=(
                    Role.TERMINAL_MANAGER.value
                    if alert.raised_by_role == Role.ADMIN.value
                    else alert.raised_by_role
                ),
                type="sos_alert",
                title="Your SOS has been seen",
                message=(
                    "The A2Z office has acknowledged your emergency "
                    "alert and is responding."
                ),
                related_entity_type="sos",
                related_entity_id=alert.sos_id,
                is_read=False,
                delivery_status="queued",
                created_at=app_tz.now(),
            )
        )

    async def notify_trip(
        self, *, trip: Trip, type: str, title: str, message: str,
        roles: tuple[Role, ...], dispatcher: bool = False,
        skip_user_id: str | None = None,
    ) -> int:
        """A trip-lifecycle alert (brief 4.2, 4.4) to the office roles
        named, and to the trip's Dispatcher when `dispatcher` is set."""
        return await self.notify_staff(
            type=type, title=title, message=message, roles=roles,
            entity=("trip", trip.trip_id),
            also=[trip.dispatcher_id] if dispatcher and trip.dispatcher_id else [],
            skip_user_id=skip_user_id,
        )

    async def notify_staff(
        self, *, type: str, title: str, message: str, roles: tuple[Role, ...],
        entity: tuple[str, str], also: list[str] = (),
        skip_user_id: str | None = None,
    ) -> int:
        """An alert to every active account in `roles`, plus the Dispatchers
        in `also`, about one entity (a trip, a van).

        Same contract as notify_variance: rows join the caller's
        transaction. The person whose own action raised the alert sees it
        on screen already and is skipped."""
        recipients = dict(await self._staff(*roles))
        for user_id in also:
            recipients.setdefault(user_id, Role.DISPATCHER.value)
        now = app_tz.now()
        sent = 0
        for user_id, audience in recipients.items():
            if user_id == skip_user_id:
                continue
            self.session.add(
                Notification(
                    notification_id=str(uuid.uuid4()),
                    user_id=user_id,
                    # notifications.audience has no 'admin' member.
                    audience=(Role.TERMINAL_MANAGER.value
                              if audience == Role.ADMIN.value else audience),
                    type=type,
                    title=title[:100],
                    message=message[:500],
                    related_entity_type=entity[0],
                    related_entity_id=entity[1],
                    is_read=False,
                    delivery_status="queued",
                    created_at=now,
                )
            )
            sent += 1
        return sent

    async def notify_passengers(
        self, *, trip: Trip, user_ids: list[str], title: str, message: str,
    ) -> None:
        """A trip update to passengers holding a ticket on it."""
        now = app_tz.now()
        for user_id in dict.fromkeys(user_ids):
            self.session.add(
                Notification(
                    notification_id=str(uuid.uuid4()),
                    user_id=user_id,
                    audience=Role.PASSENGER.value,
                    type="trip_update",
                    title=title[:100],
                    message=message[:500],
                    related_entity_type="trip",
                    related_entity_id=trip.trip_id,
                    is_read=False,
                    delivery_status="queued",
                    created_at=now,
                )
            )

    async def notify_passenger(
        self, *, user_id: str, title: str, message: str, entity: tuple[str, str],
    ) -> None:
        """One passenger, about something that is not yet a trip (a
        special-trip request). Joins the caller's transaction."""
        self.session.add(
            Notification(
                notification_id=str(uuid.uuid4()),
                user_id=user_id,
                audience=Role.PASSENGER.value,
                type="trip_update",
                title=title[:100],
                message=message[:500],
                related_entity_type=entity[0],
                related_entity_id=entity[1],
                is_read=False,
                delivery_status="queued",
                created_at=app_tz.now(),
            )
        )

    # ------------------------------------------------------------------
    # Consumers
    # ------------------------------------------------------------------
    async def list_for_user(
        self, user_id: str, *, unread_only: bool = False, limit: int = 50
    ) -> tuple[list[Notification], int]:
        """Newest first, plus the unread count for a badge."""
        q = select(Notification).where(Notification.user_id == user_id)
        if unread_only:
            q = q.where(Notification.is_read.is_(False))
        rows = list(
            await self.session.scalars(
                q.order_by(Notification.created_at.desc()).limit(limit)
            )
        )
        unread = await self.session.scalar(
            select(func.count()).select_from(Notification).where(
                Notification.user_id == user_id,
                Notification.is_read.is_(False),
            )
        )
        return rows, int(unread or 0)

    async def mark_read(self, user_id: str, notification_id: str) -> bool:
        """Scoped to the caller so nobody can clear another user's row."""
        result = await self.session.execute(
            update(Notification)
            .where(
                Notification.notification_id == notification_id,
                Notification.user_id == user_id,
            )
            .values(is_read=True)
        )
        await self.session.commit()
        return result.rowcount > 0

    async def mark_all_read(self, user_id: str) -> int:
        result = await self.session.execute(
            update(Notification)
            .where(Notification.user_id == user_id, Notification.is_read.is_(False))
            .values(is_read=True)
        )
        await self.session.commit()
        return result.rowcount
