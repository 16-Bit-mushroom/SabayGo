"""What a cooperative policy value may be.

Every key is checked against its declared data_type; a few carry a
tighter rule. A malformed value would otherwise surface much later,
inside a booking or a statement, as an opaque ValueError.
"""

from __future__ import annotations

from decimal import Decimal, InvalidOperation

_BOOL_SPELLINGS = {"true", "false", "1", "0", "yes", "no"}

# Values the paper leaves undecided (brief 4.5): empty means "not set",
# and whatever reads them must then do nothing -- retention deletes no
# evidence while its mode or period is unset.
MAY_BE_UNSET = frozenset({"retention_mode", "retention_days"})

_CHOICES = {"retention_mode": ("fixed_days", "until_settled")}

# Inclusive bounds. Every other number must not be negative: no policy
# has a meaningful negative value.
_BOUNDS: dict[str, tuple[Decimal, Decimal | None]] = {
    "remittance_rate_pct": (Decimal("0.01"), Decimal("100")),
    # 0 would count every phone as silent the moment it reported.
    "heartbeat_gap_seconds": (Decimal(1), None),
    "retention_days": (Decimal(1), None),
}


def check_policy_value(key: str, data_type: str, raw: str) -> str:
    """The value to store, or ValueError with the reason in plain words."""
    value = raw.strip()
    if value == "" and key in MAY_BE_UNSET:
        return value

    number: Decimal | None = None
    if data_type == "int":
        if not value.lstrip("-").isdigit():
            raise ValueError("must be a whole number")
        number = Decimal(value)
    elif data_type == "decimal":
        try:
            number = Decimal(value)
        except InvalidOperation:
            raise ValueError("must be a number") from None
        if not number.is_finite():
            raise ValueError("must be a number")
    elif data_type == "bool" and value.lower() not in _BOOL_SPELLINGS:
        raise ValueError("must be true or false")

    if number is not None:
        low, high = _BOUNDS.get(key, (Decimal(0), None))
        if number < low or (high is not None and number > high):
            upper = f" and at most {high}" if high is not None else ""
            raise ValueError(f"must be at least {low}{upper}")

    choices = _CHOICES.get(key)
    if choices and value not in choices:
        raise ValueError(f"must be one of: {', '.join(choices)}")
    return value
