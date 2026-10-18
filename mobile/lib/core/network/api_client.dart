import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

/// The only place in the app that knows about HTTP.
///
/// Everything above it deals in typed models and typed exceptions.
/// Repositories call methods here; screens never see a status code.
///
/// Also the one place a bearer token is attached, so there is no chance
/// of a screen forgetting to send it, and no chance of it leaking into a
/// request that should not carry it.
class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    http.Client? httpClient,
    String? baseUrl,
  })  : _tokens = tokenStorage,
        _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final TokenStorage _tokens;
  final http.Client _http;
  final String _baseUrl;

  /// Called when a request comes back 401 — the token is dead and the
  /// app should return to the sign-in screen. Set once by the auth
  /// provider so any repository triggers the same sign-out.
  void Function()? onUnauthorized;

  // -----------------------------------------------------------------
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// A binary GET: a payment screenshot. Errors as for JSON calls.
  Future<Uint8List> getBytes(String path) async {
    final token = await _tokens.readAccessToken();
    final request = http.Request('GET', Uri.parse('$_baseUrl$path'))
      ..headers['Accept'] = '*/*';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    final response = await _exchange(request);
    if (response.statusCode >= 200 && response.statusCode < 300) return response.bodyBytes;
    _handle(response); // throws the typed exception for this status
    throw ServerException('Request failed (${response.statusCode}).');
  }

  /// A multipart upload of one file under [field]: a payment screenshot.
  Future<dynamic> upload(
    String path, {
    required String field,
    required Uint8List bytes,
    required String filename,
  }) async {
    final token = await _tokens.readAccessToken();
    final request = http.MultipartRequest('POST', Uri.parse('$_baseUrl$path'))
      ..headers['Accept'] = 'application/json'
      ..files.add(http.MultipartFile.fromBytes(field, bytes, filename: filename));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    return _handle(await _exchange(request));
  }

  Future<http.Response> _exchange(http.BaseRequest request) async {
    try {
      return await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw const RequestTimeoutException();
    } on http.ClientException {
      throw const NetworkException();
    }
  }

  // -----------------------------------------------------------------
  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
    );

    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';

    final token = await _tokens.readAccessToken();
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    try {
      // The timeout covers the whole exchange, body included. It used to
      // wrap only send(), which completes when the *headers* arrive; a
      // response that stalled mid-body (a server reloading under it, a
      // weak link at a terminal) then hung its spinner with no limit.
      final response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(AppConfig.requestTimeout);
      return _handle(response);
    } on TimeoutException {
      throw const RequestTimeoutException();
    } on http.ClientException {
      throw const NetworkException();
    } on FormatException {
      throw const ServerException('The server sent an unreadable response.');
    }
  }

  dynamic _handle(http.Response response) {
    final status = response.statusCode;
    final text = response.body;

    dynamic parsed;
    if (text.isNotEmpty) {
      try {
        parsed = jsonDecode(text);
      } catch (_) {
        parsed = null;
      }
    }

    if (status >= 200 && status < 300) return parsed;

    // The backend's own errors are {error, detail}. FastAPI's built-in
    // validation errors are {detail: [...]}, a different shape, so both
    // are unpacked here rather than in every caller.
    String message = 'Request failed ($status).';
    String? code;

    if (parsed is Map) {
      code = parsed['error'] as String?;
      final detail = parsed['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          message = first['msg'] as String;
        }
      }
    }

    switch (status) {
      case 401:
        onUnauthorized?.call();
        throw UnauthorizedException(message, code: code);
      case 403:
        throw ForbiddenException(message, code: code);
      case 404:
        throw NotFoundException(message, code: code);
      case 409:
        throw ConflictException(message, code: code);
      case 422:
        throw PolicyViolationException(message, code: code);
      case 502:
        throw UpstreamException(message, code: code);
      case 503:
        throw ContentionException(message);
      default:
        throw ServerException(message, status);
    }
  }

  void dispose() => _http.close();
}
