"""Value objects.

PhoneNumber, EmergencyContact and LicenseNumber are carried over from the
Sprint 1 domain model -- the validation rules were correct and are
domain-independent. Email's .edu.ph restriction was dropped: SabayGo
serves cooperative staff and the general commuting public, not a campus.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from decimal import Decimal

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$")


@dataclass(frozen=True)
class Email:
    value: str

    def __post_init__(self) -> None:
        cleaned = self.value.strip().lower()
        if not EMAIL_RE.match(cleaned):
            raise ValueError("Must be a valid email address.")
        object.__setattr__(self, "value", cleaned)

    def __str__(self) -> str:
        return self.value


@dataclass(frozen=True)
class PhoneNumber:
    """Philippine mobile number. Salvaged unchanged from Sprint 1."""

    value: str

    def __post_init__(self) -> None:
        object.__setattr__(self, "value", self.value.strip().replace(" ", ""))
        is_standard = self.value.startswith("09") and len(self.value) == 11
        is_intl = self.value.startswith("+639") and len(self.value) == 13
        if not (is_standard or is_intl):
            raise ValueError(
                "Must be a valid Philippine mobile number (e.g. 09123456789)."
            )

    def normalized(self) -> str:
        """Canonical +639XXXXXXXXX form for storage and SMS delivery."""
        return "+63" + self.value[1:] if self.value.startswith("09") else self.value


@dataclass(frozen=True)
class LicenseNumber:
    """LTO driver's licence. Salvaged unchanged from Sprint 1."""

    value: str

    def __post_init__(self) -> None:
        cleaned = self.value.replace("-", "").replace(" ", "").upper()
        if not re.match(r"^[A-Z]\d{10}$", cleaned):
            raise ValueError("Must be a valid Philippine driver's license format.")
        object.__setattr__(self, "value", cleaned)


@dataclass(frozen=True)
class EmergencyContact:
    name: str
    phone: PhoneNumber

    def __post_init__(self) -> None:
        if not self.name.strip():
            raise ValueError("Emergency contact name cannot be empty.")


@dataclass(frozen=True)
class Segment:
    """A boarding/alighting pair along a route's ordered stop sequence.

    This is the value object the whole booking model turns on. A passenger
    does not occupy "a seat on a trip" -- they occupy one seat across a
    contiguous span of legs, which is what allows the same physical seat
    to be sold twice on non-overlapping portions of the same trip.
    """

    boarding_stop: int
    alighting_stop: int

    def __post_init__(self) -> None:
        if self.boarding_stop < 1:
            raise ValueError("Stop sequence is 1-based.")
        if self.alighting_stop <= self.boarding_stop:
            raise ValueError("Alighting stop must come after the boarding stop.")

    @property
    def leg_range(self) -> tuple[int, int]:
        """Inclusive leg_sequence bounds this segment consumes.

        Leg k spans stop k -> k+1, so boarding at 2 and alighting at 4
        consumes legs 2 and 3.
        """
        return self.boarding_stop, self.alighting_stop - 1

    @property
    def leg_count(self) -> int:
        lo, hi = self.leg_range
        return hi - lo + 1

    def overlaps(self, other: Segment) -> bool:
        return (
            self.boarding_stop < other.alighting_stop
            and other.boarding_stop < self.alighting_stop
        )


@dataclass(frozen=True)
class Fare:
    amount: Decimal

    def __post_init__(self) -> None:
        if self.amount < 0:
            raise ValueError("Fare cannot be negative.")