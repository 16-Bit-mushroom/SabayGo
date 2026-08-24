"""Seat inventory repository -- the pessimistic locking implementation.

This module is the technical core of the thesis. Everything else in the
backend is supporting infrastructure; this is the contribution.

WHY A COARSE LOCK
-----------------
The obvious single-query form is:

    SELECT seat_number FROM seat_inventory
     WHERE trip_id = ? AND leg_sequence BETWEEN ? AND ? AND status='available'
     GROUP BY seat_number HAVING COUNT(*) = ?
     ORDER BY seat_number LIMIT 1 FOR UPDATE

MySQL's locking semantics for FOR UPDATE combined with GROUP BY and
LIMIT are subtle: the rows the optimiser scans and the rows it returns
after aggregation are not the same set, so exactly which rows end up
locked depends on the plan. That is a poor foundation for a correctness
claim you have to defend.

Instead we lock the whole candidate window -- every seat-leg row for this
trip across the requested span -- and then pick in Python. For a 14-seat
van on a 4-stop route that is at most 42 rows, and in practice only the
legs actually requested. The lock set is small, bounded, and identical
regardless of query plan.

The trade-off is honest and worth stating in the manuscript: this
serialises concurrent bookings on overlapping spans of the same trip.
That is exactly the intended behaviour for a 14-seat vehicle. It would be
the wrong choice for a 400-seat aircraft, where you would want row-level
granularity per seat.

THREE LAYERS OF DEFENCE
-----------------------
1. Domain  -- Segment expresses "one seat, free on every leg in the span"
2. Here    -- SELECT ... FOR UPDATE serialises the read-then-write
3. Database-- UNIQUE (trip_id, seat_number, leg_sequence) makes a
              double-seating physically impossible even if 1 and 2 fail
"""

from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, text, update
from sqlalchemy.exc import OperationalError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import (
    NoSeatAvailableError,
    NotFoundError,
    SeatLockTimeoutError,
)
from app.domain.enums import SeatStatus
from app.domain.value_objects import Segment
from app.infrastructure.models import SeatInventory

log = logging.getLogger(__name__)

# MySQL error 1205: lock wait timeout exceeded.
# MySQL error 1213: deadlock found, transaction rolled back.
_LOCK_ERRNOS = {1205, 1213}


class SeatRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    # ------------------------------------------------------------------
    async def allocate_seat(
        self,
        *,
        trip_id: str,
        segment: Segment,
        hold_ttl_seconds: int = 600,
    ) -> int:
        """Lock the candidate window and claim the lowest free seat.

        MUST be called inside an open transaction. The caller commits.

        Returns the allocated seat number.
        Raises NoSeatAvailableError if no seat is free across the whole span.
        Raises SeatLockTimeoutError if the row lock could not be acquired.
        """
        lo_leg, hi_leg = segment.leg_range
        leg_count = segment.leg_count

        try:
            # ---- (1) LOCK ------------------------------------------------
            # Every seat-leg row in the requested window, regardless of
            # status. Locking unconditionally (rather than filtering to
            # status='available') means a row another transaction is
            # currently releasing cannot slip through between our read and
            # our write.
            locked = await self.session.execute(
                select(SeatInventory)
                .where(
                    SeatInventory.trip_id == trip_id,
                    SeatInventory.leg_sequence >= lo_leg,
                    SeatInventory.leg_sequence <= hi_leg,
                )
                .order_by(SeatInventory.seat_number, SeatInventory.leg_sequence)
                .with_for_update()
            )
            rows = list(locked.scalars().all())

        except OperationalError as exc:
            errno = getattr(getattr(exc, "orig", None), "args", [None])[0]
            if errno in _LOCK_ERRNOS:
                log.warning("Seat lock contention on trip %s (errno=%s)", trip_id, errno)
                raise SeatLockTimeoutError(
                    "The seat map is busy. Please try again."
                ) from exc
            raise

        if not rows:
            raise NotFoundError(f"No seat inventory exists for trip {trip_id}.")

        # ---- (2) CHOOSE --------------------------------------------------
        now = datetime.now(timezone.utc)
        free_legs_by_seat: dict[int, int] = {}
        for row in rows:
            usable = row.status == SeatStatus.AVAILABLE.value or (
                row.status == SeatStatus.HELD.value
                and row.hold_expires_at is not None
                and row.hold_expires_at.replace(tzinfo=timezone.utc) < now
            )
            if usable:
                free_legs_by_seat[row.seat_number] = (
                    free_legs_by_seat.get(row.seat_number, 0) + 1
                )

        # A seat qualifies only if it is free on EVERY leg of the span --
        # this is what allows the same seat to be sold twice on
        # non-overlapping portions of the same trip.
        candidates = [s for s, n in free_legs_by_seat.items() if n == leg_count]
        if not candidates:
            raise NoSeatAvailableError(
                "No single seat is available for the whole of this segment."
            )

        seat_number = min(candidates)  # deterministic: lowest-indexed seat

        # ---- (3) CLAIM ---------------------------------------------------
        await self.session.execute(
            update(SeatInventory)
            .where(
                SeatInventory.trip_id == trip_id,
                SeatInventory.seat_number == seat_number,
                SeatInventory.leg_sequence >= lo_leg,
                SeatInventory.leg_sequence <= hi_leg,
            )
            .values(
                status=SeatStatus.HELD.value,
                hold_expires_at=now + timedelta(seconds=hold_ttl_seconds),
            )
        )
        return seat_number

    # ------------------------------------------------------------------
    async def bind_to_booking(
        self, *, trip_id: str, seat_number: int, segment: Segment, booking_id: str
    ) -> None:
        lo_leg, hi_leg = segment.leg_range
        await self.session.execute(
            update(SeatInventory)
            .where(
                SeatInventory.trip_id == trip_id,
                SeatInventory.seat_number == seat_number,
                SeatInventory.leg_sequence >= lo_leg,
                SeatInventory.leg_sequence <= hi_leg,
            )
            .values(booking_id=booking_id)
        )

    async def confirm(self, *, booking_id: str) -> None:
        """Payment cleared: held -> booked, hold no longer expires."""
        await self.session.execute(
            update(SeatInventory)
            .where(SeatInventory.booking_id == booking_id)
            .values(status=SeatStatus.BOOKED.value, hold_expires_at=None)
        )

    async def release(self, *, booking_id: str) -> None:
        """Cancellation or reschedule: return the seat-legs to the pool."""
        await self.session.execute(
            update(SeatInventory)
            .where(SeatInventory.booking_id == booking_id)
            .values(
                status=SeatStatus.AVAILABLE.value,
                booking_id=None,
                hold_expires_at=None,
            )
        )

    async def sweep_expired_holds(self) -> int:
        """Release seats whose checkout was abandoned. Run periodically."""
        result = await self.session.execute(
            update(SeatInventory)
            .where(
                SeatInventory.status == SeatStatus.HELD.value,
                SeatInventory.hold_expires_at < datetime.now(timezone.utc),
            )
            .values(
                status=SeatStatus.AVAILABLE.value,
                booking_id=None,
                hold_expires_at=None,
            )
        )
        return result.rowcount or 0

    # ------------------------------------------------------------------
    async def count_available(self, *, trip_id: str, segment: Segment) -> int:
        """Non-locking availability read for search results.

        Deliberately dirty: it is a display hint, not a reservation. The
        authoritative check happens under lock in allocate_seat().
        """
        lo_leg, hi_leg = segment.leg_range
        result = await self.session.execute(
            text(
                """
                SELECT COUNT(*) FROM (
                    SELECT seat_number
                      FROM seat_inventory
                     WHERE trip_id = :trip_id
                       AND leg_sequence BETWEEN :lo AND :hi
                       AND status = 'available'
                     GROUP BY seat_number
                    HAVING COUNT(*) = :leg_count
                ) AS free_seats
                """
            ),
            {
                "trip_id": trip_id,
                "lo": lo_leg,
                "hi": hi_leg,
                "leg_count": segment.leg_count,
            },
        )
        return int(result.scalar_one())