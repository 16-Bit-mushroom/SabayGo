#!/usr/bin/env python3
"""Apply Group C edits in place.

Patches rather than replaces, so the roadside-pickup work in
reserve_seat.py and the DATETIME(fsp=6) fix in models are preserved.

    python3 apply_group_c.py        (run from backend/)
"""

import pathlib
import sys

BACKEND = pathlib.Path(__file__).resolve().parent
changed = []


def patch(path: pathlib.Path, old: str, new: str, label: str) -> None:
    s = path.read_text()
    if new.strip().splitlines()[0] in s:
        print(f"  skip  {label} (already applied)")
        return
    if old not in s:
        sys.exit(f"  FAIL  {label}: anchor not found. Paste the file and stop here.")
    path.write_text(s.replace(old, new, 1))
    changed.append(label)
    print(f"  ok    {label}")


# ─────────────────────────────────────────────────────────────────────
# 1. Payment.remittance_id — links a fare to the handover that covered it
# ─────────────────────────────────────────────────────────────────────
models = BACKEND / "app/infrastructure/models/__init__.py"
patch(
    models,
    "    provider_ref_id: Mapped[str | None] = mapped_column(String(128))",
    "    # Set when this fare is included in an end-of-trip cash handover.\n"
    "    remittance_id: Mapped[str | None] = mapped_column(String(36))\n"
    "    provider_ref_id: Mapped[str | None] = mapped_column(String(128))",
    "Payment.remittance_id",
)

# ─────────────────────────────────────────────────────────────────────
# 2. CashRemittance model
# ─────────────────────────────────────────────────────────────────────
s = models.read_text()
if "class CashRemittance" not in s:
    s += '''

class CashRemittance(Base):
    """End-of-trip cash handover from crew to office.

    `expected_amount` is computed from the crew member's own cash bookings
    and never typed in -- the figure a person is measured against must not
    be editable by that person.
    """

    __tablename__ = "cash_remittances"

    remittance_id: Mapped[str] = mapped_column(UUID_PK, primary_key=True)
    trip_id: Mapped[str] = mapped_column(ForeignKey("trips.trip_id"))
    collected_by_user_id: Mapped[str] = mapped_column(ForeignKey("users.user_id"))
    expected_amount: Mapped[Decimal] = mapped_column(Numeric(10, 2))
    declared_amount: Mapped[Decimal | None] = mapped_column(Numeric(10, 2))
    received_amount: Mapped[Decimal | None] = mapped_column(Numeric(10, 2))
    variance: Mapped[Decimal | None] = mapped_column(Numeric(10, 2))
    status: Mapped[str] = mapped_column(String(16), default="pending")
    submitted_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))
    received_at: Mapped[dt.datetime | None] = mapped_column(DATETIME(fsp=6))
    received_by_user_id: Mapped[str | None] = mapped_column(
        ForeignKey("users.user_id")
    )
    notes: Mapped[str | None] = mapped_column(String(512))
    created_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))
    updated_at: Mapped[dt.datetime] = mapped_column(DATETIME(fsp=6))
'''
    models.write_text(s)
    changed.append("CashRemittance model")
    print("  ok    CashRemittance model")
else:
    print("  skip  CashRemittance model (already applied)")

# ─────────────────────────────────────────────────────────────────────
# 3. Cash bookings write a pending payment row
# ─────────────────────────────────────────────────────────────────────
reserve = BACKEND / "app/application/booking/reserve_seat.py"
s = reserve.read_text()

if "from app.infrastructure.models import Payment as PaymentRow" not in s:
    s = s.replace(
        "from app.infrastructure.models import FareMatrix, Trip",
        "from app.infrastructure.models import FareMatrix, Trip\n"
        "from app.infrastructure.models import Payment as PaymentRow",
        1,
    )
if "\nimport uuid" not in s:
    s = s.replace("import logging\n", "import logging\nimport uuid\n", 1)
reserve.write_text(s)

patch(
    reserve,
    "        if is_cash:\n"
    "            await self.seats.confirm(booking_id=booking.booking_id)",
    "        if is_cash:\n"
    "            await self.seats.confirm(booking_id=booking.booking_id)\n"
    "            # Record the fare as collected but NOT settled. This is the\n"
    "            # false-leakage fix: cash in a conductor's pocket is a\n"
    "            # different state from money missing, and the revenue view\n"
    "            # now separates the two. It settles when the crew remits at\n"
    "            # the end of the trip.\n"
    "            self.session.add(\n"
    "                PaymentRow(\n"
    "                    payment_id=str(uuid.uuid4()),\n"
    "                    booking_id=booking.booking_id,\n"
    "                    provider=\"cash\",\n"
    "                    method=\"cash\",\n"
    "                    amount=fare,\n"
    "                    status=\"pending\",\n"
    "                    created_at=now,\n"
    "                )\n"
    "            )",
    "cash payment row",
)

print()
print(f"{len(changed)} change(s) applied." if changed else "Nothing to do.")
print("Next:  python -c \"from app.main import app; print('imports ok')\"")
