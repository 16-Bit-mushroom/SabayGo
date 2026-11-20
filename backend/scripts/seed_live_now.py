#!/usr/bin/env python3
"""Live activity for the console, on top of the alpha data (seed_alpha.py).

    backend/venv/bin/python backend/scripts/seed_live_now.py

Everything goes through the real API in the order the day would: nothing
is written to the database directly, so every screen shows what the server
really holds. It plays, as each role would:

  * an extra departure 20 minutes from now on TST-1023 with Nonoy: three
    app passengers who reserve and are marked Paid, four walk-ins; a phone
    checked out to the van reports a working camera and counts eight
    boardings at the door (one more than the list: the Boarding Audit
    case); the operator disputes the Kidapawan line; the Cashier records
    the fees and the operator's share; the trip starts; Nonoy explains the
    eighth boarding (a porter loading cargo) and departs.
  * a second extra trip on a free van with Mae, let go by the Terminal
    Manager before its fees (a written reason), with no phone aboard:
    Unaudited, for Review Starts.
  * the next departures given a Dispatcher, and a van only where one has
    nothing today (a van on a trip owes its ticket and parking before a
    second); one trip keeps no van, with two paid reservations, so the
    sheet shows fees due and an empty van cell.

Then it leaves two helpers running in the background, so the Overview and
the van board stay live: the GPS replay (tracking_simulator.py) for the
trip on the road, and the phone's status reports every 30 s (`heartbeat`
below). Their logs are in logs/. Stop them with:  pkill -f seed_live_now ;
pkill -f tracking_simulator

This is test data for the alpha, played by the script: the camera count
and positions come from the script, not from a van.
"""

from __future__ import annotations

import datetime as dt
import json
import math
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid

API = os.environ.get("SABAYGO_API", "http://127.0.0.1:8000/api/v1")
ROOT = pathlib.Path(__file__).resolve().parents[2]
PHONE = "realme 8 5G (live data)"  # the model name this script's simulated phones carry
_tok: dict[str, str] = {}


def call(method, path, body=None, who=None, device=None):
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Content-Type", "application/json")
    if who:
        req.add_header("Authorization", "Bearer " + login(who))
    if device:
        req.add_header("X-Device-Token", device)
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]


def login(who):
    if who not in _tok:
        s, b = call("POST", "/auth/login", {"email": f"{who}@a2z.dev", "password": "sabaygo123"})
        if s != 200:
            raise SystemExit(f"cannot sign in as {who}@a2z.dev: {b}")
        _tok[who] = b["access_token"]
    return _tok[who]


def step(ok, what, detail=""):
    print(f"  {'done ' if ok else 'FAIL '} {what}{'' if ok or not detail else ' -- ' + str(detail)}")
    return ok


def now_iso(seconds=0):
    return (dt.datetime.now() + dt.timedelta(seconds=seconds)).isoformat(timespec="seconds")


def heartbeat(token: str):
    """The phone's status reports every 30 s: camera working, lens clear,
    and the battery, heat and detection rate the real app sends."""
    while True:
        # What the real edge app also reports (CountingService.kt): battery,
        # its temperature, charging on the van's power, and how many frames
        # a second the model checks. Simulated, as the door counts are.
        t = time.time()
        report = {"recorded_at": now_iso(), "camera_ok": True, "gps_ok": True, "lens_blocked": False,
                  "battery_pct": max(20, 92 - int((t / 600) % 60)), "charging": True,
                  "battery_temp_c": round(39.5 + 2.5 * math.sin(t / 420), 1),
                  "detection_rate_hz": round(8.2 + 0.9 * math.sin(t / 180), 2)}
        try:
            s, b = call("POST", "/edge/heartbeats", {"reports": [report]}, device=token)
        except urllib.error.URLError as e:
            # The backend restarting (./run.sh again) is not the phone
            # going away: try again next round, as a real phone would.
            print(f"{now_iso()} backend unreachable ({e.reason}); retrying in 30 s", flush=True)
            time.sleep(30)
            continue
        print(f"{now_iso()} heartbeat {s}", flush=True)
        if s in (401, 403, 404):
            print(f"stopping: {b}", flush=True)
            return
        time.sleep(30)


def background(name, args):
    log = ROOT / "logs" / f"{name}.log"
    with open(log, "ab") as out:
        subprocess.Popen(args, cwd=ROOT / "backend", stdout=out, stderr=subprocess.STDOUT,
                         stdin=subprocess.DEVNULL, start_new_session=True)
    print(f"  running {name} in the background (logs/{name}.log)")


