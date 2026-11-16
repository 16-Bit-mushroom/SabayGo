#!/usr/bin/env python3
"""The 10 Nov alpha run as a journey: A2Z trip ticket Nº 0012223 replayed.

    ./db/load-day1.sh && backend/venv/bin/python backend/tests/integration/test_trip_ticket.py

On the Day 1 data (A2Z's route Ecoland -> Digos -> Kidapawan -> Cotabato),
it does what the office did by hand on 10 Nov
(`docs/ALPHA_TEST_CASE_TRIP_TICKET.md`): the ticket's fares, the ticket's
van with a new operator, a new Dispatcher, three passengers who sign up,
five departures today, then five trips from reservation to arrival, and
checks every peso against the hand calculation:

  1  TST-1023  the ticket's 8: 2 booked + 6 walk-ins     due 525.20
  2  ABC-1234  2 booked + 5 walk-ins                      due 438.80
  3  LCT-9042  10 walk-ins; an unpaid reservation cancelled  due 570.20
  4  TST-1023  its second trip: no second parking         due 369.75
  5  ABC-1234  a disputed line adjusted 51.00 -> 22.50    due 478.65
     the day's terminal fees                                  2,382.60
  6  LCT-9042  an extra departure: the operator's share given first,
               then the line's dispute upheld -- the 308.55 the operator
               now holds over the share is previewed, told and handed
               back (finding 35)

The ticket itself totals ₱2,185 with 15 % = ₱327.75 because four of its
passengers paid the senior fare (₱290); SabayGo has no discount fare
(finding 32), so trip 1 counts them at ₱363. Departure times are set from
the clock (40 to 80 minutes ahead) with Start opening 300 minutes early,
so the script runs at any hour before 22:40.
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
from decimal import Decimal

API = os.environ.get("SABAYGO_API", "http://127.0.0.1:8000/api/v1")
P = F = 0
_tok: dict[str, str] = {}


def ok(m):
    global P
    P += 1
    print(f"  \033[32mPASS\033[0m  {m}")


def bad(m):
    global F
    F += 1
    print(f"  \033[31mFAIL\033[0m  {m}")


def is_(got, want, m):
    (ok if got == want else bad)(m if got == want else f"{m} (got {got}, wanted {want})")


def hdr(m):
    print(f"\n\033[1m── {m} ─────────────────────\033[0m")


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
        email = who if "@" in who else f"{who}@a2z.dev"
        s, b = call("POST", "/auth/login", {"email": email, "password": "sabaygo123"})
        if s != 200:
            raise SystemExit(f"cannot sign in as {email}: {b}")
        _tok[who] = b["access_token"]
    return _tok[who]


def png() -> bytes:
    """A tiny valid PNG, for the van's four photographs."""
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\x00" + b"\x10\xb9\x81" * 2 + b"\x00" + b"\x10\xb9\x81" * 2))
            + chunk(b"IEND", b""))


def upload(van_id, side):
    boundary = uuid.uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"{side}.png\"\r\n"
            "Content-Type: image/png\r\n\r\n").encode() + png() + f"\r\n--{boundary}--\r\n".encode()
    return call("PUT", f"/fleet/vans/{van_id}/photos/{side}", raw=body, who="manager",
                ctype=f"multipart/form-data; boundary={boundary}")[0]


def share(trip_id):
    return call("GET", f"/trips/{trip_id}/share", who="joy")[1]


def walk_ins(dispatcher, trip_id, stop, n):
    codes = [call("POST", "/bookings/walk-in", {"trip_id": trip_id, "boarding_stop": 1, "alighting_stop": stop},
                  dispatcher)[0] for _ in range(n)]
    return codes.count(201)


def reserve_and_pay(who, dispatcher, trip_id, stop):
    s, b = call("POST", "/bookings/reserve", {"trip_id": trip_id, "boarding_stop": 1, "alighting_stop": stop}, who)
    if s != 201:
        bad(f"{who} reserves: {s} {b}")
        return None
    s2, _ = call("POST", f"/bookings/{b['booking_id']}/mark-paid", {}, dispatcher)
    return b if s2 == 200 else None


