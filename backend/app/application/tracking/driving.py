"""Driving flags from a trip's GPS readings, with no database.

Rev 603, change brief 6.3-6.4. Pure, like `geometry`, so the paper's
sample trip can be replayed in a unit test (`tests/test_driving_flags.py`).
Every threshold is one of A2Z's settings, handed in as `Rules`. A flag is
an indicator for review, not proof of misconduct.

  overspeed         the speed stays above the limit of the stretch the van
                    is on for `overspeed_s` or more;
  unscheduled_stop  a standstill (`standstill_kmh` or less) longer than
                    `stop_s` away from every stop zone, not counting the
                    allowed wait at a declared home pickup;
  en_route_stop     the same, `stop_s` or shorter: recorded, not flagged;
  slow_stretch      leaving one stop zone to entering the next took more
                    than `slow_ratio` times the stretch's expected time,
                    less the declared home-pickup wait in between.

A standstill that overlaps a declared home pickup is that pickup's stop:
never an en-route stop, and an unscheduled stop only for what lasts past
`pickup_wait_s` from the van's arrival (6.3). The stretch time subtracts
the whole declared wait, arrival to leaving, as 6.3 states.

Readings further apart than `gap_s` (the silent-phone gap) do not make
one episode: a run of fast or still readings breaks at such a gap, since
nothing is known about what happened in it. A stretch time is wall-clock
and does not need the gap filled. A reading with no speed takes the
speed from the distance to the reading before it.

A special trip (a rental) has no route: no stretches, no stop zones.
Only overspeed applies to it, against one limit (`rental_flags`, brief
2.5).

A run still under way when the readings end is reported with no end
(`end` None) once it already qualifies; a short stop still under way is
not reported yet. Flags are keyed by kind and start, so a later
recomputation over more readings extends the same flag.
"""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from datetime import datetime, timedelta

from app.application.tracking.geometry import haversine_m, snap_to_route


@dataclass(frozen=True)
class Reading:
    at: datetime
    lat: float
    lon: float
    speed_kmh: float | None = None


@dataclass(frozen=True)
class Stop:
    seq: int
    lat: float
    lon: float
    radius_m: float


@dataclass(frozen=True)
class Stretch:
    no: int             # stop `no` -> stop `no + 1`
    limit_kmh: float
    expected_s: int


@dataclass(frozen=True)
class Wait:
    """A declared home pickup: the van arrived at the pin, and left."""
    arrived: datetime
    left: datetime | None


@dataclass(frozen=True)
class Rules:
    overspeed_s: int
    stop_s: int
    slow_ratio: float
    standstill_kmh: float
    gap_s: int
    pickup_wait_s: int


@dataclass
class Flag:
    kind: str
    start: datetime
    end: datetime | None
    lat: float
    lon: float
    stretch_no: int | None = None
    max_speed_kmh: float | None = None
    limit_kmh: float | None = None
    time_ratio: float | None = None
    nearest_stop_dist_m: float | None = None
    duration_s: int | None = None


@dataclass
class _Point:
    r: Reading
    speed: float
    stretch: int | None
    zone: int | None            # the stop whose zone the van is in
    nearest_m: float


def _seconds(a: datetime, b: datetime) -> float:
    return (b - a).total_seconds()


def _overlap(a0: datetime, a1: datetime, b0: datetime, b1: datetime) -> float:
    return max(0.0, _seconds(max(a0, b0), min(a1, b1)))


def _points(readings: Sequence[Reading], stops: Sequence[Stop]) -> list[_Point]:
    """Each reading with its speed, and, on a route, its stretch and zone."""
    line = [(s.seq, s.lat, s.lon) for s in stops]
    out: list[_Point] = []
    prev: Reading | None = None
    for r in readings:
        speed = r.speed_kmh
        if speed is None:
            dt = _seconds(prev.at, r.at) if prev else 0.0
            speed = (haversine_m(prev.lat, prev.lon, r.lat, r.lon) / dt * 3.6
                     if prev and dt > 0 else (out[-1].speed if out else 0.0))
        if stops:
            snap = snap_to_route(r.lat, r.lon, line)
            near_m, near = min(((haversine_m(r.lat, r.lon, s.lat, s.lon), s) for s in stops),
                               key=lambda d: d[0])
            out.append(_Point(r, speed, snap.stretch if snap else None,
                              near.seq if near_m <= near.radius_m else None, near_m))
        else:
            out.append(_Point(r, speed, None, None, float("inf")))
        prev = r
    return out


