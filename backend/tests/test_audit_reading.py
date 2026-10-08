"""What an audit result is read as -- domain/audit_reading.py.

The direction of a variance carries the meaning: more people than the
manifest is possible leakage, fewer is a camera-view problem and never
lost revenue. If those two ever swapped, the console would send the
office chasing honest conductors. Pure function; no database.

    python tests/test_audit_reading.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.domain.audit_reading import read_audit  # noqa: E402

failures: list[str] = []


def check(cond: bool, label: str) -> None:
    print(f"  {'PASS' if cond else 'FAIL'}  {label}")
    if not cond:
        failures.append(label)


def reading(visual: int, booked: int, conf: float | None = 0.8):
    return read_audit(visual_count=visual, booked_count=booked, leg_sequence=1,
                      confidence_avg=conf)


over = reading(7, 5)
check(over.verdict == "more_than_manifest", "+2 reads as more than the manifest")
check(over.headline == "2 more people than the manifest", "+2 headline names the two extra people")
check("unrecorded passengers" in over.explanation, "+2 explains it as possible leakage")

under = reading(1, 5)
check(under.verdict == "fewer_than_manifest", "-4 reads as fewer than the manifest")
check("not lost revenue" in under.explanation.lower(), "-4 says plainly it is not lost money")
check(under.caution is None, "-4 at good confidence carries no caution")

check(reading(5, 5).verdict == "match", "equal counts read as a match")
check(reading(1, 0).headline == "1 more person than the manifest",
      "singular: 1 person, not 1 people")

check(reading(0, 5).caution is not None and "saw no one" in reading(0, 5).caution,
      "a zero count against a full manifest warns about the camera")
check(reading(0, 0).caution is None, "zero against an empty manifest is no cause for alarm")
check(reading(5, 5, conf=0.5).caution is not None, "low confidence is flagged")
check(reading(5, 5, conf=None).caution is None, "unknown confidence is not invented as low")

# Brevity is a requirement, not a style: these sit beside a manifest.
for v, b, c in [(7, 5, 0.8), (1, 5, 0.8), (5, 5, 0.8), (0, 5, None), (5, 5, 0.5)]:
    r = reading(v, b, c)
    longest = max(len(f) for f in (r.headline, r.explanation, r.next_step, r.caution or ""))
    check(longest <= 70, f"{v} vs {b}: every field is one short line ({longest} chars)")

print(f"\n{'ALL PASSED' if not failures else f'{len(failures)} FAILED'}")
sys.exit(1 if failures else 0)
