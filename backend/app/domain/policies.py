"""What a cooperative policy value may be.

Every key is checked against its declared data_type; a few carry a
tighter rule. A malformed value would otherwise surface much later,
inside a booking or a statement, as an opaque ValueError.
"""

from __future__ import annotations

from decimal import Decimal, InvalidOperation

_BOOL_SPELLINGS = {"true", "false", "1", "0", "yes", "no"}

# Values that wait on a site survey or on A2Z (brief 4.2 rule 8, 2.6):
# empty means "not set", and whatever reads them must then do nothing --
# no GPS departure, no home pickup offered.
MAY_BE_UNSET = frozenset({"depart_zone_radius_m", "depart_readings", "home_pickup_max_route_m"})

# Inclusive bounds. Every other number must not be negative: no policy
# has a meaningful negative value.
_BOUNDS: dict[str, tuple[Decimal, Decimal | None]] = {
    "remittance_rate_pct": (Decimal("0.01"), Decimal("100")),
    # 0 would count every phone as silent the moment it reported.
    "heartbeat_gap_seconds": (Decimal(1), None),
    "retention_days": (Decimal(1), None),
    "match_window_seconds": (Decimal(1), None),
    "depart_zone_radius_m": (Decimal(1), None),
    "depart_readings": (Decimal(1), None),
    "home_pickup_max_route_m": (Decimal(1), None),
    "chat_image_max_kb": (Decimal(1), None),
    "chat_image_retention_days": (Decimal(1), None),
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
    return value
