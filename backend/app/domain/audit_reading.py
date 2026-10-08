"""What a YOLOv8 audit result means, in words the office can act on.

An audit is two numbers -- who the camera counted, who the manifest says
is aboard -- and their difference. The difference only means something
once its direction is read, and the two directions mean very different
things for a cooperative:

  * MORE people than the manifest is the case the system exists for:
    someone may be riding without a ticket or a logged cash fare, which
    is revenue that never reaches the office (undocumented boarding).
  * FEWER people than the manifest is not lost money -- every one of
    those fares was already paid or logged. It is almost always the
    camera's view: someone out of frame, hidden behind a seat or another
    passenger, or a booked passenger who has not boarded and was not
    marked a no-show.

Written once here, so the audit queue, the Trips screen and the phone
all say the same thing about the same result. Pure: no database, no
HTTP, testable in isolation.
"""

from __future__ import annotations

from dataclasses import dataclass

# Below this mean detection confidence the count is shown with a caution.
# The detector's own threshold is 0.45 (ai_service); a mean barely above it
# says most boxes were near-misses.
LOW_CONFIDENCE = 0.6


@dataclass(frozen=True)
class AuditReading:
    verdict: str  # "match" | "more_than_manifest" | "fewer_than_manifest"
    headline: str
    explanation: str
    next_step: str
    caution: str | None


def _people(n: int) -> str:
    return f"{n} person" if n == 1 else f"{n} people"


def read_audit(
    *,
    visual_count: int,
    booked_count: int,
    leg_sequence: int,
    confidence_avg: float | None,
) -> AuditReading:
    """Short on purpose: these are read at a glance beside a manifest, so
    each field is a phrase, never a paragraph. `leg_sequence` is accepted
    for callers' symmetry; the screens already show the leg."""
    variance = visual_count - booked_count

    caution = None
    if visual_count == 0 and booked_count > 0:
        caution = "Camera saw no one -- lens may be blocked or aimed away."
    elif confidence_avg is not None and confidence_avg < LOW_CONFIDENCE:
        caution = f"Low confidence ({confidence_avg:.0%}) -- count is approximate."

    if variance > 0:
        n = variance
        return AuditReading(
            verdict="more_than_manifest",
            headline=f"{n} more {'person' if n == 1 else 'people'} than the manifest",
            explanation="Possible unrecorded passengers.",
            next_step="Ask the conductor about unlogged walk-ins; check the snapshot.",
            caution=caution,
        )

    if variance < 0:
        n = -variance
        return AuditReading(
            verdict="fewer_than_manifest",
            headline=f"{n} fewer {'person' if n == 1 else 'people'} than the manifest",
            explanation="Not lost revenue -- likely out of camera view.",
            next_step="Check the snapshot; mark no-shows or ignore.",
            caution=caution,
        )

    return AuditReading(
        verdict="match",
        headline="Matches the manifest",
        explanation="All passengers accounted for.",
        next_step="No action needed.",
        caution=caution,
    )
