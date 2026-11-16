#!/usr/bin/env python3
"""NAHGM benchmark: how right the map matching and ETAs are, and how fast
positions are taken in.

Two parts, written to docs/benchmarks/nahgm_<stamp>.txt (+ .csv):

**Accuracy** (no server, no database). A van is driven, second by second,
along the *real road* of the pilot route ECO-COT -- Ecoland, Digos,
Kidapawan, Cotabato -- taken from OpenStreetMap through OSRM and kept in
`docs/benchmarks/nahgm_route_eco_cot_osrm.json`, so the run is repeatable
offline. Speeds follow OSRM's free-flow time for each stretch of road
(times 0.85 for a loaded van, never over 80 km/h), with traffic stops in
the cities and a five-minute dwell at Digos and at Kidapawan. That drive
is the ground truth: where the van is, and when it really reaches each
stop.

From it, the phone's 1 Hz fixes are made with GPS error (0, 5, 15, 30 m
per axis), lost fixes (none, 10 %, 30 %, the last two with a three-minute
dead zone) and with or without the receiver's speed. Every fix goes
through NAHGM's own code -- `TrackingService._match_to_node` at ingest,
then, every 15 s, `_estimate_speed` over the last five fixes and
`_compute_etas` from the nearest stop, exactly as `current_position`
does -- and each ETA is compared with the true arrival.

Only the glue of `current_position` (take the newest five fixes; ETAs from
the newest fix's nearest stop; `now` is that fix's time) is repeated here,
not the arithmetic, so a change to NAHGM is measured by re-running this.

What this is not: a real drive. No van has yet reported a real trail
(every stored point came from the simulator), and OSRM's free-flow times
are not Davao traffic. It measures the method's error sources that do not
depend on traffic -- straight-line distance against road distance, the
nearest-stop rule, speed from five fixes, GPS error and gaps -- and says
so in the report.

**Speed** (needs a backend and the *scratch* database). Positions are
posted to `POST /tracking/trips/{id}/ping` (development only; it runs the
same `record_ping` as the phone's `/edge/fixes`, plus the driving-flag
review) by N vans at once, one fix per second each, N rising until the
95th-percentile answer is slower than one second or requests fail. The
phone uploads in batches, so one request per fix is the worst case.

    cd backend
    venv/bin/python scripts/nahgm_benchmark.py --accuracy-only
    DATABASE_URL=...sabaygo_t venv/bin/python scripts/nahgm_benchmark.py \\
        --api http://127.0.0.1:8001/api/v1
"""

from __future__ import annotations

import argparse
import asyncio
import csv
import math
import os
import platform
import random
import statistics
import sys
import time
import timeit
from collections import deque
from dataclasses import dataclass
from datetime import datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.dirname(HERE)
REPO = os.path.dirname(BACKEND)
sys.path.insert(0, BACKEND)

from app.application.tracking.geometry import haversine_m  # noqa: E402
from app.application.tracking.nahgm import (  # noqa: E402
    MIN_MOVING_KPH,
    SPEED_WINDOW,
    TrackingService,
)

ROUTE_FILE = os.path.join(REPO, "docs", "benchmarks", "nahgm_route_eco_cot_osrm.json")
BENCHMARKS = os.path.join(REPO, "docs", "benchmarks")

# ECO-COT as A2Z's Day 1 setup holds it (db/day1/day1_a2z.sql). The
# offsets were test values on Day 1; they matter only when no speed is
# reported (the schedule's pace is then the fallback).
STOPS = [
    (1, "Ecoland", 7.051048, 125.587456, 0),
    (2, "Digos", 6.738249, 125.365530, 90),
    (3, "Kidapawan", 7.008300, 125.089700, 195),
    (4, "Cotabato", 7.221700, 124.246700, 300),
]
STALE_AFTER_S = 120          # tracking_stale_after_seconds (migration seed)
EVAL_EVERY_S = 15
VAN_FACTOR = 0.85            # a loaded van against OSRM's free-flow car
MAX_KPH = 80.0
DWELL_S = 300                # at Digos and Kidapawan
# Traffic stops: (metres along the route, seconds stopped).
TRAFFIC_STOPS = [(2_000, 75), (4_500, 60), (7_500, 90), (51_000, 60),
                 (106_000, 60), (225_000, 75)]
