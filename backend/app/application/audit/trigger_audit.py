"""YOLOv8 passenger reconciliation -- the capstone's core contribution.

    visual_count  (bodies the camera sees)
  - booked_count  (seats the manifest says are occupied on this leg)
  ---------------
  = variance      (positive => undocumented passengers => revenue leakage)

Variance is computed HERE, on the server, against the authoritative
manifest in MySQL. The AI node reports only what it saw; it does not know
about trips, bookings, or fares. A client-side variance calculation would
be trivially forgeable by exactly the person it is meant to audit.

Negative variance is kept distinct from positive. Fewer bodies than
tickets is a different anomaly -- someone alighted early, or a no-show was
never recorded -- and conflating the two would make the leakage figure
meaningless.
"""

from __future__ import annotations

import base64
import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import ConflictError, NotFoundError
from app.domain.enums import AuditResolution
from app.infrastructure.clients.ai_node_client import AiNodeClient
from app.infrastructure.models import Trip, Yolov8AuditLog
from app.infrastructure.repositories.policy_repository import PolicyRepository

log = logging.getLogger(__name__)

MEDIA_ROOT = Path(__file__).resolve().parents[3] / "media" / "audits"


@dataclass(frozen=True)
class AuditResult:
    audit_id: str
    trip_id: str
    leg_sequence: int
    visual_count: int
    booked_count: int
    variance: int
    resolution_status: str
    snapshot_url: str | None
    model_version: str
    inference_ms: int
    confidence_avg: float | None
    alert_raised: bool
    message: str


class TriggerAuditUseCase:
    def __init__(self, session: AsyncSession):
        self.session = session
        self.ai = AiNodeClient()
        self.policies = PolicyRepository(session)

    async def execute(
        self,
        *,
        trip_id: str,
        leg_sequence: int,
        triggered_by_user_id: str,
        trigger_type: str = "manual",
    ) -> AuditResult:
        from app.application.operations.boarding import ManifestUseCase

        trip = await self.session.get(Trip, trip_id)
        if trip is None:
            raise NotFoundError("Trip not found.")
        if trip.status not in ("boarding", "departed"):
            raise ConflictError(
                f"Audits apply to a trip in progress; this one is {trip.status}."
            )

        # Manifest baseline BEFORE the capture, so the two counts describe
        # the same moment as closely as possible.
        booked_count = await ManifestUseCase(self.session).booked_count_on_leg(
            trip_id, leg_sequence
        )

        # Any failure here propagates as 502. Deliberately no fallback.
        capture = await self.ai.capture()

        variance = capture.visual_count - booked_count
        threshold = await self.policies.get_int("variance_alert_threshold")
        alert = abs(variance) >= threshold

        snapshot_url = self._store_snapshot(trip_id, capture.snapshot_b64)

        audit_id = str(uuid.uuid4())
        self.session.add(
            Yolov8AuditLog(
                audit_id=audit_id,
                trip_id=trip_id,
                leg_sequence=leg_sequence,
                triggered_by_user_id=triggered_by_user_id,
                trigger_type=trigger_type,
                visual_count=capture.visual_count,
                booked_count=booked_count,
                variance=variance,
                model_version=capture.model_version,
                inference_ms=capture.inference_ms,
                confidence_avg=(
                    Decimal(str(capture.confidence_avg))
                    if capture.confidence_avg is not None
                    else None
                ),
                snapshot_url=snapshot_url,
                resolution_status=(
                    AuditResolution.PENDING.value
                    if alert
                    else AuditResolution.RECONCILED.value
                ),
                captured_at=datetime.now(timezone.utc),
            )
        )
        await self.session.commit()

        if variance > 0:
            message = (
                f"{variance} more passenger(s) aboard than the manifest shows. "
                "Possible undocumented boarding."
            )
        elif variance < 0:
            message = (
                f"{abs(variance)} fewer passenger(s) than expected. "
                "Check for early alighting or an unrecorded no-show."
            )
        else:
            message = "Headcount matches the manifest."

        log.info(
            "Audit %s trip=%s leg=%s visual=%d booked=%d variance=%+d",
            audit_id, trip_id, leg_sequence,
            capture.visual_count, booked_count, variance,
        )

        return AuditResult(
            audit_id=audit_id,
            trip_id=trip_id,
            leg_sequence=leg_sequence,
            visual_count=capture.visual_count,
            booked_count=booked_count,
            variance=variance,
            resolution_status=(
                AuditResolution.PENDING.value if alert else AuditResolution.RECONCILED.value
            ),
            snapshot_url=snapshot_url,
            model_version=capture.model_version,
            inference_ms=capture.inference_ms,
            confidence_avg=capture.confidence_avg,
            alert_raised=alert,
            message=message,
        )

    @staticmethod
    def _store_snapshot(trip_id: str, b64: str) -> str | None:
        """Write the blurred snapshot to disk and return its served path.

        Local filesystem is a prototype choice -- object storage with
        signed URLs and a retention policy is the production answer, and
        that belongs in Limitations. The image is already face-blurred by
        the AI node before it ever reaches this process.
        """
        if not b64:
            return None
        try:
            MEDIA_ROOT.mkdir(parents=True, exist_ok=True)
            name = f"{trip_id}_{datetime.now(timezone.utc):%Y%m%d%H%M%S}_{uuid.uuid4().hex[:6]}.jpg"
            (MEDIA_ROOT / name).write_bytes(base64.b64decode(b64))
            return f"/media/audits/{name}"
        except (OSError, ValueError) as exc:
            # A snapshot that fails to save must not lose the counts --
            # the numbers are the audit; the image is corroboration.
            log.error("Could not store audit snapshot: %s", exc)
            return None


