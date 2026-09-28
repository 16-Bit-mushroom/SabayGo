"""In-app notifications.

Rows in `notifications` are the record; FCM delivery is a later concern
(the roadmap's Tier 3 decision: an in-app list is enough for testing, so
`delivery_status` stays 'queued' and `fcm_message_id` stays NULL).

The first producer is the YOLOv8 audit: a flagged variance used to be
written to `yolov8_audit_logs` and told no one. Now the office, the driver
and the conductor each get a row pointing at the audit, so the console's
queue is a destination rather than something staff must remember to open.
"""

from __future__ import annotations

import uuid

from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import timezone as app_tz
from app.domain.enums import Role
from app.infrastructure.models import Notification, Trip, User


class NotificationService:
    def __init__(self, session: AsyncSession):
        self.session = session

    # ------------------------------------------------------------------
    # Producers
    # ------------------------------------------------------------------
    async def notify_variance(
        self, *, audit_id: str, trip: Trip, leg_sequence: int,
        visual_count: int, booked_count: int, variance: int,
    ) -> int:
        """Alert office, driver and conductor about a flagged headcount.

        Adds rows to the session without committing; the caller owns the
        transaction so the audit log and its alerts land together.
        Returns the number of recipients.
        """
        if variance > 0:
            headline = f"{variance} more aboard than the manifest"
            detail = "Possible undocumented boarding."
        else:
            headline = f"{abs(variance)} fewer aboard than the manifest"
            detail = "Check for early alighting or an unrecorded no-show."
        plate = trip.van.plate_number if trip.van is not None else "unassigned van"
        route = trip.route.route_name if trip.route is not None else trip.route_id
        message = (
            f"{route} · {plate} · leg {leg_sequence}: camera counted "
            f"{visual_count}, manifest shows {booked_count}. {detail}"
        )

        recipients: list[tuple[str, str]] = []
        office = await self.session.scalars(
            select(User.user_id).where(
                User.role == Role.COOP_ADMIN.value,
                User.account_status == "active",
            )
        )
        recipients.extend((uid, Role.COOP_ADMIN.value) for uid in office)
        if trip.driver_id:
            recipients.append((trip.driver_id, Role.DRIVER.value))
        if trip.conductor_id:
            recipients.append((trip.conductor_id, Role.CONDUCTOR.value))

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

        recipients: list[tuple[str, str]] = []
        office = await self.session.scalars(
            select(User.user_id).where(
                User.role == Role.COOP_ADMIN.value,
                User.account_status == "active",
            )
        )
        recipients.extend((uid, Role.COOP_ADMIN.value) for uid in office)
        if trip is not None:
            if trip.driver_id:
                recipients.append((trip.driver_id, Role.DRIVER.value))
            if trip.conductor_id:
                recipients.append((trip.conductor_id, Role.CONDUCTOR.value))

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
                    Role.COOP_ADMIN.value
                    if alert.raised_by_role == Role.ADMIN.value
                    else alert.raised_by_role
                ),
                type="sos_alert",
                title="Your SOS has been seen",
                message=(
                    "The cooperative office has acknowledged your emergency "
                    "alert and is responding."
                ),
                related_entity_type="sos",
                related_entity_id=alert.sos_id,
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
