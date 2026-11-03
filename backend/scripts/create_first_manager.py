#!/usr/bin/env python3
"""Create the cooperative's first Terminal Manager on an empty system.

Staff do not self-register, and only a Terminal Manager creates staff
accounts in the console (Setup > Staff) -- so on day one somebody has to
make the first one. That is the development team's job, once, at
installation; the Terminal Manager then signs in and enters everyone and
everything else through the console.

    cd backend && venv/bin/python scripts/create_first_manager.py \\
        --email maria@a2z.dev --phone 09171234567 --first Maria --last Santos

The password is asked for, never passed on the command line (it would sit
in the shell history). Refused when the email or phone number is taken.
"""
import argparse
import asyncio
import datetime as dt
import getpass
import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import or_, select

from app.core.db import SessionFactory, engine
from app.core.security import hash_password
from app.core.timezone import APP_TZ
from app.domain.enums import Role
from app.domain.value_objects import PhoneNumber
from app.infrastructure.models import StaffProfile, User


async def main(args: argparse.Namespace, password: str) -> int:
    phone = PhoneNumber(args.phone).normalized()
    email = args.email.strip().lower()
    now = dt.datetime.now(APP_TZ).replace(tzinfo=None)
    async with SessionFactory() as session:
        clash = await session.execute(
            select(User).where(or_(User.email == email, User.phone_number == phone))
        )
        if clash.scalar_one_or_none() is not None:
            print("That email address or phone number is already in use.", file=sys.stderr)
            return 1
        user = User(
            user_id=str(uuid.uuid4()), email=email, phone_number=phone,
            password_hash=hash_password(password), role=Role.TERMINAL_MANAGER.value,
            account_status="active", created_at=now, updated_at=now,
        )
        session.add(user)
        await session.flush()
        # Office staff are not on the Dispatchers' roster, so there is no
        # validation to wait for (the console says "Validation: not needed").
        session.add(StaffProfile(
            user_id=user.user_id, first_name=args.first.strip(), last_name=args.last.strip(),
            cooperative_name=args.cooperative, employment_status="active",
            validation_status="pending",
        ))
        await session.commit()
    await engine.dispose()
    print(f"Terminal Manager {args.first} {args.last} <{email}> created. Sign in to the console.")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--email", required=True)
    parser.add_argument("--phone", required=True, help="mobile number, e.g. 09171234567")
    parser.add_argument("--first", required=True, help="first name")
    parser.add_argument("--last", required=True, help="last name")
    parser.add_argument("--cooperative", default="A2Z Transport Cooperative")
    args = parser.parse_args()
    password = getpass.getpass("Password for the new Terminal Manager: ")
    if len(password) < 8 or password != getpass.getpass("Same password again: "):
        sys.exit("Passwords must match and be at least 8 characters.")
    sys.exit(asyncio.run(main(args, password)))
