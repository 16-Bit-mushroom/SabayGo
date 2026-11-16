#!/usr/bin/env python3
"""Fresh test data for the alpha, on top of A2Z's Day 1 setup.

    ./db/load-day1.sh && backend/venv/bin/python backend/scripts/seed_alpha.py

Everything goes through the API, as the office would type it, so each
record passes the same checks a person's would. It adds:

  fares     A2Z's trip ticket Nº 0012223: Digos ₱150, Kidapawan ₱340,
            Cotabato ₱363, from today (Day 1 had ₱135 and ₱500)
  van       TST-1023 with its operator Arnel Bautista, validated
  staff     Dispatchers Nonoy, Jun and Mae (validated, with Ramon and
            Liza), a second Cashier, Rose
  passengers Andrea, Rogelio, Grace, Paolo and Lea (Chris is Day 1's)
  trips     the Day 1 timetable posted for 7 days from today

Every password is sabaygo123. Safe to run twice: anything already there is
reported and left alone.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import struct
import sys
import urllib.error
import urllib.request
import uuid
import zlib

API = os.environ.get("SABAYGO_API", "http://127.0.0.1:8000/api/v1")
_tok: dict[str, str] = {}


def call(method, path, body=None, who=None, raw=None, ctype="application/json"):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(API + path, method=method, data=data)
    req.add_header("Content-Type", ctype)
    if who:
        req.add_header("Authorization", "Bearer " + login(who))
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


def say(ok, what, detail=""):
    print(f"  {'done ' if ok else 'skip '} {what}{(' -- ' + detail) if detail and not ok else ''}")


def png() -> bytes:
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\x00" + b"\x10\xb9\x81" * 2 + b"\x00" + b"\x10\xb9\x81" * 2))
            + chunk(b"IEND", b""))


def photo(van_id, side):
    boundary = uuid.uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"{side}.png\"\r\n"
            "Content-Type: image/png\r\n\r\n").encode() + png() + f"\r\n--{boundary}--\r\n".encode()
    return call("PUT", f"/fleet/vans/{van_id}/photos/{side}", raw=body, who="manager",
                ctype=f"multipart/form-data; boundary={boundary}")[0]


DISPATCHERS = [
    ("nonoy", "Nonoy", "Abellana", "09181234567"),
    ("jun", "Jun", "Bautista", "09181234568"),
    ("mae", "Mae", "Ocampo", "09181234569"),
]
CASHIERS = [("rose", "Rose", "Lim", "09181234570")]
PASSENGERS = [
    ("andrea.villamor", "Andrea", "Villamor", "09171112233"),
    ("rogelio.tan", "Rogelio", "Tan", "09182223344"),
    ("grace.dumaguing", "Grace", "Dumaguing", "09193334455"),
    ("paolo.reyes", "Paolo", "Reyes", "09174445566"),
    ("lea.santiago", "Lea", "Santiago", "09185556677"),
]


def main():
    today = dt.date.today().isoformat()
    print("Fares, from A2Z's trip ticket")
    route = next(r for r in call("GET", "/config/routes", who="manager")[1] if r["is_active"])
    s, b = call("POST", "/config/fares", {"route_id": route["route_id"], "fares": [
        {"from_stop_sequence": 1, "to_stop_sequence": 2, "fare_amount": "150.00", "effective_from": today},
        {"from_stop_sequence": 1, "to_stop_sequence": 4, "fare_amount": "363.00", "effective_from": today},
    ]}, "manager")
    say(s == 201, "Digos ₱150, Cotabato ₱363 from today (Kidapawan stays ₱340)", str(b))

    print("Operator and van")
    vans = {v["plate_number"]: v for v in call("GET", "/fleet/vans", who="manager")[1]}
    if "TST-1023" in vans:
        say(False, "TST-1023", "already there")
    else:
        s, op = call("POST", "/fleet/operators", {"full_name": "Arnel Bautista", "contact_number": "09171234567",
                                                  "license_number": "N03-22-145678", "license_expiry": "2028-12-31"},
                     "manager")
        if s == 201:
            s, van = call("POST", "/fleet/vans", {"plate_number": "TST-1023", "operator_id": op["operator_id"],
                                                  "seat_capacity": 14, "has_cabin_camera": True}, "manager")
            photos = [photo(van["van_id"], side) for side in ("front", "rear", "left", "right")] if s == 201 else []
            ok = (s == 201 and photos == [200] * 4
                  and call("PATCH", f"/fleet/operators/{op['operator_id']}/validation",
                           {"validation_status": "validated"}, "manager")[0] == 200
                  and call("PATCH", f"/fleet/vans/{van['van_id']}/validation",
                           {"validation_status": "validated"}, "manager")[0] == 200)
            say(ok, "TST-1023, operator Arnel Bautista, 14 spaces, four photos, validated")
        else:
            say(False, "operator Arnel Bautista", str(op))

    print("Staff")
    for role, people in (("dispatcher", DISPATCHERS), ("cashier", CASHIERS)):
        for slug, first, last, phone in people:
            s, b = call("POST", "/fleet/crew", {"email": f"{slug}@a2z.dev", "phone_number": phone,
                                                "password": "sabaygo123", "role": role,
                                                "first_name": first, "last_name": last}, "manager")
            say(s == 201, f"{role.title()} {first} {last} ({slug}@a2z.dev)", "already there" if s == 409 else str(b))
    crew = {c["email"]: c for c in call("GET", "/fleet/crew", who="manager")[1]}
    for email, c in crew.items():
        if c.get("role") == "dispatcher" and c.get("validation_status") != "validated":
            s, _ = call("PATCH", f"/fleet/crew/{c['user_id']}/validation", {"validation_status": "validated"},
                        "manager")
            say(s == 200, f"{email} validated")

    print("Passengers")
    for slug, first, last, phone in PASSENGERS:
        s, b = call("POST", "/auth/register", {"email": f"{slug}@a2z.dev", "phone_number": phone,
                                               "password": "sabaygo123", "first_name": first, "last_name": last})
        say(s == 201, f"{first} {last} ({slug}@a2z.dev)", "already there" if s == 409 else str(b))

    print("Trips")
    s, reports = call("POST", f"/config/trips/generate?service_date={today}&days_ahead=7", None, "manager")
    made = sum(r["trips_created"] for r in reports) if s == 200 else 0
    say(s == 200, f"the timetable posted for 7 days: {made} trips", str(reports))


if __name__ == "__main__":
    main()
