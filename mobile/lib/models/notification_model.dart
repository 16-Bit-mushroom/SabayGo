enum NotificationType {
  tailoredTrip,    // New schedule for saved destination
  tripCanceled,    // Trip was canceled
  vanDeparted,     // Van already left
  tripUpdate,      // Trip details changed
  policyUpdate,    // App/Trip policy updates
  terminalPolicy   // Terminal policy updates
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
  });

  final String id;
  final NotificationType type;
  final String title;
  final String message;
  final DateTime timestamp;
  final bool isRead;
  final String? relatedTripId; // Useful for routing the CTA button

  NotificationModel copyWith({bool? isRead}) {
    return NotificationModel(
      id: id,
      type: type,
      title: title,
      message: message,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      relatedTripId: relatedTripId,
    );
  }
}