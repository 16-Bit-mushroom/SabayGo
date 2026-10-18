"""Driving flags on the paper's sample trip -- application/tracking/driving.py.

Brief 12.1: Ecoland -> Toril -> Sta. Cruz -> Digos, 100 m stop zones,
55 km/h expected. The trip is rebuilt one reading a second from the
sample's events: an 88 km/h burst for 40 s against 60, a 210 s wait at a
declared home pickup, a 34 s en-route stop, a 244 s unscheduled stop,
and stretch times of 0.99, 1.01 and 1.45 times expected. Pure; no
database.

    python tests/test_driving_flags.py
"""

from __future__ import annotations

import sys
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.application.tracking.driving import (  # noqa: E402
    Reading, Rules, Stop, Stretch, Wait, flags,
)
from app.application.tracking.geometry import haversine_m  # noqa: E402

failures: list[str] = []


def check(cond: bool, label: str) -> None:
    print(f"  {'PASS' if cond else 'FAIL'}  {label}")
    if not cond:
        failures.append(label)


STOPS = [Stop(1, 7.0540, 125.6060, 100), Stop(2, 7.0130, 125.4960, 100),
         Stop(3, 6.8370, 125.4100, 100), Stop(4, 6.7500, 125.3570, 100)]
LEN = [haversine_m(a.lat, a.lon, b.lat, b.lon) for a, b in zip(STOPS, STOPS[1:])]
AT = [0.0, LEN[0], LEN[0] + LEN[1], sum(LEN)]          # stop positions along the route
EXPECTED = [round((n - 200) / (55 / 3.6)) for n in LEN]
STRETCHES = [Stretch(1, 60, EXPECTED[0]), Stretch(2, 80, EXPECTED[1]), Stretch(3, 60, EXPECTED[2])]
RULES = Rules(overspeed_s=10, stop_s=120, slow_ratio=1.25, standstill_kmh=2,
              gap_s=120, pickup_wait_s=600)
T0 = datetime(2026, 10, 15, 5, 30, 0)


def point(d: float) -> tuple[float, float]:
    for k in range(3):
        if d <= AT[k + 1] or k == 2:
            f = min(1.0, max(0.0, (d - AT[k]) / LEN[k]))
            a, b = STOPS[k], STOPS[k + 1]
            return a.lat + f * (b.lat - a.lat), a.lon + f * (b.lon - a.lon)
    raise AssertionError


def trip(speeds: bool = True) -> tuple[list[Reading], dict[str, tuple[datetime, datetime]]]:
    """The sample trip, one reading a second; and when each stop began and ended."""
    burst = 88 / 3.6 * 40
    v1 = (LEN[0] - 200 - burst) / (1038 - 210 - 40)       # 17.3 min measured, 3.5 waiting
    v2 = (LEN[1] - 200) / (1422 - 34 - 244)                # 23.7 min, two stops
    v3 = (LEN[2] - 200) / 1056                             # 17.6 min: slow
    plan = [("drive", 7043, v1), ("go", 40, 88 / 3.6), ("drive", 9400, v1), ("stand", 210, "pickup"),
            ("drive", AT[1], v1), ("drive", AT[1] + 4035, v2), ("stand", 34, "en_route"),
            ("drive", AT[1] + 8831, v2), ("stand", 244, "unscheduled"),
            ("drive", AT[2], v2), ("stand", 60, "sta_cruz"),
            ("drive", AT[3], v3), ("stand", 30, "digos")]
    out: list[Reading] = []
    spans: dict[str, tuple[datetime, datetime]] = {}
    t, d = 0, 0.0

    def emit(speed: float) -> None:
        lat, lon = point(d)
        out.append(Reading(T0 + timedelta(seconds=t), lat, lon, speed * 3.6 if speeds else None))

    for kind, a, b in plan:
        if kind == "drive":
            while d < a:
                d = min(a, d + b)
                t += 1
                emit(b)
        elif kind == "go":
            for _ in range(a):
                d += b
                t += 1
                emit(b)
        else:
            start = T0 + timedelta(seconds=t + 1)
            for _ in range(a):
                t += 1
                emit(0.0)
            spans[b] = (start, T0 + timedelta(seconds=t + 1))
    return out, spans


def kinds(found) -> list[str]:
    return [f.kind for f in found]


readings, spans = trip()
pickup = Wait(*spans["pickup"])
found = flags(readings, STOPS, STRETCHES, [pickup], RULES)

