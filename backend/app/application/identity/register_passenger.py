"""Passenger self-registration.

Creates the three rows a passenger needs in one transaction: credentials
(`users`), profile (`passenger_profiles`), and notification preferences
(`passenger_settings`). Staff accounts are NOT created here -- conductors,
drivers and operators are provisioned by an operator, since employment is
a cooperative decision rather than a self-service one.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import datetime, timezone

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.exceptions import ConflictError
from app.core.security import hash_password
from app.domain.enums import AccountStatus, Role
from app.domain.value_objects import Email, PhoneNumber
from app.infrastructure.models import (
    PassengerProfile,
    PassengerSettings,
    User,
)


@dataclass(frozen=True)
class RegisterPassengerCommand:
    email: str
    phone_number: str
    password: str
    first_name: str
    last_name: str
    middle_name: str | None = None
    home_address: str | None = None
    gender: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_relation: str | None = None
    emergency_contact_number: str | None = None


@dataclass(frozen=True)
class RegisterPassengerResult:
    user_id: str
    email: str
    role: Role


class RegisterPassengerUseCase:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def execute(self, cmd: RegisterPassengerCommand) -> RegisterPassengerResult:
        # Value objects validate before anything touches the database.
        email = Email(cmd.email)
        phone = PhoneNumber(cmd.phone_number)
        stored_phone = phone.normalized()

        if len(cmd.password) < 8:
            raise ConflictError("Password must be at least 8 characters.")
        if not cmd.first_name.strip() or not cmd.last_name.strip():
            raise ConflictError("First and last name are required.")

        # Check both uniques up front. The DB constraints are the real
        # guard, but this produces a readable message instead of a raw
        # IntegrityError, and tells the person which field collided.
        existing = await self.session.execute(
            select(User).where(
                or_(User.email == email.value, User.phone_number == stored_phone)
            )
        )
        clash = existing.scalar_one_or_none()
        if clash is not None:
            field = "email address" if clash.email == email.value else "phone number"
            raise ConflictError(f"That {field} is already registered.")

        now = datetime.now(timezone.utc)
        user_id = str(uuid.uuid4())

        self.session.add(
            User(
                user_id=user_id,
                email=email.value,
                phone_number=stored_phone,
                password_hash=hash_password(cmd.password),
                role=Role.PASSENGER.value,
                account_status=AccountStatus.ACTIVE.value,
                created_at=now,
                updated_at=now,
            )
        )
        await self.session.flush()

        self.session.add(
            PassengerProfile(
                user_id=user_id,
                first_name=cmd.first_name.strip(),
                middle_name=(cmd.middle_name or "").strip() or None,
                last_name=cmd.last_name.strip(),
                home_address=cmd.home_address,
                gender=cmd.gender,
                emergency_contact_name=cmd.emergency_contact_name,
                emergency_contact_relation=cmd.emergency_contact_relation,
                emergency_contact_number=(
                    PhoneNumber(cmd.emergency_contact_number).normalized()
                    if cmd.emergency_contact_number
                    else None
                ),
                trust_rating=5.0,
            )
        )
        self.session.add(PassengerSettings(user_id=user_id))

        await self.session.commit()
        return RegisterPassengerResult(
            user_id=user_id, email=email.value, role=Role.PASSENGER
        )