DEAD_ZONE = (150_000, 180)   # metres along, seconds without a fix
NOISE_M = [0, 5, 15, 30]
DROPOUT = [0.0, 0.1, 0.3]
SEED = 20261116


# --------------------------------------------------------------------------
# Stand-ins for the rows NAHGM reads. Its functions take attributes, not
# ORM types, so plain objects carry exactly the fields it uses.
# --------------------------------------------------------------------------
@dataclass
class _Stop:
    stop_sequence: int
    offset_minutes: int


@dataclass
class _Terminal:
    terminal_id: str
    terminal_name: str
    latitude: float
    longitude: float


@dataclass
class _Fix:
    t: float
    latitude: float
    longitude: float
    speed_kph: float | None
    nearest_seq: int | None


ROUTE = [(_Stop(seq, off), _Terminal(f"T{seq}", name, lat, lon))
         for seq, name, lat, lon, off in STOPS]


# --------------------------------------------------------------------------
# The true drive
# --------------------------------------------------------------------------
@dataclass
class Truth:
    samples: list[tuple[float, float, float, float, float]]  # t, lat, lon, kph, along_m
    arrival: dict[int, float]     # stop -> seconds after leaving Ecoland
    leg_road_m: list[float]
    leg_straight_m: list[float]


def drive() -> Truth:
    import json
    data = json.load(open(ROUTE_FILE))
    coords = [(lat, lon) for lon, lat in data["coordinates_lonlat"]]
    seg_d, seg_u, leg_end_index = [], [], []
    for leg in data["legs"]:
        seg_d += leg["segment_distance_m"]
        seg_u += leg["segment_duration_s"]
        leg_end_index.append(len(seg_d))          # point index at the leg's end

    # Events along the road: traffic stops and the dwell at stops 2 and 3.
    along_at = [0.0]
    for d in seg_d:
        along_at.append(along_at[-1] + d)
    stops_at = {i: s for i, s in TRAFFIC_STOPS}

    samples, arrival = [], {1: 0.0}
    t, next_sample = 0.0, 0.0
    pending_traffic = sorted(TRAFFIC_STOPS)
    for i, (d, u) in enumerate(zip(seg_d, seg_u)):
        if d <= 0:
            continue
        ff = d / u * 3.6 if u > 0 else MAX_KPH
        kph = max(5.0, min(MAX_KPH, ff * VAN_FACTOR))
        dur = d / (kph / 3.6)
        (alat, alon), (blat, blon) = coords[i], coords[i + 1]
        # sample every whole second inside this segment
        while next_sample < t + dur:
            f = (next_sample - t) / dur
            samples.append((next_sample, alat + f * (blat - alat), alon + f * (blon - alon),
                            kph, along_at[i] + f * d))
            next_sample += 1.0
        t += dur
        # a traffic stop that falls in this segment
        while pending_traffic and pending_traffic[0][0] <= along_at[i + 1]:
            _, secs = pending_traffic.pop(0)
            end = t + secs
            while next_sample < end:
                samples.append((next_sample, blat, blon, 0.0, along_at[i + 1]))
                next_sample += 1.0
            t = end
        # the end of a leg: arrival, then the dwell (not at the last stop)
        if i + 1 in leg_end_index:
            k = leg_end_index.index(i + 1) + 2      # stop number reached
            arrival[k] = t
            if k < len(STOPS):
                end = t + DWELL_S
                while next_sample < end:
                    samples.append((next_sample, blat, blon, 0.0, along_at[i + 1]))
                    next_sample += 1.0
                t = end
    del stops_at

    road = [leg["distance_m"] for leg in data["legs"]]
    straight = [haversine_m(a[2], a[3], b[2], b[3]) for a, b in zip(STOPS, STOPS[1:])]
    return Truth(samples, arrival, road, straight)


