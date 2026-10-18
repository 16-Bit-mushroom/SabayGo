"""Did the phone watch this trip? The Unaudited rule (brief 4.4).

The edge phone is a trip's only camera witness. A trip it could not watch
is Unaudited: the statement counts only its QR tickets and logged fares,
and nothing the camera says is held against the trip. Never a refusal --
the service always continues. Four reasons:

  no_phone         no phone was checked out with the van at the start
  silent_at_start  its last report is older than `heartbeat_gap_seconds`,
                   or it never reported
  lens_blocked     a report says the lens is covered or the camera is not
                   working -- at the start, or a covered lens at any
                   point of the trip
  lost_en_route    a gap in the reports during the trip that the reports
                   the phone stored while offline do not cover

A silence mid-trip is alerted at once (`alert_silent_phones`) but marked
only when it is final: when the phone reconnects and its stored reports
leave the gap open, or the trip ends with it open. A gap in mobile data
is not a camera switched off. A report covers the time up to it when the
camera and the GPS both worked and the lens was clear.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.application.notifications.service import NotificationService, trip_label
from app.core import timezone as app_tz
from app.domain.enums import Role, TripAuditStatus, TripStatus, UnauditedReason
from app.infrastructure.models import (
    DeviceCheckout,
    DeviceHeartbeat,
    EdgeDevice,
    Notification,
    Trip,
    Van,
)
from app.infrastructure.repositories.policy_repository import PolicyRepository

OFFICE = (Role.TERMINAL_MANAGER, Role.CASHIER)
OPEN = (TripStatus.BOARDING.value, TripStatus.DEPARTED.value)


def _covers(report: DeviceHeartbeat) -> bool:
    return report.camera_ok and report.gps_ok and not report.lens_blocked


class PhoneEvidence:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.notifications = NotificationService(session)

    async def gap(self) -> timedelta:
        return timedelta(seconds=await PolicyRepository(self.session).get_int("heartbeat_gap_seconds"))

    # ------------------------------------------------------------ start
    async def at_start(
        self, trip: Trip, van: Van, *, now: datetime, skip_user_id: str | None,
    ) -> list[str]:
        """Judge the phone with the van as the trip starts. Marks the trip
        Unaudited when it cannot watch, and returns the starter's warnings."""
        checkout = (await self.session.execute(
            select(DeviceCheckout).where(
                DeviceCheckout.van_id == van.van_id, DeviceCheckout.returned_at.is_(None)
            )
        )).scalars().first()
        if checkout is None:
            why = f"No phone is checked out with {van.plate_number}."
            await self.mark(trip, UnauditedReason.NO_PHONE, at=now, why=why, skip_user_id=skip_user_id)
            return [f"{why} The trip is Unaudited: the camera cannot check it."]

        last = await self._latest_report(checkout.device_id)
        if last is None or now - last.recorded_at > await self.gap():
            why = (f"The phone with {van.plate_number} has never sent a status report."
                   if last is None else
                   f"The phone with {van.plate_number} has not reported since "
                   f"{last.recorded_at:%H:%M}.")
            await self.mark(trip, UnauditedReason.SILENT_AT_START, at=now, why=why,
                            skip_user_id=skip_user_id)
            return [f"{why} The trip is Unaudited: check that its app is open."]
        if last.lens_blocked or not last.camera_ok:
            why = (f"The phone with {van.plate_number} reports its camera "
                   + ("covered." if last.lens_blocked else "not working."))
            await self.mark(trip, UnauditedReason.LENS_BLOCKED, at=now, why=why,
                            skip_user_id=skip_user_id)
            return [f"{why} The trip is Unaudited."]
        if not last.gps_ok:
            # Warn only: none of the four reasons is a GPS fault, and the
            # camera still counts. A GPS gap later in the trip is not
            # covered, so it does count against the trip (lost_en_route).
            return [f"The phone with {van.plate_number} reports its GPS not working."]
        return []

    # ----------------------------------------------------- during the trip
    async def review_coverage(self, trip: Trip) -> None:
        """Mark the trip if its reports leave a gap, or show a covered lens.

        Call after a phone's reports arrive and when the trip ends. While
        the trip is open, the time since the newest report is not judged:
        the phone may still send it."""
        if (trip.audit_status != TripAuditStatus.AUDITED.value
                or trip.started_at is None or trip.van_id is None):
            return
        gap = await self.gap()
        end = trip.completed_at
        devices = (await self.session.execute(
            select(DeviceCheckout.device_id).where(
                DeviceCheckout.van_id == trip.van_id,
                DeviceCheckout.checked_out_at <= (end or app_tz.now().replace(tzinfo=None)),
                or_(DeviceCheckout.returned_at.is_(None),
                    DeviceCheckout.returned_at >= trip.started_at),
            )
        )).scalars().all()
        if not devices:
            return  # no phone: decided at the start

        stmt = select(DeviceHeartbeat).where(
            DeviceHeartbeat.device_id.in_(devices),
            DeviceHeartbeat.recorded_at >= trip.started_at - gap,
        ).order_by(DeviceHeartbeat.recorded_at)
        if end is not None:
            stmt = stmt.where(DeviceHeartbeat.recorded_at <= end)
        reports = (await self.session.execute(stmt)).scalars().all()

        covered_to = trip.started_at
        for report in reports:
            if report.recorded_at > covered_to + gap:
                await self._lost(trip, covered_to)
                return
            if report.lens_blocked and report.recorded_at >= trip.started_at:
                await self.mark(
                    trip, UnauditedReason.LENS_BLOCKED, at=report.recorded_at,
                    why=f"The phone reported its camera covered at {report.recorded_at:%H:%M}.",
                )
                return
            if _covers(report):
                covered_to = max(covered_to, report.recorded_at)
        if end is not None and end > covered_to + gap:
            await self._lost(trip, covered_to)

    async def _lost(self, trip: Trip, since: datetime) -> None:
        await self.mark(
            trip, UnauditedReason.LOST_EN_ROUTE, at=since,
            why=f"The phone's reports leave the trip unwatched from {since:%H:%M}, "
                "and the reports it stored offline do not cover the gap.",
        )

    # ----------------------------------------------------------- marking
    async def mark(
        self, trip: Trip, reason: UnauditedReason, *, at: datetime, why: str,
        skip_user_id: str | None = None,
    ) -> None:
        """Unaudited from `at`, once: the first reason stands."""
        if trip.audit_status == TripAuditStatus.UNAUDITED.value:
            return
        trip.audit_status = TripAuditStatus.UNAUDITED.value
        trip.unaudited_at = at
        trip.unaudited_reason = reason.value
        await self.notifications.notify_trip(
            trip=trip, type="unaudited_trip",
            title=f"Unaudited trip · {reason.value.replace('_', ' ')}",
            message=f"{trip_label(trip)}: {why} The statement counts only its QR "
                    "tickets and logged fares.",
            roles=OFFICE, dispatcher=True, skip_user_id=skip_user_id,
        )

    async def _latest_report(self, device_id: str) -> DeviceHeartbeat | None:
        return (await self.session.execute(
            select(DeviceHeartbeat).where(DeviceHeartbeat.device_id == device_id)
            .order_by(DeviceHeartbeat.recorded_at.desc()).limit(1)
        )).scalar_one_or_none()


