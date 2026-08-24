"""Domain enums.

Values match the MySQL ENUM definitions exactly. If you change one here,
change the migration too -- a mismatch fails at INSERT time with a data
truncation error that is unpleasant to trace.
"""

from enum import Enum


class Role(str, Enum):
    PASSENGER = "passenger"
    CONDUCTOR = "conductor"
    DRIVER = "driver"
    OPERATOR = "operator"
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