import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/notification_repository.dart';

/// Polls the signed-in user's notifications while the shell is mounted.
///
/// Polling, not push: the roadmap defers FCM (Tier 3) and the console is a
/// desk browser with a steady connection, so a 30-second refresh is enough
/// for a variance alert to reach the office while the van is still on the
/// leg it was flagged on.
class NotificationProvider extends ChangeNotifier {
  NotificationProvider(this._repo, {this.interval = const Duration(seconds: 30)}) {
    refresh();
    _timer = Timer.periodic(interval, (_) => refresh());
  }

  final NotificationRepository _repo;
  final Duration interval;
  Timer? _timer;

  List<AppNotification> _items = const [];
  int _unread = 0;
  bool _loading = false;
  String? _error;

  List<AppNotification> get items => _items;
  int get unreadCount => _unread;
  bool get isLoading => _loading;
  String? get error => _error;

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      final page = await _repo.list();
      _items = page.items;
      _unread = page.unreadCount;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(AppNotification n) async {
    if (n.isRead) return;
    // Optimistic: the badge drops before the round trip completes.
    _items = [for (final i in _items) i.notificationId == n.notificationId ? i.copyWith(isRead: true) : i];
    _unread = (_unread - 1).clamp(0, 1 << 30);
    notifyListeners();
    try {
      await _repo.markRead(n.notificationId);
    } catch (_) {
      await refresh();
    }
  }

  Future<void> markAllRead() async {
    _items = [for (final i in _items) i.copyWith(isRead: true)];
    _unread = 0;
    notifyListeners();
    try {
      await _repo.markAllRead();
    } catch (_) {
      await refresh();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
