"""SOS emergency alerts (spec 2.3.5, Scope & Limitations).

The order of work in `RaiseSosUseCase` is the whole design:

    1. record the alert and its in-app notifications, and COMMIT
    2. only then attempt SMS
    3. record what each attempt actually did, and COMMIT again

An SMS gateway is a phone on a shelf or a vendor with a balance. Either
can be unreachable at the exact moment someone needs help, and a send that
blocks for ten seconds must not be standing between a panicking conductor
and a saved record. So the emergency is durable before the first packet
leaves, and the reply the handset gets says plainly how many texts went
out -- including "none, nobody is configured to receive them".

This is the same rule the YOLOv8 node follows: an unreachable device is an
error state, never a fabricated success.
"""

from __future__ import annotations

import logging
import uuid
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.identity.naming import display_name
from app.application.notifications.service import NotificationService
from app.core import timezone as app_tz
from app.core.exceptions import ConflictError, NotFoundError, PermissionDeniedError
from app.domain.enums import BookingStatus, Role, SosStatus
from app.infrastructure.clients.sms_client import SmsClient
from app.infrastructure.models import (
    Booking,
    CooperativePolicy,
    SosAlert,
    SosDispatch,
    Trip,
    User,
)

log = logging.getLogger(__name__)

SOS_CONTACTS_POLICY = "sos_contact_numbers"

# Bookings that put a passenger on a van, or on their way to one. A
# cancelled booking is not a seat in the vehicle, so it is not grounds to
# raise an emergency against that trip's crew.
_ABOARD = {
    BookingStatus.CONFIRMED.value,
    BookingStatus.CHECKED_IN.value,
    BookingStatus.BOARDED.value,
    BookingStatus.COMPLETED.value,
}


def _where(alert: SosAlert) -> str:
    """Human-readable position, or an honest admission there isn't one."""
    if alert.latitude is None or alert.longitude is None:
        return "Location unavailable"
    accuracy = f" (±{alert.accuracy_m:.0f} m)" if alert.accuracy_m is not None else ""
    return f"At {alert.latitude:.6f}, {alert.longitude:.6f}{accuracy}"


def _map_link(alert: SosAlert) -> str | None:
    """OpenStreetMap, the same source the live map draws from -- and no
    Google dependency anywhere in the stack. Four decimals is ~11 m,
    which keeps the whole message inside two SMS segments."""
    if alert.latitude is None or alert.longitude is None:
        return None
    return (
        f"https://www.openstreetmap.org/"
        f"?mlat={alert.latitude:.4f}&mlon={alert.longitude:.4f}"
    )


