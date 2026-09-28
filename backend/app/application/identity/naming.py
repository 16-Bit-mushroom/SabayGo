"""How a person is named in anything another person reads.

Lived in messaging/service.py as a private helper until SOS alerts needed
the same answer. One definition, so a conversation header and an emergency
SMS do not disagree about who someone is.
"""

from __future__ import annotations

from app.infrastructure.models import User


def display_name(user: User) -> str:
    if user.passenger_profile is not None:
        p = user.passenger_profile
        return f"{p.first_name} {p.last_name}".strip()
    if user.staff_profile is not None:
        s = user.staff_profile
        return f"{s.first_name} {s.last_name}".strip()
    return user.email
