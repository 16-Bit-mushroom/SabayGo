"""Client for the in-van YOLOv8 inference node."""

from __future__ import annotations

import logging
from dataclasses import dataclass

import httpx

from app.config import settings
from app.core.exceptions import UpstreamServiceError

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class CaptureResult:
    visual_count: int
    confidence_avg: float | None
    model_version: str
    conf_threshold: float
    capture_ms: int
    inference_ms: int
    total_ms: int
    snapshot_b64: str


class AiNodeClient:
    def __init__(self, base_url: str | None = None, api_key: str | None = None):
        self.base_url = (base_url or settings.ai_node_url).rstrip("/")
        self.api_key = api_key or settings.ai_node_api_key

    async def capture(self) -> CaptureResult:
        """Trigger a cabin capture and return the count.

        Raises UpstreamServiceError on any failure. It NEVER returns a
        fabricated count -- the original Flutter implementation caught
        network errors and substituted visual_count=1 with a 1x1 blank
        image, which would display a fake audit as authoritative. A missing
        audit is recoverable; a fabricated one that flags a driver for
        theft is not.
        """
        if not self.api_key:
            raise UpstreamServiceError("AI node API key is not configured.")

        try:
            async with httpx.AsyncClient(timeout=settings.ai_node_timeout_s) as client:
                r = await client.post(
                    f"{self.base_url}/api/audit/capture",
                    headers={"X-API-Key": self.api_key},
                )
        except httpx.RequestError as exc:
            log.error("AI node unreachable at %s: %s", self.base_url, exc)
            raise UpstreamServiceError(
                "The van's camera node did not respond. No audit was recorded."
            ) from exc

        if r.status_code == 401:
            raise UpstreamServiceError("AI node rejected the API key.")
        if r.status_code == 503:
            raise UpstreamServiceError("The van's camera is unavailable.")
        if r.status_code >= 400:
            log.error("AI node error %s: %s", r.status_code, r.text[:300])
            raise UpstreamServiceError(f"AI node returned {r.status_code}.")

        data = r.json()
        return CaptureResult(
            visual_count=int(data["visual_count"]),
            confidence_avg=data.get("confidence_avg"),
            model_version=data.get("model_version", "unknown"),
            conf_threshold=float(data.get("conf_threshold", 0)),
            capture_ms=int(data.get("capture_ms", 0)),
            inference_ms=int(data.get("inference_ms", 0)),
            total_ms=int(data.get("total_ms", 0)),
            snapshot_b64=data.get("snapshot_b64", ""),
        )

    async def health(self) -> dict:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                r = await client.get(f"{self.base_url}/health")
                r.raise_for_status()
                return r.json()
        except httpx.HTTPError as exc:
            raise UpstreamServiceError("AI node health check failed.") from exc
