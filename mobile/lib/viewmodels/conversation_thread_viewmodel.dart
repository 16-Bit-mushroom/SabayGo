import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repositories/messaging_repository.dart';
import '../models/message_model.dart';

/// One thread's messages. No push infrastructure exists yet (that's the
/// FCM roadmap item), so this polls -- same pattern as the ticket screen's
/// booking-status poll, just faster since a chat is actively being read.
class ConversationThreadViewModel extends ChangeNotifier {
  ConversationThreadViewModel(
    this._repo,
    this.conversationId, {
    Duration pollEvery = const Duration(seconds: 4),
  }) {
    load();
    _timer = Timer.periodic(pollEvery, (_) => load());
  }

  final MessagingRepository _repo;
  final String conversationId;
  Timer? _timer;

  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  String? _error;

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get error => _error;

  Future<void> load() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      _messages = await _repo.listMessages(conversationId);
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> send(String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty || _isSending) return;
    _isSending = true;
    notifyListeners();
    try {
      final sent = await _repo.sendMessage(conversationId, trimmed);
      _messages = [..._messages, sent];
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