print("\nThe sample trip (brief 12.1)")
print("  flags:", kinds(found))
over = [f for f in found if f.kind == "overspeed"]
check(len(over) == 1, "one overspeed")
check(over and 39 <= over[0].duration_s <= 41 and over[0].max_speed_kmh == 88.0
      and over[0].limit_kmh == 60 and over[0].stretch_no == 1,
      "40 s at 88 km/h against 60, on Ecoland-Toril")
check(not [f for f in found if f.kind.endswith("stop")
           and spans["pickup"][0] <= f.start < spans["pickup"][1]],
      "the 210 s wait at the declared pin is not flagged, nor recorded as a stop")
en_route = [f for f in found if f.kind == "en_route_stop"]
check(len(en_route) == 1 and 33 <= en_route[0].duration_s <= 35,
      "the 34 s stop is an en-route stop (recorded, not flagged)")
stop = [f for f in found if f.kind == "unscheduled_stop"]
check(len(stop) == 1 and 243 <= stop[0].duration_s <= 245, "the 244 s stop is an unscheduled stop")
check(stop and abs(stop[0].nearest_stop_dist_m - 8831) < 20,
      f"8,830 m from the nearest stop ({stop[0].nearest_stop_dist_m:,.0f} m)" if stop else "distance")
slow = [f for f in found if f.kind == "slow_stretch"]
check(len(slow) == 1 and slow[0].stretch_no == 3 and abs(slow[0].time_ratio - 1.45) <= 0.01,
      f"only Sta. Cruz-Digos is slow, 1.45 ({slow[0].time_ratio if slow else '-'})")
check(not [f for f in found if f.kind.endswith("stop") and spans["sta_cruz"][0] <= f.start],
      "standing at Sta. Cruz and Digos, inside their zones, is not a stop")

print("\nStretch times (tolerance lowered to show every ratio)")
every = flags(readings, STOPS, STRETCHES, [pickup],
              Rules(**{**RULES.__dict__, "slow_ratio": 0.9}))
ratios = {f.stretch_no: f.time_ratio for f in every if f.kind == "slow_stretch"}
check(abs(ratios.get(1, 0) - 0.99) <= 0.01,
      f"Ecoland-Toril 0.99: 17.3 min less 3.5 waiting ({ratios.get(1)})")
check(abs(ratios.get(2, 0) - 1.01) <= 0.01, f"Toril-Sta. Cruz 1.01 ({ratios.get(2)})")

print("\nThe home-pickup wait")
none = flags(readings, STOPS, STRETCHES, [], RULES)
check(len([f for f in none if f.kind == "unscheduled_stop"]) == 2,
      "with no declared pickup, the 210 s wait is an unscheduled stop")
short = flags(readings, STOPS, STRETCHES, [pickup], Rules(**{**RULES.__dict__, "pickup_wait_s": 60}))
check(len([f for f in short if f.kind == "unscheduled_stop"]) == 2,
      "past the allowed wait (60 s here), the rest counts: 150 s is unscheduled")

print("\nReadings")
derived = flags(trip(speeds=False)[0], STOPS, STRETCHES, [pickup], RULES)
check(kinds(derived) == kinds(found), "with no speed sent, it is taken from the distance travelled")
cut = spans["unscheduled"][0] + timedelta(seconds=200)
partial = flags([r for r in readings if r.at <= cut], STOPS, STRETCHES, [pickup], RULES)
stop_now = [f for f in partial if f.kind == "unscheduled_stop"]
check(len(stop_now) == 1 and stop_now[0].end is None and stop_now[0].start == stop[0].start,
      "a stop still under way past 120 s is flagged with no end, from the same start")
early = flags([r for r in readings if r.at <= spans["unscheduled"][0] + timedelta(seconds=100)],
              STOPS, STRETCHES, [pickup], RULES)
check(not [f for f in early if f.start >= spans["unscheduled"][0]], "under 120 s, it waits")
s0 = spans["unscheduled"][0]
holed = [r for r in readings if not (s0 + timedelta(seconds=60) < r.at < s0 + timedelta(seconds=190))]
split = flags(holed, STOPS, STRETCHES, [pickup], RULES)
check(not [f for f in split if f.kind == "unscheduled_stop"],
      "a gap longer than the silent-phone gap breaks the stop: nothing is known inside it")

print(f"\n{'All passed.' if not failures else f'{len(failures)} failed.'}")
sys.exit(1 if failures else 0)
