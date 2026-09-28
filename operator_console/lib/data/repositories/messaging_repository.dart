import '../../core/network/api_client.dart';

/// Mirrors `GET /conversations`. For the office kind (the only kind the
/// console ever sees -- coop_admin is only ever a participant in an
/// "office" thread), the peer is the specific passenger/conductor/driver
/// on the other end.
class ConsoleConversation {
  const ConsoleConversation({
    required this.conversationId,
    required this.kind,
    required this.peerUserId,
    required this.peerRole,
    required this.peerName,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.createdAt,
  });

  final String conversationId;
  final String kind;
  final String? peerUserId;
  final String peerRole;
  final String peerName;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime createdAt;

  factory ConsoleConversation.fromJson(Map<String, dynamic> json) => ConsoleConversation(
        conversationId: json['conversation_id'] as String,
        kind: json['kind'] as String,
        peerUserId: json['peer_user_id'] as String?,
        peerRole: json['peer_role'] as String,
        peerName: json['peer_name'] as String,
        lastMessage: json['last_message'] as String?,
        lastMessageAt: json['last_message_at'] != null
            ? DateTime.parse(json['last_message_at'] as String)
            : null,
        unreadCount: json['unread_count'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class ConsoleMessage {
  const ConsoleMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderRole,
    required this.body,
    required this.isMine,
    required this.createdAt,
  });

  final String messageId;
  final String conversationId;
  final String senderRole;
  final String body;
  final bool isMine;
  final DateTime createdAt;

  factory ConsoleMessage.fromJson(Map<String, dynamic> json) => ConsoleMessage(
        messageId: json['message_id'] as String,
        conversationId: json['conversation_id'] as String,
        senderRole: json['sender_role'] as String,
        body: json['body'] as String,
        isMine: json['is_mine'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class MessagingRepository {
  MessagingRepository(this._api);
  final ApiClient _api;

  Future<List<ConsoleConversation>> listConversations() async {
    final json = await _api.get('/conversations') as List;
    return json.map((e) => ConsoleConversation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ConsoleMessage>> listMessages(String conversationId) async {
    final json = await _api.get('/conversations/$conversationId/messages') as List;
    return json.map((e) => ConsoleMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ConsoleMessage> sendMessage(String conversationId, String body) async {
    final json = await _api.post('/conversations/$conversationId/messages', body: {'body': body});
    return ConsoleMessage.fromJson(json as Map<String, dynamic>);
  }
}