# --------------------------------------------------------------------------
# One scenario through NAHGM's own code
# --------------------------------------------------------------------------
M_PER_DEG_LAT = 110_574.0


def _jitter(lat: float, lon: float, sigma: float, rng: random.Random) -> tuple[float, float]:
    if sigma <= 0:
        return lat, lon
    dlat = rng.gauss(0, sigma) / M_PER_DEG_LAT
    dlon = rng.gauss(0, sigma) / (111_320.0 * math.cos(math.radians(lat)))
    return lat + dlat, lon + dlon


def horizon_band(minutes: float) -> str:
    for hi, name in ((15, "0-15 min"), (30, "15-30 min"), (60, "30-60 min"),
                     (120, "60-120 min")):
        if minutes < hi:
            return name
    return "120+ min"


BANDS = ["0-15 min", "15-30 min", "30-60 min", "60-120 min", "120+ min"]


async def scenario(truth: Truth, noise: float, dropout: float, with_speed: bool) -> dict:
    rng = random.Random(f"{SEED}-{noise}-{dropout}-{with_speed}")
    svc = TrackingService.__new__(TrackingService)     # _compute_etas reads no session
    t0 = datetime(2026, 11, 16, 5, 30)
    final = truth.arrival[len(STOPS)]
    dead_from = dead_to = None
    if dropout > 0:
        # the dead zone: first sample past DEAD_ZONE's distance
        for t, *_rest, along in truth.samples:
            if along >= DEAD_ZONE[0]:
                dead_from, dead_to = t, t + DEAD_ZONE[1]
                break

    window: deque[_Fix] = deque(maxlen=SPEED_WINDOW)
    pairs = []            # (band, err_min or None, remaining_min)
    instants = matched_next = matched_prev = matched_other = 0
    next_missing = stale = 0
    drop_lead: dict[int, float] = {}      # stop -> minutes before arrival it left the list
    next_eval = 0.0

    for t, lat, lon, kph, _along in truth.samples:
        if t >= final:
            break
        lost = (rng.random() < dropout) or (dead_from is not None and dead_from <= t < dead_to)
        if not lost:
            glat, glon = _jitter(lat, lon, noise, rng)
            spd = max(0.0, kph + rng.gauss(0, 1.5)) if with_speed else None
            seq, _ = TrackingService._match_to_node(glat, glon, ROUTE)
            window.append(_Fix(t, glat, glon, spd, seq))
        if t < next_eval or not window:
            continue
        next_eval = t + EVAL_EVERY_S

        latest = window[-1]
        instants += 1
        if t - latest.t > STALE_AFTER_S:
            stale += 1            # the app shows the fix as old; not scored
            continue
        true_next = next(k for k in range(2, len(STOPS) + 1) if truth.arrival[k] > t)
        nearest = latest.nearest_seq or 1
        if nearest == true_next:
            matched_next += 1
        elif nearest == true_next - 1:
            matched_prev += 1
        else:
            matched_other += 1

        speed = TrackingService._estimate_speed(list(window), None, ROUTE)
        etas = await svc._compute_etas(
            latitude=latest.latitude, longitude=latest.longitude,
            from_sequence=nearest, stops=ROUTE, speed_kph=speed,
            now=t0 + timedelta(seconds=latest.t),
        )
        listed = {e.stop_sequence: e for e in etas}
        if true_next not in listed:
            next_missing += 1
            drop_lead.setdefault(true_next, (truth.arrival[true_next] - t) / 60)
        for k in range(true_next, len(STOPS) + 1):
            remaining = (truth.arrival[k] - t) / 60
            e = listed.get(k)
            if e is None or e.eta is None:
                pairs.append((horizon_band(remaining), None, remaining))
                continue
            err = ((e.eta - t0).total_seconds() - truth.arrival[k]) / 60
            pairs.append((horizon_band(remaining), err, remaining))

    return {
        "noise_m": noise, "dropout": dropout, "speed": "reported" if with_speed else "absent",
        "instants": instants, "stale": stale,
        "matched_next": matched_next, "matched_prev": matched_prev, "matched_other": matched_other,
        "next_missing": next_missing, "drop_lead": drop_lead, "pairs": pairs,
    }