class RaiseSosUseCase:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def execute(
        self,
        *,
        user: User,
        trip_id: str | None,
        category: str,
        note: str | None,
        latitude: float | None,
        longitude: float | None,
        accuracy_m: float | None,
    ) -> dict:
        trip = await self._authorize_trip(user, trip_id)

        # A frightened thumb presses the button more than once. A second
        # press while the first alert is still open returns that alert
        # instead of raising a new emergency and a second round of texts --
        # the office should see one incident, not five.
        existing = await self.session.scalar(
            select(SosAlert).where(
                SosAlert.raised_by_user_id == user.user_id,
                SosAlert.status != SosStatus.RESOLVED.value,
            ).order_by(SosAlert.raised_at.desc()).limit(1)
        )
        if existing is not None:
            return {
                "sos_id": existing.sos_id,
                "status": existing.status,
                "raised_at": existing.raised_at,
                "duplicate": True,
                "notified_in_app": 0,
                "sms": _dispatch_summary(list(existing.dispatches)),
                "message": "Your earlier SOS is still open. The office already has it.",
            }

        alert = SosAlert(
            sos_id=str(uuid.uuid4()),
            raised_by_user_id=user.user_id,
            raised_by_role=user.role,
            trip_id=trip.trip_id if trip is not None else None,
            category=category,
            note=(note or "").strip()[:255] or None,
            latitude=None if latitude is None else Decimal(str(round(latitude, 6))),
            longitude=None if longitude is None else Decimal(str(round(longitude, 6))),
            accuracy_m=None if accuracy_m is None else Decimal(str(round(accuracy_m, 1))),
            status=SosStatus.OPEN.value,
            raised_at=app_tz.now(),
        )
        self.session.add(alert)

        raiser_name = display_name(user)
        notified = await NotificationService(self.session).notify_sos(
            alert=alert,
            raiser_name=raiser_name,
            raiser_role=user.role,
            trip=trip,
            where=_where(alert),
        )
        # Step 1 ends here. Whatever the SMS gateway does next, the
        # emergency is on disk and the office's bell has it.
        await self.session.commit()

        results = await self._dispatch_sms(alert, raiser_name, user.role, trip)
        summary = _dispatch_summary(results)

        return {
            "sos_id": alert.sos_id,
            "status": alert.status,
            "raised_at": alert.raised_at,
            "duplicate": False,
            "notified_in_app": notified,
            "sms": summary,
            "message": _crew_message(notified, summary),
        }

    # ------------------------------------------------------------------
    async def _authorize_trip(self, user: User, trip_id: str | None) -> Trip | None:
        """An SOS may name a trip only if the raiser is actually on it.

        Without this, any signed-in account could raise an emergency
        against any crew in the fleet -- a false alarm aimed at a named
        driver, which is exactly the accusation this system is built to
        avoid making carelessly. An SOS with no trip is always allowed:
        a passenger waiting at the terminal has an emergency too.
        """
        if trip_id is None:
            return None
        trip = await self.session.get(Trip, trip_id)
        if trip is None:
            raise NotFoundError("Trip not found.")

        if user.role in (Role.COOP_ADMIN.value, Role.ADMIN.value):
            return trip
        if user.role in (Role.DRIVER.value, Role.CONDUCTOR.value):
            if user.user_id not in (trip.driver_id, trip.conductor_id):
                raise PermissionDeniedError("You are not crewed on this trip.")
            return trip
        booked = await self.session.scalar(
            select(Booking.booking_id).where(
                Booking.trip_id == trip_id,
                Booking.passenger_user_id == user.user_id,
                Booking.status.in_(_ABOARD),
            ).limit(1)
        )
        if booked is None:
            raise PermissionDeniedError("You have no booking on this trip.")
        return trip

    async def _contact_numbers(self) -> list[str]:
        policy = await self.session.get(CooperativePolicy, SOS_CONTACTS_POLICY)
        raw = policy.policy_value if policy else ""
        return [n.strip() for n in raw.split(",") if n.strip()]

    async def _dispatch_sms(
        self, alert: SosAlert, raiser_name: str, raiser_role: str, trip: Trip | None
    ) -> list[SosDispatch]:
        recipients = await self._contact_numbers()
        if not recipients:
            log.warning(
                "SOS %s raised with no contact numbers configured (%s policy).",
                alert.sos_id, SOS_CONTACTS_POLICY,
            )
            return []

        results = await SmsClient().send_many(recipients, _sms_body(
            alert, raiser_name, raiser_role, trip
        ))
        now = app_tz.now()
        rows = [
            SosDispatch(
                sos_id=alert.sos_id,
                provider=r.provider,
                recipient=r.recipient[:20],
                status=r.status,
                provider_message_id=r.message_id,
                error=r.error,
                attempted_at=now,
            )
            for r in results
        ]
        self.session.add_all(rows)
        await self.session.commit()
        return rows


def _sms_body(
    alert: SosAlert, raiser_name: str, raiser_role: str, trip: Trip | None
) -> str:
    lines = [f"SabayGo SOS [{alert.category.upper()}]", f"{raiser_name} ({raiser_role})"]
    if trip is not None:
        plate = trip.van.plate_number if trip.van is not None else "no van"
        route = trip.route.route_name if trip.route is not None else trip.route_id
        lines.append(f"{route} {trip.departure_datetime:%H:%M} / {plate}")
    link = _map_link(alert)
    lines.append(link if link else "Location unavailable")
    if alert.note:
        lines.append(alert.note)
    return "\n".join(lines)[:320]


def _dispatch_summary(rows: list[SosDispatch]) -> dict:
    return {
        "attempted": len(rows),
        "sent": sum(1 for r in rows if r.status == "sent"),
        "failed": sum(1 for r in rows if r.status == "failed"),
        "skipped": sum(1 for r in rows if r.status == "skipped"),
        "recipients": [
            {
                "recipient": r.recipient,
                "provider": r.provider,
                "status": r.status,
                "error": r.error,
            }
            for r in rows
        ],
    }


