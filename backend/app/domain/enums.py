"""Domain enums.

Values match the MySQL ENUM definitions exactly. If you change one here,
change the migration too -- a mismatch fails at INSERT time with a data
truncation error that is unpleasant to trace.
"""

from enum import Enum


class Role(str, Enum):
    """Who can sign in. The operator (van owner, who drives) is not here:
    a roster row in `operators`, no login."""

    PASSENGER = "passenger"
    DISPATCHER = "dispatcher"
    TERMINAL_MANAGER = "terminal_manager"
    CASHIER = "cashier"
    ADMIN = "admin"


class AccountStatus(str, Enum):
    ACTIVE = "active"
    SUSPENDED = "suspended"
    INACTIVE = "inactive"


class TripStatus(str, Enum):
    SCHEDULED = "scheduled"
    BOARDING = "boarding"
    DEPARTED = "departed"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class StartMode(str, Enum):
    """How a trip was started (brief 4.2 rules 5 and 7; migration 019)."""

    MANUAL = "manual"
    AUTO_ASSIGNED = "auto_assigned"
    AUTO_DETECTED = "auto_detected"


class StartReview(str, Enum):
    """An automatic start is held off the statement until reviewed."""

    NOT_REQUIRED = "not_required"
    PENDING = "pending"
    REVIEWED = "reviewed"


class TripAuditStatus(str, Enum):
    AUDITED = "audited"
    UNAUDITED = "unaudited"


class UnauditedReason(str, Enum):
    NO_PHONE = "no_phone"
    SILENT_AT_START = "silent_at_start"
    LOST_EN_ROUTE = "lost_en_route"
    LENS_BLOCKED = "lens_blocked"


class DepartureSource(str, Enum):
    """Who tapped Depart, or 'gps' when nobody did (brief 4.2 rule 7)."""

    DISPATCHER = "dispatcher"
    STAFF = "staff"
    GPS = "gps"


class BookingStatus(str, Enum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    CHECKED_IN = "checked_in"
    BOARDED = "boarded"
    COMPLETED = "completed"
    CANCELLED = "cancelled"
    NO_SHOW = "no_show"
    RESCHEDULED = "rescheduled"


class BookingType(str, Enum):
    APP = "app"
    WALK_IN = "walk_in"
    DRIVER_ISSUED = "driver_issued"


class SeatStatus(str, Enum):
    AVAILABLE = "available"
    HELD = "held"
    BOOKED = "booked"
    BLOCKED = "blocked"


class PaymentStatus(str, Enum):
    PENDING = "pending"
    PAID = "paid"
    FAILED = "failed"
    REFUNDED = "refunded"
    VOIDED = "voided"


class AuditResolution(str, Enum):
    RECONCILED = "reconciled"
    PENDING = "pending"
    RESOLVED = "resolved"
    IGNORED = "ignored"
    FAILED = "failed"


class AuditTrigger(str, Enum):
    """What caused a cabin capture -- the audit's provenance.

    MANUAL is a person asking. The rest are system events (2.3.5's
    "triggered by door closures or specific GPS nodes"), and they are the
    ones that carry the leakage claim: a check the crew initiates is a
    check the crew can decline to initiate. Because of that, only the
    server may label an audit automatic; the manual endpoint does not
    accept this value from its caller.

    Mirrors the ENUM in migration 006. SCHEDULED is declared there and is
    not yet produced by anything.
    """

    MANUAL = "manual"
    DOOR_CLOSE = "door_close"
    GPS_NODE = "gps_node"
    SCHEDULED = "scheduled"

    @property
    def is_automatic(self) -> bool:
        return self is not AuditTrigger.MANUAL


class SosCategory(str, Enum):
    MEDICAL = "medical"
    ACCIDENT = "accident"
    SECURITY = "security"
    BREAKDOWN = "breakdown"
    OTHER = "other"


class SosStatus(str, Enum):
    OPEN = "open"
    ACKNOWLEDGED = "acknowledged"
    RESOLVED = "resolved"