def summarise(pairs: list[tuple[str, float | None, float]]) -> dict:
    errs = [e for _, e, _ in pairs if e is not None]
    rel = [abs(e) / r for _, e, r in pairs if e is not None and r > 0]
    if not errs:
        return {"n": len(pairs), "avail": 0.0}
    abs_e = sorted(abs(e) for e in errs)
    return {
        "n": len(pairs),
        "avail": len(errs) / len(pairs) * 100,
        "mae": statistics.fmean(abs_e),
        "bias": statistics.median(errs),
        "p90": abs_e[int(0.9 * (len(abs_e) - 1))],
        "within5": sum(a <= 5 for a in abs_e) / len(abs_e) * 100,
        "within10pct": sum(r <= 0.10 for r in rel) / len(rel) * 100,
    }


# --------------------------------------------------------------------------
# Speed
# --------------------------------------------------------------------------
def micro_timings() -> list[str]:
    lat, lon = 7.0, 125.4
    n = 200_000
    match = timeit.timeit(lambda: TrackingService._match_to_node(lat, lon, ROUTE), number=n)
    svc = TrackingService.__new__(TrackingService)
    now = datetime(2026, 11, 16, 6, 0)

    def etas():
        coro = svc._compute_etas(latitude=lat, longitude=lon, from_sequence=1,
                                 stops=ROUTE, speed_kph=60.0, now=now)
        try:
            coro.send(None)
        except StopIteration:
            pass
    m = 50_000
    eta = timeit.timeit(etas, number=m)
    return [
        f"map matching (nearest of 4 stops)  : {match / n * 1e6:7.2f} us per fix",
        f"ETAs to the stops ahead            : {eta / m * 1e6:7.2f} us per call",
        "Pure Python, one core. Both grow with the number of stops (a route",
        "has a handful), so the arithmetic is never the bottleneck: the",
        "database write and the request are (below).",
    ]


async def _sql(stmt: str, params: dict | None = None):
    from sqlalchemy import text
    from app.core.db import engine
    async with engine.begin() as c:
        r = await c.execute(text(stmt), params or {})
        return r.fetchall() if r.returns_rows else None


async def make_trips(n: int, source: str) -> list[str]:
    cols = [r[0] for r in await _sql(
        "SELECT column_name FROM information_schema.columns WHERE table_schema = DATABASE() "
        "AND table_name = 'trips' ORDER BY ordinal_position")]
    ids = []
    for i in range(n):
        tid = f"BENCH-{i:04d}-{int(time.time())}"
        sel = ", ".join(":tid" if c == "trip_id" else f"`{c}`" for c in cols)
        await _sql(f"INSERT INTO trips ({', '.join(f'`{c}`' for c in cols)}) "
                   f"SELECT {sel} FROM trips WHERE trip_id = :src", {"tid": tid, "src": source})
        ids.append(tid)
    return ids


async def load_step(api: str, trips: list[str], seconds: int) -> dict:
    import httpx
    lat, lon = 6.90, 125.47       # between Ecoland and Digos
    lat_ms, codes = [], {}

    async def van(client, tid, k):
        start = time.perf_counter() + (k % 1000) / 1000   # spread the first second
        for s in range(seconds):
            wait = start + s - time.perf_counter()
            if wait > 0:
                await asyncio.sleep(wait)
            body = {"latitude": lat + s * 1e-4, "longitude": lon + s * 1e-4,
                    "speed_kph": 55.0, "accuracy_m": 8.0}
            t = time.perf_counter()
            try:
                r = await client.post(f"{api}/tracking/trips/{tid}/ping", json=body)
                codes[r.status_code] = codes.get(r.status_code, 0) + 1
            except Exception as exc:  # timeouts, refused connections
                codes[type(exc).__name__] = codes.get(type(exc).__name__, 0) + 1
            lat_ms.append((time.perf_counter() - t) * 1000)

    limits = httpx.Limits(max_connections=len(trips) + 10, max_keepalive_connections=len(trips) + 10)
    async with httpx.AsyncClient(timeout=10, limits=limits) as client:
        t0 = time.perf_counter()
        await asyncio.gather(*(van(client, tid, k) for k, tid in enumerate(trips)))
        wall = time.perf_counter() - t0
    lat_ms.sort()
    q = lambda p: lat_ms[min(len(lat_ms) - 1, int(p * (len(lat_ms) - 1)))]  # noqa: E731
    ok = codes.get(201, 0)
    return {"vans": len(trips), "sent": len(lat_ms), "ok": ok, "errors": len(lat_ms) - ok,
            "codes": codes, "rate": ok / wall, "p50": q(0.50), "p95": q(0.95),
            "p99": q(0.99), "max": lat_ms[-1]}


