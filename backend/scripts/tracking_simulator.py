#!/usr/bin/env python3
"""GPS replay simulator — drives a virtual van along a real route.

The in-vehicle tracking unit is a GPS dongle on the edge computer. Until
that hardware exists, this script produces the same position reports by
interpolating between the route's terminal coordinates and posting to the
same endpoint.

This is not a stand-in for the API — the requests are real HTTP, the
server does real map matching, and the database stores real rows. Only
the source of the coordinates is simulated.

Worth keeping after the hardware arrives: a demo that depends on a van
physically driving between Davao and Cotabato is not a demo you can run
in a defence room.

    python tracking_simulator.py --trip TRIP-DEMO-00000001
    python tracking_simulator.py --trip ... --speed 20   (20x faster)
    python tracking_simulator.py --trip ... --jitter 30  (30m GPS noise)
"""

from __future__ import annotations

import argparse
import math
import pathlib
import os
import random
import sys
import time
from datetime import datetime, timezone

import httpx

API = os.getenv("SABAYGO_API", "http://127.0.0.1:8000/api/v1")
TRACKER_KEY = os.getenv("TRACKER_API_KEY", "")

EARTH_RADIUS_M = 6_371_000.0


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def bearing_deg(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def jitter(lat: float, lng: float, metres: float) -> tuple[float, float]:
    """Scatter a point within `metres` — consumer GPS is never exact.

    Without this the track is a perfect straight line, which would let a
    map-matching bug pass unnoticed until real hardware arrives.
    """
    if metres <= 0:
        return lat, lng
    angle = random.uniform(0, 2 * math.pi)
    dist = random.uniform(0, metres)
    dlat = (dist * math.cos(angle)) / 111_320
    dlng = (dist * math.sin(angle)) / (111_320 * math.cos(math.radians(lat)))
    return lat + dlat, lng + dlng


def fetch_route(client: httpx.Client, trip_id: str) -> list[dict]:
    r = client.get(f"{API}/trips/{trip_id}/stops")
    r.raise_for_status()
    stops = r.json()
    if len(stops) < 2:
        sys.exit("Route has fewer than two stops; nothing to drive along.")
    return stops


def stop_coordinates(client: httpx.Client, stops: list[dict]) -> list[dict]:
    """Read terminal coordinates directly from MySQL.

    The public terminals endpoint deliberately omits latitude and
    longitude -- a passenger picker does not need them, and publishing
    precise geofence centres invites spoofing. The simulator stands in
    for hardware that would have its own GPS, so it reads them from the
    database instead of widening the API.
    """
    import subprocess

    ids = ",".join(f"'{s['terminal_id']}'" for s in stops)
    sql = (
        "SELECT terminal_id, terminal_name, latitude, longitude "
        f"FROM terminals WHERE terminal_id IN ({ids});"
    )
    pw = os.getenv("MYSQL_ROOT_PASSWORD", "sabaygo_root_dev")
    out = subprocess.run(
        ["docker", "compose", "exec", "-T", "-e", f"MYSQL_PWD={pw}",
         "mysql", "mysql", "-u", "root", "--silent", "sabaygo", "-e", sql],
        capture_output=True, text=True, cwd=str(pathlib.Path(__file__).resolve().parents[2]),
    )
    if out.returncode != 0:
        sys.exit(f"Could not read terminal coordinates:\n{out.stderr}")

    coords = {}
    for line in out.stdout.strip().splitlines():
        tid, name, lat, lng = line.split("\t")
        coords[tid] = (name, float(lat), float(lng))

    result = []
    for s in stops:
        if s["terminal_id"] not in coords:
            sys.exit(f"Terminal {s['terminal_id']} has no coordinates.")
        name, lat, lng = coords[s["terminal_id"]]
        result.append({"sequence": s["stop_sequence"], "name": name,
                       "lat": lat, "lng": lng})
    return result


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--trip", required=True)
    ap.add_argument("--interval", type=float, default=10.0,
                    help="Seconds between reports, as a real unit would send")
    ap.add_argument("--speed", type=float, default=1.0,
                    help="Playback multiplier. 20 covers a 5h route in 15 min")
    ap.add_argument("--kph", type=float, default=45.0, help="Simulated road speed")
    ap.add_argument("--jitter", type=float, default=15.0, help="GPS noise, metres")
    ap.add_argument("--loop", action="store_true", help="Restart on arrival")
    args = ap.parse_args()

    headers = {"X-Tracker-Key": TRACKER_KEY} if TRACKER_KEY else {}

    with httpx.Client(timeout=15.0) as client:
        stops = stop_coordinates(client, fetch_route(client, args.trip))

        print(f"Route: {' -> '.join(s['name'] for s in stops)}")
        total_km = sum(
            haversine_m(a["lat"], a["lng"], b["lat"], b["lng"])
            for a, b in zip(stops, stops[1:])
        ) / 1000
        print(f"Distance: {total_km:.1f} km at {args.kph} km/h "
              f"({total_km / args.kph * 60:.0f} min real, "
              f"{total_km / args.kph * 60 / args.speed:.1f} min at {args.speed}x)")
        print(f"Reporting every {args.interval}s, {args.jitter}m jitter\n")

        while True:
            for a, b in zip(stops, stops[1:]):
                leg_m = haversine_m(a["lat"], a["lng"], b["lat"], b["lng"])
                heading = bearing_deg(a["lat"], a["lng"], b["lat"], b["lng"])
                # Ground covered between reports, at the simulated speed.
                step_m = (args.kph * 1000 / 3600) * args.interval * args.speed
                steps = max(int(leg_m / step_m), 1)

                print(f"-- {a['name']} -> {b['name']}  "
                      f"({leg_m / 1000:.1f} km, {steps} reports)")

                for i in range(steps + 1):
                    frac = i / steps
                    lat = a["lat"] + (b["lat"] - a["lat"]) * frac
                    lng = a["lng"] + (b["lng"] - a["lng"]) * frac
                    jlat, jlng = jitter(lat, lng, args.jitter)

                    try:
                        r = client.post(
                            f"{API}/tracking/trips/{args.trip}/ping",
                            headers=headers,
                            json={
                                "latitude": round(jlat, 6),
                                "longitude": round(jlng, 6),
                                "accuracy_m": round(random.uniform(4, 12), 1),
                                "speed_kph": round(
                                    args.kph + random.uniform(-6, 6), 1
                                ),
                                "heading_deg": round(heading, 1),
                                "recorded_at": datetime.now(timezone.utc).isoformat(),
                            },
                        )
                    except httpx.RequestError as exc:
                        print(f"   ! unreachable: {exc}")
                        time.sleep(args.interval)
                        continue

                    if r.status_code == 201:
                        d = r.json()
                        near = d.get("nearest_stop_sequence")
                        dist = d.get("distance_to_stop_m") or 0
                        print(f"   {jlat:.5f},{jlng:.5f}  "
                              f"nearest stop {near} ({dist / 1000:.1f} km)")
                    elif r.status_code == 409:
                        sys.exit(f"   ! {r.json().get('detail')}\n"
                                 "     Set the trip to boarding or departed first.")
                    else:
                        print(f"   ! {r.status_code} {r.text[:120]}")

                    time.sleep(args.interval / args.speed)

            print("\nArrived at the final stop.")
            if not args.loop:
                return
            print("Restarting.\n")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nStopped.")