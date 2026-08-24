"""Domain and application exceptions.

Domain code raises these. The API layer maps them to HTTP status codes in
one place (see app/main.py), so entities never import fastapi -- which is
what keeps the domain layer framework-free and unit-testable without a
running server.
"""


class DomainError(Exception):
    """Base for all business rule violations."""

    status_code = 400
    code = "domain_error"

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


class NotFoundError(DomainError):
    status_code = 404
    code = "not_found"


class ConflictError(DomainError):
    """State prevents the operation (already boarded, already cancelled)."""

    status_code = 409
    code = "conflict"


class NoSeatAvailableError(DomainError):
    """No single seat is free across every leg of the requested segment."""

    status_code = 409
    code = "no_seat_available"


class SeatLockTimeoutError(DomainError):
    """Lost the race for the row lock within innodb_lock_wait_timeout.

    Distinct from NoSeatAvailableError on purpose: a seat may well exist,
    but contention prevented acquiring it. The concurrency experiment
    needs to count these separately from genuine sell-outs.
    """

    status_code = 503
    code = "seat_lock_timeout"


class PolicyViolationError(DomainError):
    """Cooperative policy refuses the action (past cutoff, cap reached)."""

    status_code = 422
    code = "policy_violation"


class AuthenticationError(DomainError):
    status_code = 401
    code = "authentication_failed"


class PermissionDeniedError(DomainError):
    status_code = 403
    code = "permission_denied"


class UpstreamServiceError(DomainError):
    """AI node or payment provider unreachable. Never fabricate a result."""

    status_code = 502
    code = "upstream_unavailable"