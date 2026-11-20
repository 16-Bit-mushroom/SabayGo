import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/dialog_buttons.dart';
import '../../core/design/components/status_chip.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../data/repositories/messaging_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/operations_repository.dart';
import '../../viewmodels/auth_provider.dart';
import '../../viewmodels/conversations_viewmodel.dart';
import '../../viewmodels/notifications_viewmodel.dart';
import '../../viewmodels/shift_viewmodel.dart';
import '../messages/conversations_screen.dart';
import '../notifications/notifications_screen.dart';
import 'dispatcher_trips_screen.dart';

/// Shell for the Dispatcher working a van.
///
/// One list: the trips this person is rostered to. Everything they do at
/// the door — scan, log a cash passenger, count heads, open and close
/// boarding, hand over cash — hangs off a trip, so it lives on that
/// trip's manifest rather than in a separate tab that would have to ask
/// "which trip?" again.
class DispatcherMainScreen extends StatefulWidget {
  const DispatcherMainScreen({super.key});

  @override
  State<DispatcherMainScreen> createState() => _DispatcherMainScreenState();
}

class _DispatcherMainScreenState extends State<DispatcherMainScreen> {
  late final ShiftViewModel _shift;
  late final NotificationsViewModel _notifications;
  late final ConversationsViewModel _conversations;

  @override
  void initState() {
    super.initState();
    _shift = ShiftViewModel(OperationsRepository(context.read<ApiClient>()));
    // A flagged headcount should reach the crew while the van is still on
    // that leg, so the badge polls rather than waiting for the screen.
    _notifications = NotificationsViewModel(
      NotificationRepository(context.read<ApiClient>()),
      pollEvery: const Duration(seconds: 30),
    );
    _conversations = ConversationsViewModel(
      MessagingRepository(context.read<ApiClient>()),
      pollEvery: const Duration(seconds: 15),
    );
  }

  @override
  void dispose() {
    _shift.dispose();
    _notifications.dispose();
    _conversations.dispose();
    super.dispose();
  }

  void _openMessages() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Messages')),
          body: ConversationsScreen(viewModel: _conversations),
        ),
      ),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: const Text('Notifications'),
            actions: [
              if (_notifications.unreadCount > 0)
                TextButton(
                  onPressed: _notifications.markAllRead,
                  // Colour comes from the theme: this bar is the light one,
                  // and a hardcoded white label was invisible on it.
                  child: const Text('Mark all read'),
                ),
            ],
          ),
          body: NotificationsScreen(viewModel: _notifications),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut() async {
    final auth = context.read<AuthProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End shift?'),
        content: const Text(
          'You will need to sign in again to mark seats Paid or log passengers.',
        ),
        actions: [
          DialogButtons(
            action: 'End shift',
            onAction: () => Navigator.pop(ctx, true),
            cancel: 'Stay',
            onCancel: () => Navigator.pop(ctx, false),
          ),
        ],
      ),
    );
    if (ok == true) await auth.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;
    // The bar grows with the system text so its labels and the role chip
    // are never clipped (WCAG 1.4.4); 56 at normal size.
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);

    return ChangeNotifierProvider.value(
      value: _shift,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: kToolbarHeight * scale,
          // Light, like every other screen (3 Oct). The crew bar used to be
          // a solid brand block to say "this is the crew side"; after the
          // rebrand that block was black, the heaviest thing on a screen
          // read in direct sun, and it forced every icon in it to white.
          // The role is now said in words, on a chip, which survives glare
          // better than a background colour does.
          titleSpacing: AppSpacing.gutter,
          // The name and the role have the bar's whole left side. Beside
          // the van mark and three labelled buttons they were cut to
          // "Nonoy…" and "DISP…" (20 Nov); the role chip still says which
          // side of the app this is.
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                profile?.displayName ?? 'SabayGo',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 2),
              const StatusChip(
                'DISPATCHER',
                tone: StatusTone.brand,
              ),
            ],
          ),
          // Labelled, not icons alone (20 Nov redesign): an envelope and a
          // bell are guesses, and "End shift" must never be.
          actions: [
            ListenableBuilder(
              listenable: _conversations,
              builder: (context, _) => _BarAction(
                icon: _conversations.unreadCount > 0 ? Icons.chat_bubble : Icons.chat_bubble_outline,
                label: 'Messages',
                badge: _conversations.unreadCount,
                onPressed: _openMessages,
              ),
            ),
            ListenableBuilder(
              listenable: _notifications,
              builder: (context, _) => _BarAction(
                icon: _notifications.unreadCount > 0 ? Icons.notifications_active : Icons.notifications_none,
                label: 'Alerts',
                badge: _notifications.unreadCount,
                onPressed: _openNotifications,
              ),
            ),
            _BarAction(icon: Icons.logout, label: 'End shift', onPressed: _confirmSignOut),
            const SizedBox(width: 4),
          ],
        ),
        body: const DispatcherTripsScreen(),
      ),
    );
  }
}

/// An app bar action with its name under the icon, and an unread count.
class _BarAction extends StatelessWidget {
  const _BarAction({required this.icon, required this.label, required this.onPressed, this.badge = 0});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final int badge;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: badge > 0 ? '$label, $badge unread' : label,
        excludeSemantics: true,
        onTap: onPressed,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 52, minHeight: AppSizing.minTouchTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Badge(
                    isLabelVisible: badge > 0,
                    label: Text('$badge'),
                    child: Icon(icon, size: 22, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(label,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ],
              ),
            ),
          ),
        ),
      );
}
