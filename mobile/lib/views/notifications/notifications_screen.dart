import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/design/components/empty_state.dart';
import '../../core/design/components/status_chip.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../data/repositories/notification_repository.dart';
import '../../models/notification_model.dart';
import '../../viewmodels/notifications_viewmodel.dart';

class NotificationsScreen extends StatefulWidget {
  /// Pass a [viewModel] to share one already polling elsewhere (the
  /// Dispatcher's app-bar badge); omit it and the screen owns its own.
  const NotificationsScreen({super.key, this.viewModel});

  final NotificationsViewModel? viewModel;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _query = '';
  late final NotificationsViewModel _viewModel;
  late final bool _ownsViewModel;

  @override
  void initState() {
    super.initState();
    _ownsViewModel = widget.viewModel == null;
    _viewModel = widget.viewModel ??
        NotificationsViewModel(NotificationRepository(context.read<ApiClient>()));
    _viewModel.addListener(_onStateChanged);
  }

  void _onStateChanged() => setState(() {});

  @override
  void dispose() {
    _viewModel.removeListener(_onStateChanged);
    if (_ownsViewModel) _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifications = _viewModel.filteredNotifications;

    return SafeArea(
      child: Column(
        children: [
          // --- Search Bar ---
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.sm),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search updates',
                prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
              ),
              onChanged: (q) {
                setState(() => _query = q);
                _viewModel.setSearchQuery(q);
              },
            ),
          ),
          
          // --- Notifications List ---
          Expanded(
            child: RefreshIndicator(
              onRefresh: _viewModel.load,
              child: _buildBody(notifications),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<NotificationModel> notifications) {
    if (_viewModel.isLoading && notifications.isEmpty && _viewModel.error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_viewModel.error != null && notifications.isEmpty) {
      return const AppEmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load updates',
        body: 'Check your connection, then pull down to try again.',
      );
    }
    if (notifications.isEmpty) {
      return _query.isEmpty
          ? const AppEmptyState(
              icon: Icons.notifications_none,
              title: 'No updates yet',
              body: 'Reminders and changes to your trips will appear here.',
            )
          : const AppEmptyState(
              icon: Icons.search_off,
              title: 'Nothing matches',
              body: 'Try another word, or clear the search.',
            );
    }
    return ListView.separated(
      itemCount: notifications.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) => _buildNotificationItem(notifications[index]),
    );
  }

  Widget _buildNotificationItem(NotificationModel notification) {
    final isUnread = !notification.isRead;
    
    final (IconData icon, StatusTone tone) = switch (notification.type) {
      NotificationType.tailoredTrip => (Icons.directions_bus_outlined, StatusTone.info),
      NotificationType.tripCanceled => (Icons.cancel_outlined, StatusTone.danger),
      NotificationType.vanDeparted => (Icons.time_to_leave, StatusTone.warning),
      NotificationType.tripUpdate => (Icons.info_outline, StatusTone.info),
      NotificationType.policyUpdate || NotificationType.terminalPolicy => (Icons.article_outlined, StatusTone.muted),
      NotificationType.varianceAlert => (Icons.people_alt_outlined, StatusTone.warning),
      NotificationType.sosAlert => (Icons.emergency_share, StatusTone.danger),
      // Money still owed is routine until it is paid: ochre, never red.
      NotificationType.unremittedFare => (Icons.payments_outlined, StatusTone.warning),
      NotificationType.departureReminder => (Icons.schedule, StatusTone.warning),
      NotificationType.scheduleChange => (Icons.event_repeat, StatusTone.info),
      NotificationType.systemAlert => (Icons.notifications_active_outlined, StatusTone.muted),
    };
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: () {
        _viewModel.markAsRead(notification.id);
      },
      child: Container(
        color: isUnread ? AppColors.primaryContainer : AppColors.surfaceRaised,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon container
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tone.bg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: tone.fg, size: 24),
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
                          style: text.bodyLarge?.copyWith(fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500),
                        ),
                      ),
                      Text(
                        _formatTimestamp(notification.timestamp),
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notification.message,
                    style: text.bodyMedium?.copyWith(color: isUnread ? AppColors.textPrimary : AppColors.textMuted),
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
                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
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
    final buttonText = switch (notification.type) {
      NotificationType.tailoredTrip => 'Book a seat',
      NotificationType.tripCanceled => 'Find another trip',
      _ => 'See the next departures',
    };

    return OutlinedButton(
      onPressed: () {
        // 1. Mark as read
        _viewModel.markAsRead(notification.id);
        
        // 2. Seamlessly transition the user back to the Home Tab (Index 0)
        DefaultTabController.of(context).animateTo(0);
      },
      // Ink, the colour of the thing you act on; 48dp tall like every target.
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, AppSizing.minTouchTarget)),
      child: Text(buttonText),
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