async def alert_silent_phones(session_factory) -> None:
    """A `PeriodicJob` tick: alert at once when the phone of a trip under
    way goes silent (4.4). The mark waits for the stored reports."""
    async with session_factory() as session:
        evidence = PhoneEvidence(session)
        gap = await evidence.gap()
        now = app_tz.now().replace(tzinfo=None)
        silent = (await session.execute(
            select(DeviceCheckout, EdgeDevice)
            .join(EdgeDevice, EdgeDevice.device_id == DeviceCheckout.device_id)
            .where(
                DeviceCheckout.returned_at.is_(None),
                EdgeDevice.status == "checked_out",
                or_(EdgeDevice.last_heartbeat_at.is_(None),
                    EdgeDevice.last_heartbeat_at < now - gap),
            )
        )).all()
        for checkout, device in silent:
            trip = (await session.execute(
                select(Trip).where(
                    Trip.van_id == checkout.van_id,
                    Trip.status.in_(OPEN),
                    Trip.audit_status == TripAuditStatus.AUDITED.value,
                ).order_by(Trip.started_at.desc()).limit(1)
            )).scalar_one_or_none()
            if trip is None:
                continue
            since = max(device.last_heartbeat_at or trip.started_at, trip.started_at)
            already = (await session.execute(
                select(Notification.notification_id).where(
                    Notification.type == "unaudited_trip",
                    Notification.related_entity_id == trip.trip_id,
                    Notification.created_at > since,
                ).limit(1)
            )).first()
            if already:
                continue
            await evidence.notifications.notify_trip(
                trip=trip, type="unaudited_trip", title="Phone silent · trip may be Unaudited",
                message=f"{trip_label(trip)}: the phone has not reported since {since:%H:%M}. "
                        "The trip stays Audited if the reports it stored cover the gap when "
                        "it reconnects; otherwise, or if the trip ends first, it becomes "
                        "Unaudited from then.",
                roles=OFFICE, dispatcher=True,
            )
        await session.commit()