async def speed_part(api: str, source: str, steps: list[int], seconds: int) -> list[str]:
    import httpx
    url = os.environ.get("DATABASE_URL", "")
    if not url.endswith("/sabaygo_t"):
        return ["SKIPPED: DATABASE_URL must name the scratch database sabaygo_t;",
                "this part writes thousands of positions and extra trips."]
    async with httpx.AsyncClient(timeout=5) as c:
        if (await c.get(api.replace("/api/v1", "/health"))).status_code != 200:
            return [f"SKIPPED: no backend at {api}."]
    trips = await make_trips(max(steps), source)
    out = ["vans  sent     ok  errors  ok/s    p50 ms   p95 ms   p99 ms   max ms"]
    best = None
    for n in steps:
        r = await load_step(api, trips[:n], seconds)
        out.append(f"{r['vans']:>4} {r['sent']:>6} {r['ok']:>6} {r['errors']:>7} {r['rate']:>6.1f}"
                   f"{r['p50']:>9.1f}{r['p95']:>9.1f}{r['p99']:>9.1f}{r['max']:>9.1f}"
                   + ("" if r["errors"] == 0 else f"   {r['codes']}"))
        if r["errors"] == 0 and r["p95"] < 1000:
            best = n
        else:
            break
    out += ["",
            f"Most vans kept at one fix per second with p95 under 1 s and no",
            f"errors: {best if best is not None else 'none of the steps'}"
            f" ({seconds} s per step, one uvicorn worker as ./run.sh starts it,",
            "MySQL in Docker, client and server on the same machine)."]
    await _sql("DELETE FROM trip_location_pings WHERE trip_id LIKE 'BENCH-%'")
    try:
        await _sql("DELETE FROM trips WHERE trip_id LIKE 'BENCH-%'")
    except Exception:
        out.append("(benchmark trips left in the scratch database: rows refer to them)")
    return out


