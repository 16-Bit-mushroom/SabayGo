"""Passenger self-service profile edit (G.4).

Email is intentionally not editable here -- changing it would need
re-verification, which is its own feature. Name, phone and password are.
"""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import timezone as app_tz
from app.core.exceptions import ConflictError
from app.core.security import hash_password, verify_password
from app.domain.value_objects import PhoneNumber
from app.infrastructure.models import User


@dataclass(frozen=True)
class UpdateProfileCommand:
    user_id: str
    first_name: str | None = None
    last_name: str | None = None
    middle_name: str | None = None
    phone_number: str | None = None
    home_address: str | None = None
    gender: str | None = None
    emergency_contact_name: str | None = None
    emergency_contact_relation: str | None = None
    emergency_contact_number: str | None = None
    current_password: str | None = None
    new_password: str | None = None


class UpdateProfileUseCase:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def execute(self, cmd: UpdateProfileCommand) -> User:
        user = await self.session.get(User, cmd.user_id)
        if user is None:
            raise ConflictError("Account no longer exists.")
        profile = user.passenger_profile
        # Office staff and crew edit their name too; the passenger-only
        # fields below have no columns on a staff profile.
        named = profile or user.staff_profile

        if cmd.new_password:
            if not cmd.current_password or not verify_password(
                cmd.current_password, user.password_hash
            ):
                # Not AuthenticationError (401): the mobile ApiClient treats
                # any 401 as an expired session and force-signs-out, which
                # would be a strange reaction to a typo'd current password.
                raise ConflictError("Current password is incorrect.")
            if len(cmd.new_password) < 8:
                raise ConflictError("Password must be at least 8 characters.")
            user.password_hash = hash_password(cmd.new_password)

        if cmd.phone_number:
            stored_phone = PhoneNumber(cmd.phone_number).normalized()
            if stored_phone != user.phone_number:
                clash = await self.session.execute(
                    select(User).where(
                        User.phone_number == stored_phone, User.user_id != user.user_id
                    )
                )
                if clash.scalar_one_or_none() is not None:
                    raise ConflictError("That phone number is already registered.")
                user.phone_number = stored_phone

        if named is not None:
            if cmd.first_name and cmd.first_name.strip():
                named.first_name = cmd.first_name.strip()
            if cmd.last_name and cmd.last_name.strip():
                named.last_name = cmd.last_name.strip()
            if cmd.middle_name is not None:
                named.middle_name = cmd.middle_name.strip() or None

        if profile is not None:
            if cmd.home_address is not None:
                profile.home_address = cmd.home_address.strip() or None
            if cmd.gender is not None:
                profile.gender = cmd.gender or None
            if cmd.emergency_contact_name is not None:
                profile.emergency_contact_name = cmd.emergency_contact_name.strip() or None
            if cmd.emergency_contact_relation is not None:
                profile.emergency_contact_relation = (
                    cmd.emergency_contact_relation.strip() or None
                )
            if cmd.emergency_contact_number is not None:
                profile.emergency_contact_number = (
                    PhoneNumber(cmd.emergency_contact_number).normalized()
                    if cmd.emergency_contact_number
                    else None
                )

        user.updated_at = app_tz.now()
        await self.session.commit()
        await self.session.refresh(user)
        return user