def left_unpaid(route, vans, crew):
    """A second extra trip the Terminal Manager lets leave before its fees
    are recorded: the block is lifted with a written reason, the trip reads
    'overridden', and the van's ticket and parking stay owing on the Van
    Status Board. It runs on a van with nothing else today (a trip this
    early is still on the road at 05:30), and carries no in-van phone (A2Z
    has one), so it is Unaudited -- the case Review Starts lists -- never
    counted as zero."""
    today = call("GET", f"/config/trips?date={dt.date.today().isoformat()}", who="manager")[1]
    plate = next((p for p in ("ABC-1234", "LCT-9042")
                  if vans.get(p) and all(r["van_id"] != vans[p] for r in today)), None)
    if not step(plate is not None, "a van with nothing else today", "every van is on a trip today"):
        return
    print(f"A trip let go before its fees: {plate} with Mae")
    leaves = (dt.datetime.now() + dt.timedelta(minutes=15)).replace(second=0, microsecond=0)
    s, t = call("POST", "/config/trips/special", {
        "route_id": route["route_id"], "departure_datetime": leaves.isoformat(),
        "dispatcher_id": crew["mae"], "trip_label": "Extra trip (paid later)"}, "manager")
    if not step(s == 201, f"extra departure at {leaves:%I:%M %p} posted with Mae", t):
        return
    trip = t["trip_id"]
    s, b = call("POST", f"/trips/{trip}/payment-override", {
        "note": "Operator short of cash at the window; pays the ticket and parking on return. Let the van go."},
        "manager")
    step(s == 200, "the Terminal Manager lifts the payment block, with the reason written", b)
    s, b = call("PUT", f"/trips/{trip}/assignment", {"van_id": vans[plate], "dispatcher_id": crew["mae"]},
                "manager")
    step(s == 200, f"{plate} assigned", b)
    walk = [call("POST", "/bookings/walk-in", {"trip_id": trip, "boarding_stop": 1, "alighting_stop": stop}, "mae")[0]
            for stop in (2, 2, 4)]
    step(walk == [201] * 3, "three walk-ins listed (two to Digos, one to Cotabato)", walk)
    s, b = call("POST", f"/trips/{trip}/start", None, "joy")
    step(s == 200, "the Cashier starts it", b)
    s, b = call("POST", f"/trips/{trip}/depart", None, "mae")
    step(s == 200, "Mae departs: fees still owing, and no phone counted it (Unaudited)", b)


