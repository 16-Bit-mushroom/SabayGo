"""Cooperative policy repository.

Every value A2Z has not yet decided is a row here rather than a constant
in code. When the pitch produces answers, the Terminal Manager's console updates
rows -- no migration, no redeploy.

Since migration 021 a key keeps every value it has held (brief Table 33):
the value in force is the latest row whose effective_from has passed, and
a change is a new row, never an edit. Read policies through this class
only; a bare lookup by key would find an arbitrary historical row.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import NotFoundError
from app.core.timezone import now
from app.domain.policies import check_policy_value
from app.infrastructure.models import CooperativePolicy

_TRUE = {"true", "1", "yes", "on"}


def _now() -> dt.datetime:
    # Naive Manila time, as MySQL stores and returns it.
    return now().replace(tzinfo=None)


class PolicyRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def current_rows(self) -> list[CooperativePolicy]:
        """The row in force for every key, ordered by key."""
        at = _now()
        latest = (
            select(
                CooperativePolicy.policy_key,
                func.max(CooperativePolicy.effective_from).label("effective_from"),
            )
            .where(CooperativePolicy.effective_from <= at)
            .group_by(CooperativePolicy.policy_key)
            .subquery()
        )
        result = await self.session.execute(
            select(CooperativePolicy)
            .join(latest, and_(
                CooperativePolicy.policy_key == latest.c.policy_key,
                CooperativePolicy.effective_from == latest.c.effective_from,
            ))
            .order_by(CooperativePolicy.policy_key)
        )
        return list(result.scalars())

    async def all(self) -> dict[str, str]:
        return {p.policy_key: p.policy_value for p in await self.current_rows()}

    async def current(self, key: str) -> CooperativePolicy | None:
        result = await self.session.execute(
            select(CooperativePolicy)
            .where(CooperativePolicy.policy_key == key,
                   CooperativePolicy.effective_from <= _now())
            .order_by(CooperativePolicy.effective_from.desc())
            .limit(1)
        )
        return result.scalar_one_or_none()

    async def history(self, key: str) -> list[CooperativePolicy]:
        """Every value the key has held, newest first."""
        result = await self.session.execute(
            select(CooperativePolicy)
            .where(CooperativePolicy.policy_key == key)
            .order_by(CooperativePolicy.effective_from.desc())
        )
        rows = list(result.scalars())
        if not rows:
            raise NotFoundError(f"Policy '{key}' does not exist.")
        return rows

    async def set(self, key: str, value: str, user_id: str) -> CooperativePolicy:
        """Put a new value in force from now. ValueError if it is not valid.

        The caller commits. Setting the value already in force writes
        nothing: history records changes, not saves.
        """
        current = await self.current(key)
        if current is None:
            raise NotFoundError(f"Policy '{key}' does not exist.")
        value = check_policy_value(key, current.data_type, value)
        if value == current.policy_value:
            return current
        stamp = _now()
        row = CooperativePolicy(
            policy_key=key,
            effective_from=stamp,
            policy_value=value,
            data_type=current.data_type,
            description=current.description,
            updated_by=user_id,
            updated_at=stamp,
        )
        self.session.add(row)
        return row

    async def _raw(self, key: str) -> str:
        policy = await self.current(key)
        if policy is None:
            raise NotFoundError(f"Policy '{key}' is not configured.")
        return policy.policy_value

    async def get_int(self, key: str) -> int:
        return int(await self._raw(key))

    async def get_optional_int(self, key: str) -> int | None:
        """None while the value is unset (`domain.policies.MAY_BE_UNSET`):
        whatever reads it then does nothing."""
        raw = (await self._raw(key)).strip()
        return int(raw) if raw else None

    async def get_bool(self, key: str) -> bool:
        return (await self._raw(key)).strip().lower() in _TRUE

    async def get_decimal(self, key: str) -> Decimal:
        return Decimal(await self._raw(key))

    async def get_str(self, key: str) -> str:
        return await self._raw(key)
