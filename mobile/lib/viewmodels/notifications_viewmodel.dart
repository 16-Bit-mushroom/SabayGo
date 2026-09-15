import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repositories/notification_repository.dart';
import '../models/notification_model.dart';

/// Notifications for the signed-in user, from `GET /notifications`.
///
/// Pass [pollEvery] to keep an unread badge current (the conductor's app
/// bar does this); the passenger tab loads on open and on pull-to-refresh.
class NotificationsViewModel extends ChangeNotifier {
  NotificationsViewModel(this._repo, {Duration? pollEvery}) {
    load();
    if (pollEvery != null) {
      _timer = Timer.periodic(pollEvery, (_) => load());
    }
  }

  final NotificationRepository _repo;
  Timer? _timer;

  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;
  String _searchQuery = '';
  bool _isLoading = false;
  String? _error;

  // --- Derived State ---
  List<NotificationModel> get filteredNotifications {
    if (_searchQuery.isEmpty) return _notifications;
    final query = _searchQuery.toLowerCase();
    return _notifications.where((n) {
      return n.title.toLowerCase().contains(query) ||
          n.message.toLowerCase().contains(query);
    }).toList();
  }

  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // --- Actions ---
  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      final page = await _repo.list();
      _notifications = page.items;
      _unreadCount = page.unreadCount;
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> markAsRead(String id) async {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index == -1 || _notifications[index].isRead) return;
    // Optimistic: the badge drops before the round trip completes.
    _notifications[index] = _notifications[index].copyWith(isRead: true);
    _unreadCount = (_unreadCount - 1).clamp(0, 1 << 30);
    notifyListeners();
    try {
      await _repo.markRead(id);
    } catch (_) {
      await load();
    }
  }

  Future<void> markAllRead() async {
    _notifications = [for (final n in _notifications) n.copyWith(isRead: true)];
    _unreadCount = 0;
    notifyListeners();
    try {
      await _repo.markAllRead();
    } catch (_) {
      await load();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
