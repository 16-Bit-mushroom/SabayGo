/// API failures, typed.
///
/// The backend returns a consistent `{"error": code, "detail": message}`
/// body and uses status codes meaningfully — 409 conflict, 422 policy
/// violation, 503 lock contention. Mapping those to distinct exception
/// types lets a screen react correctly instead of showing one generic
/// "something went wrong" for every failure.
///
/// The `detail` string is written to be shown to a person: "You are
/// 25000m from Ecoland Terminal; check-in requires being within 200m"
/// rather than an error code. So it is surfaced directly rather than
/// replaced with a client-side message.
library;

sealed class ApiException implements Exception {
  const ApiException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

/// No network, DNS failure, or the server is not running.
class NetworkException extends ApiException {
  const NetworkException([
    super.message = 'Cannot reach SabayGo. Check your connection.',
  ]);
}

/// The request was sent but no response arrived in time.
class TimeoutException extends ApiException {
  const TimeoutException([
    super.message = 'The server took too long to respond. Try again.',
  ]);
}

/// 401 — missing, expired, or invalid token. Callers should sign out.
class UnauthorizedException extends ApiException {
  const UnauthorizedException(super.message, {super.code})
      : super(statusCode: 401);
}

/// 403 — authenticated, but not permitted. A conductor scanning a trip
/// they are not rostered to lands here.
class ForbiddenException extends ApiException {
  const ForbiddenException(super.message, {super.code})
      : super(statusCode: 403);
}

class NotFoundException extends ApiException {
  const NotFoundException(super.message, {super.code})
      : super(statusCode: 404);
}

/// 409 — the request is well formed but the state refuses it: already
/// scanned, already cancelled, trip departed.
class ConflictException extends ApiException {
  const ConflictException(super.message, {super.code})
      : super(statusCode: 409);
}

/// 422 — a cooperative policy refuses it: past the reschedule cutoff,
/// outside the check-in radius, advance limit reached. Distinct from a
/// conflict because the wording tells the person what rule applies.
class PolicyViolationException extends ApiException {
  const PolicyViolationException(super.message, {super.code})
      : super(statusCode: 422);
}

/// 503 — lost the race for a seat lock. Worth retrying automatically;
/// a sold-out trip (409) is not.
class ContentionException extends ApiException {
  const ContentionException([
    super.message = 'The seat map is busy. Trying again.',
  ]) : super(statusCode: 503);
}

/// 502 — an upstream service (AI node, payment provider) is unreachable.
class UpstreamException extends ApiException {
  const UpstreamException(super.message, {super.code})
      : super(statusCode: 502);
}

class ServerException extends ApiException {
  const ServerException([
    super.message = 'Something went wrong on our side.',
    int? status,
  ]) : super(statusCode: status ?? 500);
}
