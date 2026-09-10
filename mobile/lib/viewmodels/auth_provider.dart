import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../core/storage/token_storage.dart';
import '../data/repositories/auth_repository.dart';

/// Where the app is in the sign-in lifecycle.
///
/// `unknown` exists so the first frame can show a splash rather than
/// flashing the welcome screen before the stored token has been read —
/// a returning user should never see a sign-in screen they do not need.
enum AuthStatus { unknown, signedOut, signedIn }

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    required AuthRepository repository,
    required TokenStorage tokens,
  })  : _repo = repository,
        _tokens = tokens;

  final AuthRepository _repo;
  final TokenStorage _tokens;

  AuthStatus _status = AuthStatus.unknown;
  UserProfile? _profile;
  UserRole? _role;
  bool _busy = false;
  String? _error;

  AuthStatus get status => _status;
  UserProfile? get profile => _profile;
  UserRole? get role => _role ?? _profile?.role;
  bool get isBusy => _busy;
  String? get error => _error;

  /// Restore a session on launch.
  ///
  /// A stored token may have expired while the app was closed, so it is
  /// verified against /auth/me rather than trusted. Trusting it would
  /// mean the first real request fails instead, mid-task.
  Future<void> restore() async {
    if (!await _tokens.hasSession()) {
      _set(AuthStatus.signedOut);
      return;
    }
    try {
      _profile = await _repo.me();
      _role = _profile!.role;
      _set(AuthStatus.signedIn);
    } on ApiException {
      await _tokens.clear();
      _set(AuthStatus.signedOut);
    }
  }

  Future<bool> login({required String email, required String password}) async {
    _begin();
    try {
      final session = await _repo.login(email: email, password: password);
      await _tokens.save(
        accessToken: session.accessToken,
        role: session.role.wire,
        userId: session.userId,
      );
      _role = session.role;
      _profile = await _repo.me();
      _set(AuthStatus.signedIn);
      return true;
    } on ApiException catch (e) {
      // The backend's messages are written for people to read -- "That
      // phone number is already registered" -- so they are shown as-is
      // rather than replaced with a generic string.
      _fail(e.message);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<bool> register({
    required String email,
    required String phoneNumber,
    required String password,
    required String firstName,
    required String lastName,
    String? middleName,
    String? homeAddress,
    String? gender,
    String? emergencyContactName,
    String? emergencyContactRelation,
    String? emergencyContactNumber,
  }) async {
    _begin();
    try {
      final session = await _repo.register(
        email: email,
        phoneNumber: phoneNumber,
        password: password,
        firstName: firstName,
        lastName: lastName,
        middleName: middleName,
        homeAddress: homeAddress,
        gender: gender,
        emergencyContactName: emergencyContactName,
        emergencyContactRelation: emergencyContactRelation,
        emergencyContactNumber: emergencyContactNumber,
      );
      await _tokens.save(
        accessToken: session.accessToken,
        role: session.role.wire,
        userId: session.userId,
      );
      _role = session.role;
      _profile = await _repo.me();
      _set(AuthStatus.signedIn);
      return true;
    } on ApiException catch (e) {
      _fail(e.message);
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _tokens.clear();
    _profile = null;
    _role = null;
    _error = null;
    _set(AuthStatus.signedOut);
  }

  /// Called by ApiClient when any request returns 401, so an expired
  /// token drops the app to sign-in wherever the person happens to be.
  void handleExpiredSession() {
    _tokens.clear();
    _profile = null;
    _role = null;
    _error = 'Your session expired. Please sign in again.';
    _set(AuthStatus.signedOut);
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  // -----------------------------------------------------------------
  void _begin() {
    _busy = true;
    _error = null;
    notifyListeners();
  }

  void _fail(String message) {
    _error = message;
  }

  void _set(AuthStatus status) {
    _status = status;
    notifyListeners();
  }
}
