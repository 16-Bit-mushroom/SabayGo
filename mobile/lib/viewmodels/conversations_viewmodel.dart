import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repositories/messaging_repository.dart';
import '../models/message_model.dart';

/// Conversation list for the signed-in user. Pass [pollEvery] to keep an
/// unread badge current (the conductor/driver app bar does this), same
/// shape as NotificationsViewModel.
class ConversationsViewModel extends ChangeNotifier {
  ConversationsViewModel(this._repo, {Duration? pollEvery}) {
    load();
    if (pollEvery != null) {
      _timer = Timer.periodic(pollEvery, (_) => load());
    }
  }

  final MessagingRepository _repo;
  Timer? _timer;

  List<Conversation> _conversations = [];
  bool _isLoading = false;
  String? _error;

  List<Conversation> get conversations => _conversations;
  int get unreadCount => _conversations.fold(0, (sum, c) => sum + c.unreadCount);
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      _conversations = await _repo.listConversations();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