class ResolveAuditUseCase:
    """Operator dispositions a flagged variance."""

    def __init__(self, session: AsyncSession):
        self.session = session

    async def execute(
        self, *, audit_id: str, resolution: str, notes: str, resolved_by_user_id: str
    ) -> dict:
        audit = await self.session.get(Yolov8AuditLog, audit_id)
        if audit is None:
            raise NotFoundError("Audit not found.")
        if audit.resolution_status not in (
            AuditResolution.PENDING.value,
            AuditResolution.FAILED.value,
        ):
            raise ConflictError(f"Audit is already {audit.resolution_status}.")
        if resolution not in (
            AuditResolution.RESOLVED.value,
            AuditResolution.IGNORED.value,
        ):
            raise ConflictError("Resolution must be 'resolved' or 'ignored'.")
        if not notes.strip():
            raise ConflictError("A note is required when dispositioning an audit.")

        audit.resolution_status = resolution
        audit.resolved_by_user_id = resolved_by_user_id
        audit.resolved_at = datetime.now(timezone.utc)
        audit.resolution_notes = notes.strip()
        await self.session.commit()

        return {
            "audit_id": audit_id,
            "resolution_status": resolution,
            "resolved_at": audit.resolved_at.isoformat(),
        }


class AuditQueueUseCase:
    """Pending variances, newest first -- backs the operator console queue."""

    def __init__(self, session: AsyncSession):
        self.session = session

    async def pending(self, limit: int = 50) -> list[dict]:
        result = await self.session.execute(
            select(Yolov8AuditLog, Trip)
            .join(Trip, Trip.trip_id == Yolov8AuditLog.trip_id)
            .where(
                Yolov8AuditLog.resolution_status == AuditResolution.PENDING.value
            )
            .order_by(Yolov8AuditLog.captured_at.desc())
            .limit(limit)
        )
        return [
            {
                "audit_id": a.audit_id,
                "trip_id": a.trip_id,
                "trip_label": t.trip_label,
                "service_date": t.service_date,
                "leg_sequence": a.leg_sequence,
                "visual_count": a.visual_count,
                "booked_count": a.booked_count,
                "variance": a.variance,
                "snapshot_url": a.snapshot_url,
                "confidence_avg": a.confidence_avg,
                "inference_ms": a.inference_ms,
                "model_version": a.model_version,
                "captured_at": a.captured_at,
            }
            for a, t in result.all()
        ]