def main():
    route = next(r for r in call("GET", "/config/routes", who="manager")[1] if r["is_active"])
    vans = {v["plate_number"]: v["van_id"] for v in call("GET", "/fleet/vans", who="manager")[1]}
    crew = {c["email"].split("@")[0]: c["user_id"] for c in call("GET", "/fleet/crew", who="manager")[1]}

    print("A trip on the road: TST-1023 with Nonoy")
    leaves = (dt.datetime.now() + dt.timedelta(minutes=20)).replace(second=0, microsecond=0)
    s, t = call("POST", "/config/trips/special", {
        "route_id": route["route_id"], "departure_datetime": leaves.isoformat(),
        "van_id": vans["TST-1023"], "dispatcher_id": crew["nonoy"], "trip_label": "Extra trip"}, "manager")
    if not step(s == 201, f"extra departure at {leaves:%I:%M %p} posted, van and Dispatcher assigned", t):
        return
    trip = t["trip_id"]
    for who, stop in (("andrea.villamor", 4), ("rogelio.tan", 3), ("grace.dumaguing", 2)):
        s, b = call("POST", "/bookings/reserve", {"trip_id": trip, "boarding_stop": 1, "alighting_stop": stop}, who)
        ok = s == 201 and call("POST", f"/bookings/{b['booking_id']}/mark-paid", {}, "nonoy")[0] == 200
        step(ok, f"{who} reserves to stop {stop} and pays Nonoy", b)
    walk = [call("POST", "/bookings/walk-in", {"trip_id": trip, "boarding_stop": 1, "alighting_stop": stop}, "nonoy")[0]
            for stop in (4, 4, 3, 2)]
    step(walk == [201] * 4, "four walk-ins listed (two to Cotabato, one each to Kidapawan and Digos)", walk)

    # A van carries one phone at a time, so a phone an earlier run left on
    # TST-1023 is recorded back in the office first; otherwise the checkout
    # is refused and the trip runs with no camera (20 Nov). Only this
    # script's own simulated phones: a real one stays where it is, and the
    # refusal below then says why.
    for d in call("GET", "/devices", who="manager")[1]:
        if d["device_model"] == PHONE and (d.get("checkout") or {}).get("van_id") == vans["TST-1023"]:
            s, b = call("POST", f"/devices/{d['device_id']}/return",
                        {"return_note": "Returned by seed_live_now.py before a new run."}, "joy")
            step(s == 200, "the phone an earlier run left on TST-1023 recorded back in the office", b)
    s, dev = call("POST", "/devices", {"device_model": PHONE}, "manager")
    s, out = (call("POST", f"/devices/{dev['device_id']}/checkout",
                   {"van_id": vans["TST-1023"], "dispatcher_id": crew["nonoy"]}, "joy")
              if s == 201 else (s, dev))
    ok = s == 200
    step(ok, "a phone added and checked out to TST-1023 and Nonoy", out)
    token = dev["device_token"] if ok else None
    if token:
        time.sleep(1)
        s, _ = call("POST", "/edge/heartbeats", {"reports": [
            {"recorded_at": now_iso(), "camera_ok": True, "gps_ok": True, "lens_blocked": False}]}, device=token)
        step(s == 200, "the phone reports: camera working, lens clear")
        events = [{"event_id": str(uuid.uuid4()), "event_type": "board", "event_at": now_iso(i)} for i in range(1, 9)]
        time.sleep(9)
        s, _ = call("POST", "/edge/events", {"events": events}, device=token)
        step(s == 200, "the door camera counts eight boardings: one more than the seven listed")

    s, share = call("GET", f"/trips/{trip}/share", who="joy")
    kid = next((l for l in share["lines"] if l["dest_terminal_name"].startswith("Kidapawan")
                and l["income_group"] == "walk_in"), None) if s == 200 else None
    if kid:
        s, _ = call("POST", "/disputes", {"subject": "fare_line", "line_id": kid["line_id"],
                                          "operator_statement": "The Kidapawan walk-in got off at Digos."}, "joy")
        step(s == 201, "the operator disputes the Kidapawan walk-in line (the Cashier records it)")
    s, share = call("GET", f"/trips/{trip}/share", who="joy")
    left = float(share["operator_share_owed"]) - float(share.get("operator_share_held", share["operator_share_given"]))
    s, _ = call("POST", f"/trips/{trip}/payment", {"amount": share["amount_due"], "reference": "0012301",
                                                   "operator_share": f"{max(left, 0):.2f}"}, "joy")
    step(s == 200, f"the Cashier records ₱{share['amount_due']} of terminal fees and the operator's share")
    s, b = call("POST", f"/trips/{trip}/start", None, "joy")
    step(s == 200, "the Cashier starts the trip", b)
    # Depart is refused while the camera counts more aboard than listed,
    # until each extra boarding is listed or explained. The eighth was not
    # a passenger; Nonoy types why, and the explanation stays on the record
    # for the Boarding Audit.
    s, chk = call("GET", f"/trips/{trip}/door-check", who="nonoy")
    for u in (chk.get("unlisted", []) if s == 200 else []):
        if u["resolution_status"] == "pending":
            s, b = call("POST", f"/door-events/{u['event_id']}/explain", {
                "note": "The station porter stepped in to load a sack of rice and stepped back out."}, "nonoy")
            step(s == 200, "Nonoy explains the eighth boarding: the station porter, loading cargo", b)
    s, b = call("POST", f"/trips/{trip}/depart", None, "nonoy")
    step(s == 200, "Nonoy departs: the van is on the road", b)

    left_unpaid(route, vans, crew)

    print("Today's next departures")
    # A van already on a trip today owes that trip's DCOTT ticket and the
    # day's parking now, so the server refuses it a second trip until the
    # Cashier records them. The script keeps to the rule: a trip that has a
    # van gets a Dispatcher; a trip without one gets a Dispatcher and stays
    # vanless (the sheet's amber cell), and only a van with nothing today is
    # given a trip.
    board = call("GET", f"/config/trips?date={dt.date.today().isoformat()}", who="manager")[1]
    ahead = sorted((r for r in board if r["status"] == "scheduled" and r["trip_id"] != trip),
                   key=lambda r: r["departure_datetime"])
    busy_vans = {r["van_id"] for r in board if r["van_id"]}
    busy_crew = {r["dispatcher_id"] for r in board if r.get("dispatcher_id")}
    spare_crew = [w for w in ("liza", "jun", "ramon", "mae") if crew.get(w) and crew[w] not in busy_crew]
    riders = [("chris", 4), ("paolo.reyes", 2)]
    for r in ahead[:3]:
        if r.get("dispatcher_id") or not spare_crew:
            continue
        who = spare_crew.pop(0)
        # The assignment is replaced as a whole: leaving van_id out would
        # take the van off the trip, so a trip's own van is sent back.
        body = {"dispatcher_id": crew[who], "van_id": r["van_id"]}
        spare_van = next((p for p in ("ABC-1234", "LCT-9042") if vans.get(p) and vans[p] not in busy_vans), None)
        if r["van_id"] is None and spare_van:
            body["van_id"] = vans[spare_van]
            busy_vans.add(vans[spare_van])
        s, b = call("PUT", f"/trips/{r['trip_id']}/assignment", body, "manager")
        plate = r.get("plate_number") or (spare_van if body["van_id"] else "no van yet")
        step(s == 200, f"{r['departure_datetime'][11:16]} trip: {plate}, Dispatcher {who.title()}", b)
        if s == 200 and riders and body["van_id"] is None:
            for pax, stop in riders:
                s, bk = call("POST", "/bookings/reserve", {"trip_id": r["trip_id"], "boarding_stop": 1,
                                                           "alighting_stop": stop}, pax)
                ok = s == 201 and call("POST", f"/bookings/{bk['booking_id']}/mark-paid", {}, who)[0] == 200
                step(ok, f"  {pax} reserves and pays {who.title()}", bk)
            riders = []


    print("Keeping it live")
    py = str(ROOT / "backend" / "venv" / "bin" / "python")
    background(f"gps_{trip}", [py, "-u", "scripts/tracking_simulator.py", "--trip", trip, "--loop", "--speed", "4"])
    if token:
        background("phone_live", [py, "-u", "scripts/seed_live_now.py", "heartbeat", token])


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "heartbeat":
        heartbeat(sys.argv[2])
    else:
        main()
