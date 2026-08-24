"""Application timezone.

MySQL runs with --default-time-zone=+08:00 (see docker-compose.yml) and
stores naive DATETIME values in Manila local time. Python must attach the
SAME zone when reading them back.

Treating a Manila timestamp as UTC shifts every comparison by eight hours,
which silently breaks the check-in window, the reschedule cutoff, and the
"already departed" guard -- silently, because eight hours of skew still
leaves most trips plausibly in the future. The failure only surfaces at a
boundary, which is the worst kind of bug to find during a demo.

Single-timezone deployment is a deliberate scope decision for a Davao
cooperative. Note it in Limitations: multi-region operation would require
storing UTC and converting at the presentation edge.
"""

from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

APP_TZ = ZoneInfo("Asia/Manila")


def now() -> datetime:
    """Timezone-aware current time in the application zone."""
    return datetime.now(APP_TZ)


def localize(value: datetime | None) -> datetime | None:
    """Attach APP_TZ to a naive datetime read from MySQL.

    Values that already carry a timezone are returned unchanged, so this
    is safe to apply defensively.
    """
    if value is None:
        return None
    return value.replace(tzinfo=APP_TZ) if value.tzinfo is None else value