def pay_start_depart_arrive(trip_id, dispatcher, reference):
    s = share(trip_id)
    left = Decimal(s["operator_share_owed"]) - Decimal(s.get("operator_share_held", s["operator_share_given"]))
    codes = [
        call("POST", f"/trips/{trip_id}/payment",
             {"amount": s["amount_due"], "reference": reference, "operator_share": str(max(left, Decimal(0)))},
             "joy")[0],
        call("POST", f"/trips/{trip_id}/start", None, "joy")[0],
        call("POST", f"/trips/{trip_id}/depart", None, dispatcher)[0],
        call("POST", f"/trips/{trip_id}/arrive", None, dispatcher)[0],
    ]
    return codes


def board_row(trip_id):
    today = dt.date.today().isoformat()
    return next(t for t in call("GET", f"/config/trips?date={today}", who="manager")[1] if t["trip_id"] == trip_id)


def main():
    hdr("1. Setup, as the office typed it on 10 Nov")
    routes = call("GET", "/config/routes", who="manager")[1]
    route = next(r for r in routes if "Cotabato" in r["route_name"])
    today = dt.date.today()
    s, _ = call("POST", "/config/fares", {"route_id": route["route_id"], "fares": [
        {"from_stop_sequence": 1, "to_stop_sequence": 2, "fare_amount": "150.00", "effective_from": today.isoformat()},
        {"from_stop_sequence": 1, "to_stop_sequence": 4, "fare_amount": "363.00", "effective_from": today.isoformat()},
    ]}, "manager")
    is_(s, 201, "the ticket's fares: Digos ₱150, Cotabato ₱363, from today")
    for key in ("start_opens_minutes", "checkin_window_minutes"):
        is_(call("PUT", f"/config/policies/{key}", {"policy_value": "300"}, "manager")[0], 200,
            f"{key} 300 for the test")

    s, op = call("POST", "/fleet/operators", {"full_name": "Arnel Bautista", "contact_number": "09171234567",
                                              "license_number": "N03-22-145678", "license_expiry": "2028-12-31"},
                 "manager")
    is_(s, 201, "operator Arnel Bautista")
    s, van = call("POST", "/fleet/vans", {"plate_number": "TST-1023", "operator_id": op["operator_id"],
                                          "seat_capacity": 14, "has_cabin_camera": True}, "manager")
    is_(s, 201, "van TST-1023 (a made-up plate)")
    is_([upload(van["van_id"], side) for side in ("front", "rear", "left", "right")], [200] * 4,
        "its four photographs")
    is_(call("PATCH", f"/fleet/operators/{op['operator_id']}/validation", {"validation_status": "validated"},
             "manager")[0], 200, "operator validated")
    is_(call("PATCH", f"/fleet/vans/{van['van_id']}/validation", {"validation_status": "validated"},
             "manager")[0], 200, "van validated")
    s, staff = call("POST", "/fleet/crew", {"email": "nonoy@a2z.dev", "phone_number": "09181234567",
                                            "password": "sabaygo123", "role": "dispatcher",
                                            "first_name": "Nonoy", "last_name": "Abellana"}, "manager")
    is_(s, 201, "Dispatcher Nonoy Abellana")
    crew = {c["email"]: c for c in call("GET", "/fleet/crew", who="manager")[1]}
    for email in ("nonoy@a2z.dev", "liza@a2z.dev", "ramon@a2z.dev"):
        uid = crew[email]["user_id"]
        if crew[email].get("validation_status") != "validated":
            call("PATCH", f"/fleet/crew/{uid}/validation", {"validation_status": "validated"}, "manager")
    crew = {c["email"]: c for c in call("GET", "/fleet/crew", who="manager")[1]}
    is_({crew[e].get("validation_status") for e in ("nonoy@a2z.dev", "liza@a2z.dev", "ramon@a2z.dev")},
        {"validated"}, "the three Dispatchers validated")

    hdr("2. Three passengers sign up")
    for slug, first, last, phone in (("andrea.villamor", "Andrea", "Villamor", "09171112233"),
                                     ("rogelio.tan", "Rogelio", "Tan", "09182223344"),
                                     ("grace.dumaguing", "Grace", "Dumaguing", "09193334455")):
        is_(call("POST", "/auth/register", {"email": f"{slug}@a2z.dev", "phone_number": phone,
                                            "password": "sabaygo123", "first_name": first, "last_name": last})[0],
            201, f"{first} {last} registers")

    hdr("3. Five departures today, then Create upcoming trips")
    mask = "".join("1" if i == today.weekday() else "0" for i in range(7))
    base = dt.datetime.now().replace(second=0, microsecond=0) + dt.timedelta(minutes=40)
    labels = []
    for i in range(5):
        at = (base + dt.timedelta(minutes=10 * i)).time()
        label = f"Ticket test {i + 1}"
        labels.append(label)
        s, _ = call("POST", "/config/schedule-templates", {"route_id": route["route_id"],
                                                           "departure_time": at.strftime("%H:%M:%S"),
                                                           "days_of_week": mask, "trip_label": label}, "manager")
        is_(s, 201, f"departure {at.strftime('%H:%M')} ({label})")
    s, _ = call("POST", f"/config/trips/generate?service_date={today.isoformat()}&days_ahead=1", None, "manager")
    is_(s, 200, "upcoming trips created")
    rows = call("GET", f"/config/trips?date={today.isoformat()}", who="manager")[1]
    trip = {r["trip_label"]: r["trip_id"] for r in rows if r.get("trip_label") in labels}
    is_(len(trip), 5, "the five trips exist today")
    vans = {v["plate_number"]: v["van_id"] for v in call("GET", "/fleet/vans", who="manager")[1]}
    disp = {e.split("@")[0]: crew[e]["user_id"] for e in crew}

    def assign(label, plate, who):
        return call("PUT", f"/trips/{trip[label]}/assignment", {"van_id": vans[plate], "dispatcher_id": disp[who]},
                    "manager")[0]

    hdr("4. Trip 1: the ticket's eight passengers")
    t1 = trip[labels[0]]
    is_(assign(labels[0], "TST-1023", "nonoy"), 200, "TST-1023 and Nonoy assigned")
    s, refused = call("POST", f"/trips/{t1}/start", None, "manager")
    is_(s, 409, "Start refused before the terminal fees are recorded")
    booked = [reserve_and_pay(p, "nonoy", t1, 4) for p in ("andrea.villamor", "rogelio.tan")]
    is_(sum(b is not None for b in booked), 2, "two app passengers to Cotabato, marked Paid at ₱363")
    is_(walk_ins("nonoy", t1, 4, 4) + walk_ins("nonoy", t1, 3, 1) + walk_ins("nonoy", t1, 2, 1), 6,
        "six walk-ins: four to Cotabato, one to Kidapawan, one to Digos")
    s1 = share(t1)
    is_(s1["amount_due"], "525.20", "due ₱525.20 = 15 % of ₱2,668 (₱400.20) + DCOTT ₱75 + parking ₱50")
    is_(s1["operator_share_owed"], "2142.80", "operator's share ₱2,142.80")
    is_(pay_start_depart_arrive(t1, "nonoy", "0012223"), [200] * 4, "paid (ref. 0012223), started, departed, arrived")
    is_(board_row(t1)["booked"], 8, "the board still counts 8 booked after departure (finding 30)")

    hdr("5. Trip 2: two booked, five walk-ins")
    t2 = trip[labels[1]]
    is_(assign(labels[1], "ABC-1234", "ramon"), 200, "ABC-1234 and Ramon assigned")
    is_(sum(reserve_and_pay(*a) is not None for a in (("grace.dumaguing", "ramon", t2, 3),
                                                      ("chris@a2z.dev", "ramon", t2, 4))), 2,
        "Grace to Kidapawan ₱340, Chris to Cotabato ₱363, both Paid")
    is_(walk_ins("ramon", t2, 4, 3) + walk_ins("ramon", t2, 2, 2), 5, "five walk-ins")
    is_(share(t2)["amount_due"], "438.80", "due ₱438.80 = 15 % of ₱2,092 + ₱75 + ₱50")
    is_(pay_start_depart_arrive(t2, "ramon", "0012224"), [200] * 4, "paid, started, departed, arrived")

    hdr("6. Trip 3: walk-ins, and a reservation cancelled before payment")
    t3 = trip[labels[2]]
    is_(assign(labels[2], "LCT-9042", "liza"), 200, "LCT-9042 and Liza assigned")
    s, r = call("POST", "/bookings/reserve", {"trip_id": t3, "boarding_stop": 1, "alighting_stop": 2}, "rogelio.tan")
    is_(s, 201, "Rogelio reserves to Digos")
    s, c = call("POST", f"/bookings/{r['booking_id']}/cancel", {}, "rogelio.tan")
    is_((s, c.get("status") if isinstance(c, dict) else c), (200, "cancelled"), "and cancels it, unpaid")
    is_(walk_ins("liza", t3, 4, 6) + walk_ins("liza", t3, 2, 3) + walk_ins("liza", t3, 3, 1), 10, "ten walk-ins")
    is_(share(t3)["amount_due"], "570.20", "due ₱570.20: the cancelled reservation counts for nothing")
    is_(pay_start_depart_arrive(t3, "liza", "0012225"), [200] * 4, "paid, started, departed, arrived")

    hdr("7. Trip 4: TST-1023's second trip, parking once a day")
    t4 = trip[labels[3]]
    is_(assign(labels[3], "TST-1023", "nonoy"), 200, "TST-1023 assigned again: its first trip is paid")
    is_(reserve_and_pay("grace.dumaguing", "nonoy", t4, 2) is not None, True, "Grace to Digos, Paid")
    is_(walk_ins("nonoy", t4, 4, 5), 5, "five walk-ins to Cotabato")
    is_(share(t4)["amount_due"], "369.75", "due ₱369.75 = 15 % of ₱1,965 + ₱75, no second ₱50")
    is_(pay_start_depart_arrive(t4, "nonoy", "0012226"), [200] * 4, "paid, started, departed, arrived")

    hdr("8. Trip 5: an operator's dispute, decided before payment")
    t5 = trip[labels[4]]
    is_(assign(labels[4], "ABC-1234", "ramon"), 200, "ABC-1234 assigned again")
    is_(walk_ins("ramon", t5, 4, 7) + walk_ins("ramon", t5, 3, 1), 8, "eight walk-ins")
    s5 = share(t5)
    is_(s5["amount_due"], "507.15", "due ₱507.15 before the dispute")
    kid = next(line for line in s5["lines"] if line["trip_id"] == t5 and line["dest_terminal_name"].startswith("Kidapawan"))
    s, d = call("POST", "/disputes", {"subject": "fare_line", "line_id": kid["line_id"],
                                      "operator_statement": "The Kidapawan passenger got off at Digos."}, "joy")
    is_(s, 201, "the Cashier records the operator's dispute on the Kidapawan line")
    is_(share(t5)["amount_due"], "456.15", "₱51.00 waits: due ₱456.15")
    s, _ = call("POST", f"/disputes/{d['dispute_id']}/decide",
                {"outcome": "adjusted", "note": "Alighted at Digos.", "adjusted_amount": "22.50"}, "manager")
    is_(s, 200, "the Terminal Manager adjusts it to ₱22.50")
    is_(share(t5)["amount_due"], "478.65", "due ₱478.65")
    is_(pay_start_depart_arrive(t5, "ramon", "0012227"), [200] * 4, "paid, started, departed, arrived")

    hdr("9. The day")
    sts = call("GET", f"/statements?date={today.isoformat()}", who="joy")[1]
    fees = sum(Decimal(x["terminal_fees_owed"]) + Decimal(x["held_share"]) for x in sts)
    paid = sum(Decimal(x["settled_amount"]) for x in sts)
    is_(f"{fees:.2f}/{paid:.2f}", "2382.60/2382.60", "terminal fees ₱2,382.60, all of it recorded")
    hist = call("GET", "/statements/history?days=7", who="joy")[1]
    is_(f"{Decimal(hist[-1]['terminal_fees']):.2f}", f"{fees:.2f}", "the Money chart's today matches")

    hdr("10. An upheld dispute after the operator's share was given (finding 35)")
    route_id = route["route_id"]
    at = (dt.datetime.now() + dt.timedelta(minutes=120)).replace(second=0, microsecond=0)
    s, extra = call("POST", "/config/trips/special", {"route_id": route_id, "departure_datetime": at.isoformat(),
                                                      "van_id": vans["LCT-9042"], "dispatcher_id": disp["liza"],
                                                      "trip_label": "Ticket test 6"}, "manager")
    is_(s, 201, "an extra LCT-9042 departure, Liza")
    t6 = extra["trip_id"]
    is_(walk_ins("liza", t6, 4, 1), 1, "one walk-in to Cotabato, ₱363")
    s6 = share(t6)
    rid = s6["remittance_id"]
    left = Decimal(s6["operator_share_owed"]) - Decimal(s6["operator_share_held"])
    is_(f"{left:.2f}", "233.55", "₱233.55 more share owed: ₱363 less 15 % ₱54.45 less DCOTT ₱75")
    is_(call("POST", f"/statements/{rid}/operator-share", {"amount": str(left)}, "joy")[0], 200,
        "the Cashier records it handed to the operator, before the fees")
    line = next(x for x in s6["lines"] if x["trip_id"] == t6)
    s, d6 = call("POST", "/disputes", {"subject": "fare_line", "line_id": line["line_id"],
                                       "operator_statement": "That passenger rode free."}, "joy")
    is_(s, 201, "the operator disputes the line")

    def statement():
        return next(x for x in call("GET", f"/statements?date={today.isoformat()}", who="joy")[1]
                    if x["remittance_id"] == rid)

    st0 = statement()
    s, pv = call("POST", f"/disputes/{d6['dispute_id']}/preview", {"outcome": "upheld"}, "manager")
    is_(s, 200, "the Terminal Manager previews Upheld")
    is_((pv["before"]["operator_share_over"], pv["after"]["operator_share_over"]), ("0.00", "308.55"),
        "the preview shows the operator would hold ₱308.55 over the share")
    is_(f"{Decimal(pv['before']['terminal_fees_owed']) - Decimal(pv['after']['terminal_fees_owed']):.2f}", "54.45",
        "and the terminal fees ₱54.45 lower")
    s, pr = call("POST", f"/disputes/{d6['dispute_id']}/preview", {"outcome": "rejected"}, "manager")
    is_((s, pr["after"]["operator_share_over"]), (200, "0.00"), "Rejected would leave nothing over")
    s, _ = call("POST", f"/disputes/{d6['dispute_id']}/preview", {"outcome": "adjusted", "adjusted_amount": "99.00"},
                "manager")
    is_(s, 422, "a preview with an adjusted share above the disputed ₱54.45 is refused like the decision")
    st1 = statement()
    is_((st1["operator_share_owed"], st1["terminal_fees_owed"], st1["disputed"]),
        (st0["operator_share_owed"], st0["terminal_fees_owed"], st0["disputed"]),
        "a preview writes nothing")
    is_(call("POST", f"/statements/{rid}/operator-share-returned", {"amount": "1.00"}, "joy")[0], 409,
        "nothing can be recorded as handed back while the operator holds no excess")

    s, _ = call("POST", f"/disputes/{d6['dispute_id']}/decide", {"outcome": "upheld", "note": "Rode free."},
                "manager")
    is_(s, 200, "the dispute is upheld")
    st2 = statement()
    is_(st2["operator_share_over"], "308.55", "the statement shows ₱308.55 held over the share, at once")
    notes = call("GET", "/notifications", who="joy")[1]
    notes = notes.get("items", notes) if isinstance(notes, dict) else notes
    is_(any(n.get("type") == "share_over_given" and "308.55" in n.get("message", "") for n in notes), True,
        "the Cashier is told, with the amount")
    is_(call("POST", f"/statements/{rid}/operator-share-returned", {"amount": "400.00"}, "joy")[0], 409,
        "more than the excess is refused")
    is_(call("POST", f"/statements/{rid}/operator-share-returned", {"amount": "300.00"}, "manager")[0], 403,
        "the Terminal Manager does not record cash")
    s, st3 = call("POST", f"/statements/{rid}/operator-share-returned", {"amount": "300.00"}, "joy")
    is_((s, st3["operator_share_over"]), (200, "8.55"), "₱300.00 handed back: ₱8.55 still over")
    s, st4 = call("POST", f"/statements/{rid}/operator-share-returned", {"amount": "8.55"}, "joy")
    is_((s, st4["operator_share_over"], st4["operator_share_returned"]), (200, "0.00", "308.55"),
        "the rest handed back: nothing over, ₱308.55 returned")
    is_((st4["operator_share_given"], st4["operator_share_returned_by_name"] is not None),
        (st2["operator_share_given"], True), "what was given stays on record beside what came back, and who")
    is_(Decimal(st4["operator_share_held"]), Decimal(st4["operator_share_owed"]),
        "the operator now holds exactly the share owed")

    print(f"\n  {P} passed, {F} failed")
    return F == 0


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