def _runs(points: list[_Point], test, gap_s: int) -> list[tuple[list[_Point], _Point | None]]:
    """Maximal runs of consecutive points passing `test`, each with the
    point that ended it (None when the readings ended or a gap broke it)."""
    runs: list[tuple[list[_Point], _Point | None]] = []
    run: list[_Point] = []
    for p in points:
        joined = run and _seconds(run[-1].r.at, p.r.at) <= gap_s
        if test(p):
            if run and not joined:
                runs.append((run, None))
                run = []
            run.append(p)
        elif run:
            runs.append((run, p if joined else None))
            run = []
    if run:
        runs.append((run, None))
    return runs


def _overspeed(points: list[_Point], limit_of, rules: Rules) -> list[Flag]:
    """Runs above the limit (`limit_of(point)`, None for none) lasting
    `overspeed_s` or more."""
    last_at = points[-1].r.at
    out = []

    def over(p: _Point) -> bool:
        limit = limit_of(p)
        return limit is not None and p.speed > limit

    for run, _ in _runs(points, over, rules.gap_s):
        first, last = run[0], run[-1]
        if _seconds(first.r.at, last.r.at) < rules.overspeed_s:
            continue
        ongoing = last.r.at == last_at
        out.append(Flag(
            "overspeed", first.r.at, None if ongoing else last.r.at, first.r.lat, first.r.lon,
            stretch_no=first.stretch, max_speed_kmh=round(max(p.speed for p in run), 1),
            limit_kmh=limit_of(first), duration_s=round(_seconds(first.r.at, last.r.at)),
        ))
    return out


def rental_flags(readings: Sequence[Reading], limit_kmh: float, rules: Rules) -> list[Flag]:
    """A special trip's flags: overspeed against its one limit (brief 2.5)."""
    if not readings:
        return []
    points = _points(sorted(readings, key=lambda r: r.at), [])
    return _overspeed(points, lambda p: limit_kmh, rules)


def flags(readings: Sequence[Reading], stops: Sequence[Stop],
          stretches: Sequence[Stretch], waits: Sequence[Wait], rules: Rules) -> list[Flag]:
    """Every driving flag in a trip's readings, in time order."""
    if len(stops) < 2 or not readings:
        return []
    points = _points(sorted(readings, key=lambda r: r.at), stops)
    last_at = points[-1].r.at
    by_no = {s.no: s for s in stretches}
    out: list[Flag] = []

    # Overspeed: above the limit of the stretch the van is on.
    out += _overspeed(points, lambda p: by_no[p.stretch].limit_kmh if p.stretch in by_no else None,
                      rules)

    # Stops away from every stop zone.
    for run, ended_by in _runs(points, lambda p: p.speed <= rules.standstill_kmh, rules.gap_s):
        first = run[0]
        if first.zone is not None:
            continue                     # a stop at a stop
        ongoing = ended_by is None and run[-1].r.at == last_at
        end = ended_by.r.at if ended_by else run[-1].r.at
        duration = _seconds(first.r.at, end)
        at_pickup = any(_overlap(first.r.at, end, w.arrived, w.left or end) > 0 for w in waits)
        allowed = sum(_overlap(first.r.at, end, w.arrived,
                               min(w.left or end, w.arrived + timedelta(seconds=rules.pickup_wait_s)))
                      for w in waits)
        counted = duration - allowed
        if counted > rules.stop_s:
            kind = "unscheduled_stop"
        elif at_pickup or ongoing or duration <= 0:
            continue
        else:
            kind = "en_route_stop"
        out.append(Flag(
            kind, first.r.at, None if ongoing else end, first.r.lat, first.r.lon,
            stretch_no=first.stretch, nearest_stop_dist_m=round(first.nearest_m, 2),
            duration_s=round(duration),
        ))

    # Stretch times: the last reading in one stop zone to the first in the next.
    last_in: dict[int, _Point] = {}
    measured: set[int] = set()
    for p in points:
        if p.zone is None:
            continue
        k = p.zone - 1
        stretch = by_no.get(k)
        if k in last_in and k not in measured and stretch is not None and stretch.expected_s > 0:
            left, entered = last_in[k].r.at, p.r.at
            waiting = sum(_overlap(left, entered, w.arrived, w.left or entered) for w in waits)
            actual = _seconds(left, entered) - waiting
            ratio = actual / stretch.expected_s
            measured.add(k)
            if ratio > rules.slow_ratio:
                out.append(Flag(
                    "slow_stretch", left, entered, last_in[k].r.lat, last_in[k].r.lon,
                    stretch_no=k, time_ratio=round(ratio, 2), duration_s=round(actual),
                ))
        last_in[p.zone] = p

    return sorted(out, key=lambda f: f.start)
