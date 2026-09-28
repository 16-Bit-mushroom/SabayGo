import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/messaging_repository.dart';

/// Backs the console's Messages module: the conversation list (the
/// office's shared inbox) plus whichever thread is currently open.
///
/// Polling, not push, same rationale as NotificationProvider: FCM is
/// deferred (Tier 3) and the console is a desk browser with a steady
/// connection.
class MessagingProvider extends ChangeNotifier {
  MessagingProvider(this._repo) {
    refreshConversations();
    _listTimer = Timer.periodic(const Duration(seconds: 15), (_) => refreshConversations());
  }

  final MessagingRepository _repo;
  Timer? _listTimer;
  Timer? _threadTimer;

  List<ConsoleConversation> _conversations = const [];
  bool _loadingList = false;
  String? _listError;

  String? _openConversationId;
  List<ConsoleMessage> _messages = const [];
  bool _loadingThread = false;
  String? _threadError;
  bool _sending = false;

  List<ConsoleConversation> get conversations => _conversations;
  int get totalUnread => _conversations.fold(0, (sum, c) => sum + c.unreadCount);
  bool get isLoadingList => _loadingList;
  String? get listError => _listError;

  String? get openConversationId => _openConversationId;
  List<ConsoleMessage> get messages => _messages;
  bool get isLoadingThread => _loadingThread;
  String? get threadError => _threadError;
  bool get isSending => _sending;

  Future<void> refreshConversations() async {
    if (_loadingList) return;
    _loadingList = true;
    notifyListeners();
    try {
      _conversations = await _repo.listConversations();
      _listError = null;
    } catch (e) {
      _listError = e.toString();
    } finally {
      _loadingList = false;
      notifyListeners();
    }
  }

  void openConversation(String conversationId) {
    if (_openConversationId == conversationId) return;
    _openConversationId = conversationId;
    _messages = const [];
    _threadTimer?.cancel();
    _refreshThread();
    _threadTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refreshThread());
    notifyListeners();
  }

  Future<void> _refreshThread() async {
    final id = _openConversationId;
    if (id == null || _loadingThread) return;
    _loadingThread = true;
    notifyListeners();
    try {
      _messages = await _repo.listMessages(id);
      _threadError = null;
      // The office just read this thread; drop its badge locally rather
      // than waiting for the next 15s list poll.
      _conversations = [
        for (final c in _conversations) c.conversationId == id ? _withZeroUnread(c) : c,
      ];
    } catch (e) {
      _threadError = e.toString();
    } finally {
      _loadingThread = false;
      notifyListeners();
    }
  }

  ConsoleConversation _withZeroUnread(ConsoleConversation c) => ConsoleConversation(
        conversationId: c.conversationId,
        kind: c.kind,
        peerUserId: c.peerUserId,
        peerRole: c.peerRole,
        peerName: c.peerName,
        lastMessage: c.lastMessage,
        lastMessageAt: c.lastMessageAt,
        unreadCount: 0,
        createdAt: c.createdAt,
      );

  Future<void> send(String body) async {
    final id = _openConversationId;
    final trimmed = body.trim();
    if (id == null || trimmed.isEmpty || _sending) return;
    _sending = true;
    notifyListeners();
    try {
      final sent = await _repo.sendMessage(id, trimmed);
      _messages = [..._messages, sent];
      _threadError = null;
    } catch (e) {
      _threadError = e.toString();
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _listTimer?.cancel();
    _threadTimer?.cancel();
    super.dispose();
  }
}
