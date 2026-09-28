/// Mirrors `GET /conversations` — one row per thread, peer already resolved
/// server-side (an "office" thread shows "Cooperative Office" to anyone
/// but the coop_admin reading it).
class Conversation {
  Conversation({
    required this.id,
    required this.kind,
    required this.tripId,
    required this.peerUserId,
    required this.peerRole,
    required this.peerName,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.createdAt,
  });

  final String id;
  final String kind; // passenger_conductor | conductor_driver | office
  final String? tripId;
  final String? peerUserId;
  final String peerRole;
  final String peerName;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final DateTime createdAt;

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['conversation_id'] as String,
        kind: json['kind'] as String,
        tripId: json['trip_id'] as String?,
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

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderRole,
    required this.body,
    required this.isMine,
    required this.readAt,
    required this.createdAt,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String senderRole;
  final String body;
  final bool isMine;
  final DateTime? readAt;
  final DateTime createdAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['message_id'] as String,
        conversationId: json['conversation_id'] as String,
        senderId: json['sender_id'] as String,
        senderRole: json['sender_role'] as String,
        body: json['body'] as String,
        isMine: json['is_mine'] as bool,
        readAt: json['read_at'] != null ? DateTime.parse(json['read_at'] as String) : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

/// One eligible person (or "the office") a new conversation can be
/// started with, from `GET /conversations/contacts`.
class MessageContact {
  MessageContact({
    required this.peerUserId,
    required this.peerRole,
    required this.peerName,
    required this.tripId,
    required this.tripLabel,
  });

  final String? peerUserId; // null means "the office" (shared inbox)
  final String peerRole;
  final String peerName;
  final String? tripId;
  final String? tripLabel;

  factory MessageContact.fromJson(Map<String, dynamic> json) => MessageContact(
        peerUserId: json['peer_user_id'] as String?,
        peerRole: json['peer_role'] as String,
        peerName: json['peer_name'] as String,
        tripId: json['trip_id'] as String?,
        tripLabel: json['trip_label'] as String?,
      );
}
