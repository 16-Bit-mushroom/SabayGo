import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/notification_model.dart';
import '../../viewmodels/notifications_viewmodel.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final NotificationsViewModel _viewModel = NotificationsViewModel();

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onStateChanged);
  }

  void _onStateChanged() => setState(() {});

  @override
  void dispose() {
    _viewModel.removeListener(_onStateChanged);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = _viewModel.filteredNotifications;

    return SafeArea(
      child: Column(
        children: [
          // --- Search Bar ---
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            color: Colors.grey.shade100,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search notifications',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _viewModel.setSearchQuery,
            ),
          ),
          
          // --- Notifications List ---
          Expanded(
            child: notifications.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    itemCount: notifications.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      // Swipe to delete widget
                      return Dismissible(
                        key: Key(notification.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: Colors.red,
                          child: const Icon(Icons.delete_outline, color: Colors.white),
                        ),
                        onDismissed: (_) {
                          _viewModel.deleteNotification(notification.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Notification deleted'), duration: Duration(seconds: 2)),
                          );
                        },
                        child: _buildNotificationItem(notification),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No notifications found',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(NotificationModel notification) {
    final isUnread = !notification.isRead;
    
    // Determine icon and color based on type
    IconData icon;
    Color iconColor;
    
    switch (notification.type) {
      case NotificationType.tailoredTrip:
        icon = Icons.directions_car;
        iconColor = const Color(0xFF00A859);
        break;
      case NotificationType.tripCanceled:
        icon = Icons.cancel_outlined;
        iconColor = Colors.red;
        break;
      case NotificationType.vanDeparted:
        icon = Icons.time_to_leave;
        iconColor = Colors.orange;
        break;
      case NotificationType.tripUpdate:
        icon = Icons.info_outline;
        iconColor = Colors.blue;
        break;
      case NotificationType.policyUpdate:
      case NotificationType.terminalPolicy:
        icon = Icons.article_outlined;
        iconColor = Colors.grey.shade700;
        break;
    }

    return InkWell(
      onTap: () {
        _viewModel.markAsRead(notification.id);
      },
      child: Container(
        color: isUnread ? Colors.blue.shade50.withOpacity(0.3) : Colors.white,
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon container
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                            fontSize: 16,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Text(
                        _formatTimestamp(notification.timestamp),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notification.message,
                    style: TextStyle(
                      color: isUnread ? Colors.black87 : Colors.grey.shade600,
                      height: 1.4,
                    ),
                  ),
                  
                  // Conditional CTA Buttons
                  if (_hasCTA(notification.type)) ...[
                    const SizedBox(height: 12),
                    _buildCTAButton(context, notification),
                  ]
                ],
              ),
            ),
            
            // Unread dot indicator
            if (isUnread)
              Container(
                margin: const EdgeInsets.only(left: 8, top: 8),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }

  bool _hasCTA(NotificationType type) {
    return type == NotificationType.tailoredTrip || 
           type == NotificationType.tripCanceled || 
           type == NotificationType.vanDeparted;
  }

  // UPDATED: Added BuildContext to access the TabController
  Widget _buildCTAButton(BuildContext context, NotificationModel notification) {
    String buttonText = '';
    Color buttonColor = const Color(0xFF00A859);
    
    if (notification.type == NotificationType.tailoredTrip) {
      buttonText = 'Book Now';
    } else if (notification.type == NotificationType.tripCanceled) {
      buttonText = 'Find Another Ride';
      buttonColor = Colors.red;
    } else if (notification.type == NotificationType.vanDeparted) {
      buttonText = 'View Next Schedule';
      buttonColor = Colors.orange;
    }

    return OutlinedButton(
      onPressed: () {
        // 1. Mark as read
        _viewModel.markAsRead(notification.id);
        
        // 2. Seamlessly transition the user back to the Home Tab (Index 0)
        DefaultTabController.of(context).animateTo(0);
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: buttonColor,
        side: BorderSide(color: buttonColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(buttonText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24 && now.day == dt.day) {
      return DateFormat('hh:mm a').format(dt);
    } else if (difference.inDays < 7) {
      return DateFormat('EEE').format(dt);
    } else {
      return DateFormat('MMM dd').format(dt);
    }
  }
}