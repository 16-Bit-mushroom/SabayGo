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

  /// Called when a request comes back 401 -- the token is dead and the
  /// console should return to the sign-in screen.
  void Function()? onUnauthorized;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send('POST', path, body: body, query: query);

  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  Future<dynamic> patch(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send('PATCH', path, body: body, query: query);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// A binary GET -- for the spreadsheet export (G.1). Errors are surfaced
  /// exactly as for JSON calls; a 2xx returns the raw body.
  Future<Uint8List> getBytes(String path, {Map<String, dynamic>? query}) async {
    final request = await _prepare('GET', path, query: query, accept: '*/*');
    try {
      final streamed = await _http.send(request).timeout(AppConfig.requestTimeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
      _handle(response); // throws the typed exception for this status
      throw ServerException('Request failed (${response.statusCode}).');
    } on TimeoutException {
      throw const RequestTimeoutException();
    } on http.ClientException {
      throw const NetworkException();
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    final request = await _prepare(method, path, query: query, body: body);
    try {
      final streamed = await _http.send(request).timeout(AppConfig.requestTimeout);
      final response = await http.Response.fromStream(streamed);
      return _handle(response);
    } on TimeoutException {
      throw const RequestTimeoutException();
    } on http.ClientException {
      throw const NetworkException();
    } on FormatException {
      throw const ServerException('The server sent an unreadable response.');
    }
  }

  Future<http.Request> _prepare(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    String accept = 'application/json',
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
    );

    final headers = <String, String>{'Accept': accept};
    if (body != null) headers['Content-Type'] = 'application/json';

    final token = await _tokens.readAccessToken();
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    return request;
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
