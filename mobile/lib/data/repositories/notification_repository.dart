import '../../core/network/api_client.dart';
import '../../models/notification_model.dart';

class NotificationPage {
  const NotificationPage({required this.unreadCount, required this.items});
  final int unreadCount;
  final List<NotificationModel> items;
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
          .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> markRead(String notificationId) =>
      _api.post('/notifications/$notificationId/read');

  Future<void> markAllRead() => _api.post('/notifications/read-all');
}
