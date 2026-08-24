"""Authentication endpoints."""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select

from app.api.v1.deps import CurrentUser, SessionDep
from app.application.identity.register_passenger import (
    RegisterPassengerCommand,
    RegisterPassengerUseCase,
)
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


class RegisterRequest(BaseModel):
    email: EmailStr
    phone_number: str
    password: str = Field(min_length=8)
    first_name: str
    last_name: str
    middle_name: str | None = None
    home_address: str | None = None
    gender: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_relation: str | None = None
    emergency_contact_number: str | None = None


@router.post("/register", response_model=TokenResponse, status_code=201)
async def register(payload: RegisterRequest, session: SessionDep) -> TokenResponse:
    """Passenger self-registration.

    Returns a token directly so the app does not have to bounce the person
    to a login screen immediately after signing up.

    Staff accounts are deliberately NOT creatable here -- conductors,
    drivers and operators are provisioned by an operator, because
    employment is a cooperative decision, not self-service.
    """
    result = await RegisterPassengerUseCase(session).execute(
        RegisterPassengerCommand(
            email=payload.email,
            phone_number=payload.phone_number,
            password=payload.password,
            first_name=payload.first_name,
            last_name=payload.last_name,
            middle_name=payload.middle_name,
            home_address=payload.home_address,
            gender=payload.gender,
            emergency_contact_name=payload.emergency_contact_name,
            emergency_contact_relation=payload.emergency_contact_relation,
            emergency_contact_number=payload.emergency_contact_number,
        )
    )
    return TokenResponse(
        access_token=create_access_token(result.user_id, result.role.value),
        role=result.role.value,
        user_id=result.user_id,
    )


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