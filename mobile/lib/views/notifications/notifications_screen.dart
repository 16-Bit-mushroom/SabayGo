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
import '../passenger_main_screen.dart';

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
    // Cards with a gap, not rows under dividers (20 Nov redesign): each
    // update is a separate thing to read and, sometimes, act on.
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, AppSpacing.section),
      itemCount: notifications.length,
      separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) => _buildNotificationItem(notifications[index]),
    );
  }

  /// What kind of update it is, said on its chip, with the icon and tone.
  static (String, IconData, StatusTone) _kind(NotificationType type) => switch (type) {
        NotificationType.tailoredTrip => ('SAVED DESTINATION', Icons.directions_bus_outlined, StatusTone.success),
        NotificationType.tripCanceled => ('CANCELLED', Icons.cancel_outlined, StatusTone.danger),
        NotificationType.vanDeparted => ('VAN LEFT', Icons.time_to_leave, StatusTone.warning),
        NotificationType.tripUpdate => ('TRIP UPDATE', Icons.info_outline, StatusTone.info),
        NotificationType.policyUpdate || NotificationType.terminalPolicy => ('RULES', Icons.article_outlined, StatusTone.muted),
        NotificationType.varianceAlert => ('COUNT CHECK', Icons.people_alt_outlined, StatusTone.warning),
        NotificationType.sosAlert => ('SOS', Icons.emergency_share, StatusTone.danger),
        // Money still owed is routine until it is paid: ochre, never red.
        NotificationType.unremittedFare => ('FEES', Icons.payments_outlined, StatusTone.warning),
        NotificationType.departureReminder => ('REMINDER', Icons.schedule, StatusTone.warning),
        NotificationType.scheduleChange => ('SCHEDULE', Icons.event_repeat, StatusTone.info),
        NotificationType.systemAlert => ('NOTICE', Icons.notifications_active_outlined, StatusTone.muted),
      };

  Widget _buildNotificationItem(NotificationModel notification) {
    final isUnread = !notification.isRead;
    final (kind, icon, tone) = _kind(notification.type);
    final text = Theme.of(context).textTheme;

    return Material(
      // Unread on the soft tint, edged in green; read on white.
      color: isUnread ? AppColors.primaryContainer : AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: isUnread ? AppColors.primaryLight : AppColors.edge),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _viewModel.markAsRead(notification.id),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Flexible(child: StatusChip(kind, tone: tone, icon: icon)),
                const SizedBox(width: AppSpacing.sm),
                Text(_formatTimestamp(notification.timestamp), style: text.bodySmall),
                if (isUnread) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Semantics(
                    label: 'unread',
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: AppSpacing.sm),
              Text(
                notification.title,
                style: text.bodyLarge?.copyWith(fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(notification.message, style: text.bodyMedium?.copyWith(color: AppColors.textPrimary)),
              if (_hasCTA(notification.type)) ...[
                const SizedBox(height: AppSpacing.md),
                _buildCTAButton(context, notification),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _hasCTA(NotificationType type) {
    return type == NotificationType.tailoredTrip ||
        type == NotificationType.tripCanceled ||
        type == NotificationType.vanDeparted;
  }

  Widget _buildCTAButton(BuildContext context, NotificationModel notification) {
    final buttonText = switch (notification.type) {
      NotificationType.tailoredTrip => 'Book a seat',
      NotificationType.tripCanceled => 'Find another trip',
      _ => 'See the next departures',
    };

    return OutlinedButton(
      onPressed: () {
        _viewModel.markAsRead(notification.id);
        // To Home. It called DefaultTabController.of(), which threw: the
        // shell has used a NavigationBar, not a TabBar, since the redesign
        // of 3 Oct (fixed 20 Nov).
        PassengerMainScreen.goTo(context, PassengerMainScreen.home);
      },
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(AppSizing.minTouchTarget)),
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