def _crew_message(notified: int, summary: dict) -> str:
    """What the handset says back. It never overstates delivery."""
    head = (
        f"Alert recorded. {notified} in-app alert(s) sent to the office."
        if notified
        else "Alert recorded, but no office account is active to receive it."
    )
    if summary["attempted"] == 0:
        return head + " No SMS was sent: no emergency contact numbers are set."
    if summary["sent"]:
        return head + f" SMS sent to {summary['sent']} of {summary['attempted']} number(s)."
    return head + " SMS could not be delivered -- check the gateway."


class SosQueueUseCase:
    """The office's emergency list, and the history behind it."""

    def __init__(self, session: AsyncSession):
        self.session = session

    async def list(
        self, *, status: str | None = None, limit: int = 50
    ) -> list[dict]:
        q = select(SosAlert)
        if status == "open":
            # The work list: anything not yet put to bed.
            q = q.where(SosAlert.status != SosStatus.RESOLVED.value)
        elif status:
            q = q.where(SosAlert.status == status)
        rows = list(
            await self.session.scalars(
                q.order_by(SosAlert.raised_at.desc()).limit(limit)
            )
        )
        out = []
        for a in rows:
            raiser = await self.session.get(User, a.raised_by_user_id)
            ack = (
                await self.session.get(User, a.acknowledged_by_user_id)
                if a.acknowledged_by_user_id
                else None
            )
            out.append(
                {
                    "sos_id": a.sos_id,
                    "status": a.status,
                    "category": a.category,
                    "note": a.note,
                    "raised_by": display_name(raiser) if raiser else "Unknown user",
                    "raised_by_role": a.raised_by_role,
                    "raised_by_phone": raiser.phone_number if raiser else None,
                    "raised_at": a.raised_at,
                    "trip_id": a.trip_id,
                    "trip_label": _trip_label(a.trip),
                    "latitude": float(a.latitude) if a.latitude is not None else None,
                    "longitude": float(a.longitude) if a.longitude is not None else None,
                    "accuracy_m": float(a.accuracy_m) if a.accuracy_m is not None else None,
                    "map_url": _map_link(a),
                    "acknowledged_by": display_name(ack) if ack else None,
                    "acknowledged_at": a.acknowledged_at,
                    "resolved_at": a.resolved_at,
                    "resolution_notes": a.resolution_notes,
                    "sms": _dispatch_summary(list(a.dispatches)),
                }
            )
        return out


def _trip_label(trip: Trip | None) -> str | None:
    if trip is None:
        return None
    route = trip.route.route_name if trip.route is not None else trip.route_id
    plate = trip.van.plate_number if trip.van is not None else "unassigned"
    return f"{route} · {trip.departure_datetime:%b %d %H:%M} · {plate}"


class DispositionSosUseCase:
    """The office acknowledges, then resolves.

    Acknowledging is the useful half: it tells the person who pressed the
    button that a human has seen it. Resolving is terminal and needs a
    note, for the same reason an audit does -- a closed emergency with no
    account of what happened is not a record.
    """

    def __init__(self, session: AsyncSession):
        self.session = session

    async def execute(
        self, *, sos_id: str, action: str, notes: str | None, user_id: str
    ) -> dict:
        alert = await self.session.get(SosAlert, sos_id)
        if alert is None:
            raise NotFoundError("SOS alert not found.")
        if alert.status == SosStatus.RESOLVED.value:
            raise ConflictError("This alert is already resolved.")

        now = app_tz.now()
        if action == "acknowledge":
            if alert.status == SosStatus.ACKNOWLEDGED.value:
                raise ConflictError("This alert is already acknowledged.")
            alert.status = SosStatus.ACKNOWLEDGED.value
            alert.acknowledged_by_user_id = user_id
            alert.acknowledged_at = now
            # The single thing the person in trouble most needs to know.
            await NotificationService(self.session).notify_sos_acknowledged(alert=alert)
        else:
            if not (notes or "").strip():
                raise ConflictError("A note is required when closing an emergency.")
            # An alert resolved without ever being acknowledged still gets
            # an acknowledgement stamp -- somebody clearly saw it.
            if alert.acknowledged_at is None:
                alert.acknowledged_by_user_id = user_id
                alert.acknowledged_at = now
            alert.status = SosStatus.RESOLVED.value
            alert.resolved_by_user_id = user_id
            alert.resolved_at = now
            alert.resolution_notes = notes.strip()[:512]

        await self.session.commit()
        return {
            "sos_id": alert.sos_id,
            "status": alert.status,
            "acknowledged_at": alert.acknowledged_at,
            "resolved_at": alert.resolved_at,
        }