# --------------------------------------------------------------------------
async def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--api", default="http://127.0.0.1:8001/api/v1")
    ap.add_argument("--accuracy-only", action="store_true")
    ap.add_argument("--source-trip", default="TRIP-A2Z-LIVE-DEPART",
                    help="a departed trip in the scratch database to clone")
    ap.add_argument("--steps", default="10,25,50,100,200,300,400,600,800")
    ap.add_argument("--seconds", type=int, default=20)
    args = ap.parse_args()

    truth = drive()
    runs = []
    for noise in NOISE_M:
        for dropout in DROPOUT:
            for with_speed in (True, False):
                runs.append(await scenario(truth, noise, dropout, with_speed))

    L = []
    rule = lambda title: ["", title, "=" * 72]  # noqa: E731
    L += ["=" * 72, "NAHGM BENCHMARK: map matching, ETA and ingest speed", "=" * 72, "",
          f"Date        : {datetime.now():%Y-%m-%d %H:%M}",
          f"Host        : {platform.machine()}, {os.cpu_count()} threads, Python {platform.python_version()}",
          "Route       : ECO-COT, Ecoland - Digos - Kidapawan - Cotabato (Day 1 terminals)",
          "Road        : OSRM over OpenStreetMap, (c) OpenStreetMap contributors, ODbL",
          f"Drive       : {len(truth.samples)} s ({len(truth.samples) / 3600:.2f} h), speed = OSRM free-flow"
          f" x {VAN_FACTOR}, max {MAX_KPH:.0f} km/h,",
          f"              {len(TRAFFIC_STOPS)} traffic stops, {DWELL_S // 60} min dwell at Digos and Kidapawan",
          f"Fixes       : 1 Hz; scored every {EVAL_EVERY_S} s; a fix older than {STALE_AFTER_S} s is"
          " 'stale' (shown as old, not scored)",
          f"Scenarios   : GPS error {NOISE_M} m x lost fixes {[int(d * 100) for d in DROPOUT]} %"
          " x speed reported / absent",
          "              (lost fixes > 0 also has one 3-minute dead zone on the Kidapawan-Cotabato leg)"]

    L += rule("TABLE 1  Straight-line (what NAHGM measures) against road distance")
    L += ["leg                     straight km   road km   road / straight"]
    for i, (s, r) in enumerate(zip(truth.leg_straight_m, truth.leg_road_m)):
        L.append(f"{STOPS[i][1] + ' - ' + STOPS[i + 1][1]:<22}{s / 1000:>12.1f}{r / 1000:>10.1f}{r / s:>14.2f}")
    tot_s, tot_r = sum(truth.leg_straight_m), sum(truth.leg_road_m)
    L.append(f"{'whole route':<22}{tot_s / 1000:>12.1f}{tot_r / 1000:>10.1f}{tot_r / tot_s:>14.2f}")
    L += ["", "NAHGM sums straight hops between stops, so with an accurate speed its",
          "ETA is early by about (road / straight - 1) of the remaining time.",
          "True arrivals: " + ", ".join(f"{STOPS[k - 1][1]} {truth.arrival[k] / 60:.0f} min"
                                        for k in range(2, len(STOPS) + 1))]

    base = next(r for r in runs if r["noise_m"] == 5 and r["dropout"] == 0 and r["speed"] == "reported")
    L += rule("TABLE 2  ETA error by how far ahead the stop is (5 m GPS error, no lost fixes,")
    L[-2] += " speed reported)"
    L += ["error = ETA - true arrival, minutes; negative = says the van comes sooner than it does",
          "", "ahead          pairs  ETA shown    MAE   median   p90 |e|   within 5 min   within 10%"]
    for band in BANDS:
        s = summarise([p for p in base["pairs"] if p[0] == band])
        if s["n"] == 0:
            continue
        if "mae" not in s:
            L.append(f"{band:<13}{s['n']:>7}{s['avail']:>10.1f}%   (no ETA shown)")
            continue
        L.append(f"{band:<13}{s['n']:>7}{s['avail']:>10.1f}%{s['mae']:>8.1f}{s['bias']:>9.1f}"
                 f"{s['p90']:>10.1f}{s['within5']:>13.1f}%{s['within10pct']:>12.1f}%")
    s = summarise(base["pairs"])
    L.append(f"{'all':<13}{s['n']:>7}{s['avail']:>10.1f}%{s['mae']:>8.1f}{s['bias']:>9.1f}"
             f"{s['p90']:>10.1f}{s['within5']:>13.1f}%{s['within10pct']:>12.1f}%")

    L += rule("TABLE 3  Robustness: every scenario, all stops ahead together")
    L += ["GPS m  lost  speed      ETA shown    MAE   median   p90 |e|  within 10%   stale"]
    csv_rows = []
    for r in runs:
        s = summarise(r["pairs"])
        stale = r["stale"] / r["instants"] * 100 if r["instants"] else 0
        L.append(f"{r['noise_m']:>5}{int(r['dropout'] * 100):>5}%  {r['speed']:<9}{s['avail']:>9.1f}%"
                 + (f"{s['mae']:>8.1f}{s['bias']:>9.1f}{s['p90']:>10.1f}{s['within10pct']:>11.1f}%"
                    if "mae" in s else "        -        -         -          -")
                 + f"{stale:>7.1f}%")
        for band in BANDS + ["all"]:
            sb = summarise([p for p in r["pairs"] if band == "all" or p[0] == band])
            csv_rows.append({"noise_m": r["noise_m"], "dropout_pct": int(r["dropout"] * 100),
                             "speed": r["speed"], "band": band, "pairs": sb["n"],
                             "eta_shown_pct": round(sb.get("avail", 0), 2),
                             "mae_min": round(sb["mae"], 2) if "mae" in sb else "",
                             "median_err_min": round(sb["bias"], 2) if "bias" in sb else "",
                             "p90_abs_min": round(sb["p90"], 2) if "p90" in sb else "",
                             "within5_pct": round(sb["within5"], 2) if "within5" in sb else "",
                             "within10pct_pct": round(sb["within10pct"], 2) if "within10pct" in sb else ""})
    L += ["", "'ETA shown' falls when the van is stopped (NAHGM gives no arrival time",
          f"below {MIN_MOVING_KPH:.0f} km/h rather than an absurd one) and when the next stop has",
          "already dropped out of the list (Table 4). Without a reported speed the",
          "schedule's pace is used, which is only as good as the offsets typed in."]

    L += rule("TABLE 4  Map matching: the nearest stop against where the van really is")
    L += ["GPS m  lost  nearest = next stop   = last stop   other   next stop missing from ETAs"]
    for r in runs:
        if r["speed"] != "reported":
            continue
        n = r["instants"] - r["stale"]
        L.append(f"{r['noise_m']:>5}{int(r['dropout'] * 100):>5}%{r['matched_next'] / n * 100:>18.1f}%"
                 f"{r['matched_prev'] / n * 100:>14.1f}%{r['matched_other'] / n * 100:>8.1f}%"
                 f"{r['next_missing'] / n * 100:>18.1f}%")
    lead = base["drop_lead"]
    L += ["", "The next stop leaves the ETA list as soon as it becomes the nearest stop,",
          "which happens once the van is past half the straight-line distance, not",
          "when it arrives. Minutes before the true arrival that it disappeared",
          "(5 m, no lost fixes): " + ", ".join(f"{STOPS[k - 1][1]} {m:.0f} min" for k, m in sorted(lead.items())),
          "In that time the passenger sees the stop after it, or nothing on the",
          "last leg. A progress rule (the stop after the one last passed, e.g.",
          "geometry.snap_to_route, already in the code) would keep it listed."]

    L += rule("TABLE 5  Speed of the arithmetic (in process)")
    L += micro_timings()

    L += rule("TABLE 6  Ingest under load (HTTP, scratch database)")
    if args.accuracy_only:
        L += ["Not run (--accuracy-only)."]
    else:
        L += await speed_part(args.api, args.source_trip,
                              [int(x) for x in args.steps.split(",")], args.seconds)

    L += rule("WHAT THIS DOES NOT MEASURE")
    L += ["- A real drive. No van has reported a real trail yet; every stored point",
          "  came from the simulator. Run this again on the first real trail.",
          "- Davao traffic. OSRM's free-flow times stand in for it; congestion that",
          "  changes speed between fixes would widen the far-ahead errors.",
          "- The phone's own GPS. Its error is modelled as Gaussian; real error is",
          "  biased near buildings and under trees.",
          "- The phone's upload path. /edge/fixes batches fixes; Table 6 posts one",
          "  request per fix, the worst case."]

    report = "\n".join(L) + "\n"
    stamp = datetime.now().strftime("%Y-%m-%d_%H%M")
    os.makedirs(BENCHMARKS, exist_ok=True)
    txt = os.path.join(BENCHMARKS, f"nahgm_{stamp}.txt")
    csv_path = os.path.join(BENCHMARKS, f"nahgm_{stamp}.csv")
    open(txt, "w", encoding="utf-8").write(report)
    with open(csv_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(csv_rows[0]))
        w.writeheader()
        w.writerows(csv_rows)
    print(report)
    print(f"summary -> {os.path.relpath(txt, REPO)}\nrows    -> {os.path.relpath(csv_path, REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
