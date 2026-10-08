import 'package:flutter/foundation.dart';

import '../core/network/api_exception.dart';
import '../core/storage/token_storage.dart';
import '../data/repositories/auth_repository.dart';

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
  bool _busy = false;
  String? _error;

  AuthStatus get status => _status;
  UserProfile? get profile => _profile;
  bool get isBusy => _busy;
  String? get error => _error;

  Future<void> restore() async {
    try {
      if (!await _tokens.hasSession()) {
        _set(AuthStatus.signedOut);
        return;
      }
      _profile = await _repo.me();
      _set(AuthStatus.signedIn);
    } catch (_) {
      // Covers both an expired token (ApiException) and a storage read
      // that fails outright -- e.g. a browser with storage access
      // blocked. Either way there is no usable session to restore.
      await _tokens.clear();
      _set(AuthStatus.signedOut);
    }
  }

  /// Signs in, but only completes for `coop_admin`. This console has no
  /// use for any other role, and letting one further in would just mean
  /// failing later on every screen instead of at the door.
  Future<bool> login({required String email, required String password}) async {
    _begin();
    try {
      final session = await _repo.login(email: email, password: password);
      if (session.role != UserRole.coopAdmin) {
        _fail('This console is for cooperative office staff only.');
        return false;
      }
      await _tokens.save(
        accessToken: session.accessToken,
        role: session.role.wire,
        userId: session.userId,
      );
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

  /// Saves the signed-in user's own profile. Errors propagate as
  /// [ApiException] so the dialog can show the server's sentence beside
  /// the field it is about.
  Future<void> updateProfile({
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? currentPassword,
    String? newPassword,
  }) async {
    _profile = await _repo.updateMe(
      firstName: firstName,
      lastName: lastName,
      phoneNumber: phoneNumber,
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    notifyListeners();
  }

  Future<void> signOut() async {
    await _tokens.clear();
    _profile = null;
    _error = null;
    _set(AuthStatus.signedOut);
  }

  void handleExpiredSession() {
    _tokens.clear();
    _profile = null;
    _error = 'Your session expired. Please sign in again.';
    _set(AuthStatus.signedOut);
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

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
