import '../../core/network/api_client.dart';

class AppNotification {
  const AppNotification({
    required this.notificationId,
    required this.type,
    required this.title,
    required this.message,
    required this.relatedEntityType,
    required this.relatedEntityId,
    required this.isRead,
    required this.createdAt,
  });

  final String notificationId;
  final String type;
  final String title;
  final String message;
  final String? relatedEntityType;
  final String? relatedEntityId;
  final bool isRead;
  final DateTime createdAt;

  bool get isVarianceAlert => type == 'variance_alert';

  AppNotification copyWith({bool? isRead}) => AppNotification(
        notificationId: notificationId,
        type: type,
        title: title,
        message: message,
        relatedEntityType: relatedEntityType,
        relatedEntityId: relatedEntityId,
        isRead: isRead ?? this.isRead,
        createdAt: createdAt,
      );

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        notificationId: json['notification_id'] as String,
        type: json['type'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
        relatedEntityType: json['related_entity_type'] as String?,
        relatedEntityId: json['related_entity_id'] as String?,
        isRead: json['is_read'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class NotificationPage {
  const NotificationPage({required this.unreadCount, required this.items});
  final int unreadCount;
  final List<AppNotification> items;
}

class NotificationRepository {
  NotificationRepository(this._api);
  final ApiClient _api;

  Future<NotificationPage> list({bool unreadOnly = false, int limit = 50}) async {
    final json = await _api.get('/notifications', query: {
      'unread_only': unreadOnly.toString(),
      'limit': limit.toString(),
    }) as Map<String, dynamic>;
    return NotificationPage(
      unreadCount: json['unread_count'] as int,
      items: (json['items'] as List)
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> markRead(String notificationId) =>
      _api.post('/notifications/$notificationId/read');

  Future<void> markAllRead() => _api.post('/notifications/read-all');
}
