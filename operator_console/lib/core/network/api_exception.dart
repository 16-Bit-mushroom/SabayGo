/// API failures, typed.
///
/// The backend returns a consistent `{"error": code, "detail": message}`
/// body and uses status codes meaningfully -- 409 conflict, 422 policy
/// violation, 503 lock contention. Mapping those to distinct exception
/// types lets a screen react correctly instead of showing one generic
/// "something went wrong" for every failure.
library;

sealed class ApiException implements Exception {
  const ApiException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

class NetworkException extends ApiException {
  const NetworkException([
    super.message = 'Cannot reach SabayGo. Check your connection.',
  ]);
}

class RequestTimeoutException extends ApiException {
  const RequestTimeoutException([
    super.message = 'The server took too long to respond. Try again.',
  ]);
}

/// 401 -- missing, expired, or invalid token. Callers should sign out.
class UnauthorizedException extends ApiException {
  const UnauthorizedException(super.message, {super.code})
      : super(statusCode: 401);
}

/// 403 -- authenticated, but not permitted for this role.
class ForbiddenException extends ApiException {
  const ForbiddenException(super.message, {super.code})
      : super(statusCode: 403);
}

class NotFoundException extends ApiException {
  const NotFoundException(super.message, {super.code})
      : super(statusCode: 404);
}

class ConflictException extends ApiException {
  const ConflictException(super.message, {super.code})
      : super(statusCode: 409);
}

class PolicyViolationException extends ApiException {
  const PolicyViolationException(super.message, {super.code})
      : super(statusCode: 422);
}

class ContentionException extends ApiException {
  const ContentionException([
    super.message = 'That record is busy. Trying again.',
  ]) : super(statusCode: 503);
}

/// 502 -- an upstream service (AI node) is unreachable.
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
