# SabayGo Backend

FastAPI + SQLAlchemy 2.0 (async) on the MySQL 8.0 schema in `../db`.

## Setup

```bash
cd backend
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
python3 -c "import secrets; print('JWT_SECRET=' + secrets.token_urlsafe(48))"
# paste that into .env
```

Seed a real password hash first, or login will always fail:

```bash
python3 -c "import bcrypt; print(bcrypt.hashpw(b'sabaygo123', bcrypt.gensalt()).decode())"
```

```sql
UPDATE users SET password_hash = '<paste>' WHERE email LIKE '%@sabaygo.test';
```

## Run

```bash
uvicorn app.main:app --reload
```

Docs at <http://127.0.0.1:8000/docs>.

## The concurrency experiment

This is the thesis validation. Reset to a clean trip first, or leftover
bookings will skew the result.

```bash
cd .. && ./db/apply.sh --reset --seed && cd backend
uvicorn app.main:app &
python tests/integration/test_concurrency.py --requests 50
```

Expect: 10 created (the `advance_booking_seat_cap`), 40 rejected,
**0 double-booked seats**. Save the output — it is your Results table.

Run it at 10, 25, 50, and 100 concurrent requests and tabulate. A curve
across load levels is far more convincing than a single data point.

## Layer rules

| Layer | May import | Never imports |
|---|---|---|
| `domain/` | stdlib only | fastapi, sqlalchemy |
| `application/` | domain, repositories | fastapi |
| `infrastructure/` | domain, sqlalchemy | fastapi |
| `api/` | everything | — |

If a domain file ever needs `from fastapi import ...`, the rule has been
broken and the entity is no longer unit-testable without a server.

## Where the locking lives

`infrastructure/repositories/seat_repository.py` — `allocate_seat()`.
Read the module docstring before modifying it; it explains why the lock is
deliberately coarse and why the single-query `GROUP BY ... FOR UPDATE`
form was rejected.

## Not yet built

Reschedule, cancel, check-in, QR scan, payments/webhooks, audit trigger,
trip generation, notifications, fleet CRUD, policy CRUD.