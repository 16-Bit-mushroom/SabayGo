/// Mirrors the `notifications.type` ENUM in migration 006. The three
/// members without a server value (tripCanceled, vanDeparted, policyUpdate)
/// predate the schema; they are kept so existing UI branches compile and
/// map from `trip_update` / `terminal_policy` where the server uses those.
enum NotificationType {
  tailoredTrip,      // tailored_schedule
  tripCanceled,      // (client-only, legacy)
  vanDeparted,       // (client-only, legacy)
  tripUpdate,        // trip_update
  policyUpdate,      // (client-only, legacy)
  terminalPolicy,    // terminal_policy
  systemAlert,       // system_alert
  varianceAlert,     // variance_alert -- YOLOv8 headcount differs from manifest
  unremittedFare,    // unremitted_fare
  departureReminder, // departure_reminder
  scheduleChange,    // schedule_change
  sosAlert;          // sos_alert -- an emergency raised from a handset

  static NotificationType fromServer(String value) => switch (value) {
        'tailored_schedule' => NotificationType.tailoredTrip,
        'trip_update' => NotificationType.tripUpdate,
        'terminal_policy' => NotificationType.terminalPolicy,
        'variance_alert' => NotificationType.varianceAlert,
        'unremitted_fare' => NotificationType.unremittedFare,
        'departure_reminder' => NotificationType.departureReminder,
        'schedule_change' => NotificationType.scheduleChange,
        'sos_alert' => NotificationType.sosAlert,
        _ => NotificationType.systemAlert,
      };
}

class NotificationModel {
  NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.timestamp,
    this.isRead = false,
    this.relatedTripId,
    this.relatedEntityType,
    this.relatedEntityId,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final String? relatedTripId; // Useful for routing the CTA button
  final String? relatedEntityType; // 'audit', 'trip', ...
  final String? relatedEntityId;

  NotificationModel copyWith({bool? isRead}) {
    return NotificationModel(
      id: id,
      type: type,
      title: title,
      message: message,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      relatedTripId: relatedTripId,
      relatedEntityType: relatedEntityType,
      relatedEntityId: relatedEntityId,
    );
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    final entityType = json['related_entity_type'] as String?;
    final entityId = json['related_entity_id'] as String?;
    return NotificationModel(
      id: json['notification_id'] as String,
      type: NotificationType.fromServer(json['type'] as String),
      title: json['title'] as String,
      message: json['message'] as String,
      timestamp: DateTime.parse(json['created_at'] as String),
      isRead: json['is_read'] as bool,
      relatedTripId: entityType == 'trip' ? entityId : null,
      relatedEntityType: entityType,
      relatedEntityId: entityId,
    );
  }
}
