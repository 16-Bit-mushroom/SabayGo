"""Shared API dependencies."""

from __future__ import annotations

from typing import Annotated

from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db import get_session
from app.core.exceptions import AuthenticationError, PermissionDeniedError
from app.core.security import decode_access_token
from app.domain.enums import Role
from app.infrastructure.models import User

bearer = HTTPBearer(auto_error=False)

SessionDep = Annotated[AsyncSession, Depends(get_session)]


async def get_current_user(
    session: SessionDep,
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)] = None,
) -> User:
    if creds is None:
        raise AuthenticationError("Missing bearer token.")
    payload = decode_access_token(creds.credentials)
    user = await session.get(User, payload.get("sub"))
    if user is None:
        raise AuthenticationError("User no longer exists.")
    if user.account_status != "active":
        raise PermissionDeniedError(f"Account is {user.account_status}.")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def require_roles(*roles: Role):
    """Route guard: 403 unless the caller holds one of these roles."""

    async def _guard(user: CurrentUser) -> User:
        if user.role not in {r.value for r in roles}:
            raise PermissionDeniedError(
                f"This action requires: {', '.join(r.value for r in roles)}."
            )
        return user

    return _guard


# The office. Deciding what is owed, setting rules and validating records
# are the Terminal Manager's alone; the Cashier joins only where the
# brief's permission table (section 3) gives both -- separation of duties.
MANAGER = require_roles(Role.TERMINAL_MANAGER, Role.ADMIN)
OFFICE = require_roles(Role.TERMINAL_MANAGER, Role.CASHIER, Role.ADMIN)
# Receiving A2Z's 15 % and recording it: the Cashier's alone, so the person
# who decides what is owed is not the one who records it (brief 3).
CASHIER = require_roles(Role.CASHIER, Role.ADMIN)