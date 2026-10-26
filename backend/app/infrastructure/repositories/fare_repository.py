"""The fare in force (brief Table 27, `Fare_Matrix` with `EffectiveFrom`).

Per stop pair on a route, the fare is the row with the latest
`effective_from` on or before the trip's service date. A fare change is a
new row dated when it takes effect, never an edit of one already in
force, so a trip keeps the fare of its own day and a change set ahead
waits for its date.

Read fares through this class only. Search, the Dispatcher's walk-in
preview and the charge itself all ask it, so the screen cannot quote one
price while the booking charges another.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.infrastructure.models import FareMatrix


class FareRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def in_force(self, route_id: str, on: dt.date) -> dict[tuple[int, int], Decimal]:
        """(boarding stop, alighting stop) -> fare, for every pair the
        route has a fare for on `on`."""
        rows = await self.session.execute(
            select(FareMatrix)
            .where(FareMatrix.route_id == route_id, FareMatrix.effective_from <= on)
            .order_by(
                FareMatrix.from_stop_sequence,
                FareMatrix.to_stop_sequence,
                FareMatrix.effective_from.desc(),
            )
        )
        fares: dict[tuple[int, int], Decimal] = {}
        for f in rows.scalars():
            # The first row per pair is the newest one in force.
            fares.setdefault((f.from_stop_sequence, f.to_stop_sequence), f.fare_amount)
        return fares

    async def fare(self, route_id: str, boarding: int, alighting: int, on: dt.date) -> Decimal | None:
        """The fare for one pair on `on`; None when the route has none."""
        row = await self.session.execute(
            select(FareMatrix.fare_amount)
            .where(
                FareMatrix.route_id == route_id,
                FareMatrix.from_stop_sequence == boarding,
                FareMatrix.to_stop_sequence == alighting,
                FareMatrix.effective_from <= on,
            )
            .order_by(FareMatrix.effective_from.desc())
            .limit(1)
        )
        return row.scalar_one_or_none()
