"""Cooperative policy repository.

Every value A2Z has not yet decided is a row here rather than a constant
in code. When the pitch produces answers, the operator console updates
rows -- no migration, no redeploy.
"""

from __future__ import annotations

from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import NotFoundError
from app.infrastructure.models import CooperativePolicy

_TRUE = {"true", "1", "yes", "on"}


class PolicyRepository:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def all(self) -> dict[str, str]:
        result = await self.session.execute(select(CooperativePolicy))
        return {p.policy_key: p.policy_value for p in result.scalars()}

    async def _raw(self, key: str) -> str:
        result = await self.session.execute(
            select(CooperativePolicy).where(CooperativePolicy.policy_key == key)
        )
        policy = result.scalar_one_or_none()
        if policy is None:
            raise NotFoundError(f"Policy '{key}' is not configured.")
        return policy.policy_value

    async def get_int(self, key: str) -> int:
        return int(await self._raw(key))

    async def get_bool(self, key: str) -> bool:
        return (await self._raw(key)).strip().lower() in _TRUE

    async def get_decimal(self, key: str) -> Decimal:
        return Decimal(await self._raw(key))

    async def get_str(self, key: str) -> str:
        return await self._raw(key)