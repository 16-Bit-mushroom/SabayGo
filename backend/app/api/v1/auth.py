"""Authentication endpoints."""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter
from pydantic import BaseModel, EmailStr
from sqlalchemy import select

from app.api.v1.deps import CurrentUser, SessionDep
from app.core.exceptions import AuthenticationError
from app.core.security import create_access_token, verify_password
from app.infrastructure.models import User

router = APIRouter(prefix="/auth", tags=["auth"])


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    role: str
    user_id: str


class MeResponse(BaseModel):
    user_id: str
    email: str
    role: str
    account_status: str
    display_name: str | None = None


@router.post("/login", response_model=TokenResponse)
async def login(payload: LoginRequest, session: SessionDep) -> TokenResponse:
    result = await session.execute(
        select(User).where(User.email == payload.email.lower())
    )
    user = result.scalar_one_or_none()

    # Same message and roughly the same work either way, so the response
    # does not reveal whether an address is registered.
    if user is None or not verify_password(payload.password, user.password_hash):
        raise AuthenticationError("Incorrect email or password.")
    if user.account_status != "active":
        raise AuthenticationError(f"Account is {user.account_status}.")

    user.last_login_at = datetime.now(timezone.utc)
    await session.commit()

    return TokenResponse(
        access_token=create_access_token(user.user_id, user.role),
        role=user.role,
        user_id=user.user_id,
    )


@router.get("/me", response_model=MeResponse)
async def me(user: CurrentUser) -> MeResponse:
    profile = user.passenger_profile or user.staff_profile
    name = f"{profile.first_name} {profile.last_name}" if profile else None
    return MeResponse(
        user_id=user.user_id,
        email=user.email,
        role=user.role,
        account_status=user.account_status,
        display_name=name,
    )