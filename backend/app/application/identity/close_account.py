"""Passenger closes their own account (G.5, Data Privacy Act erasure request).

A soft close (`account_status = 'inactive'`) rather than a row delete: the
user still has FK'd bookings, payments and audit history that other
records (revenue reconciliation, an active trip's manifest) depend on.
`get_current_user` already rejects any non-'active' account, so this also
ends the session without a token blocklist.
"""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy.ext.asyncio import AsyncSession

from app.core import timezone as app_tz
from app.core.exceptions import ConflictError
from app.core.security import verify_password
from app.domain.enums import AccountStatus
from app.infrastructure.models import User


@dataclass(frozen=True)
class CloseAccountCommand:
    user_id: str
    password: str


class CloseAccountUseCase:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def execute(self, cmd: CloseAccountCommand) -> None:
        user = await self.session.get(User, cmd.user_id)
        if user is None:
            raise ConflictError("Account no longer exists.")
        if not verify_password(cmd.password, user.password_hash):
            raise ConflictError("Password is incorrect.")

        user.account_status = AccountStatus.INACTIVE.value
        user.updated_at = app_tz.now()
        await self.session.commit()
