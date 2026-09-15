import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/operations_repository.dart';
import '../../viewmodels/auth_provider.dart';
import '../../viewmodels/notifications_viewmodel.dart';
import '../../viewmodels/shift_viewmodel.dart';
import '../notifications/notifications_screen.dart';
import 'conductor_trips_screen.dart';
import 'qr_scanner_screen.dart';

/// Shell for crew working a van — conductor or driver.
///
/// One list: the trips this person is rostered to. Everything they do at
/// the door — scan, log a cash passenger, count heads, open and close
/// boarding, hand over cash — hangs off a trip, so it lives on that
/// trip's manifest rather than in a separate tab that would have to ask
/// "which trip?" again.
class ConductorMainScreen extends StatefulWidget {
  const ConductorMainScreen({super.key});

  @override
  State<ConductorMainScreen> createState() => _ConductorMainScreenState();
}

class _ConductorMainScreenState extends State<ConductorMainScreen> {
  late final ShiftViewModel _shift;
  late final NotificationsViewModel _notifications;

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
  }

  @override
  void dispose() {
    _shift.dispose();
    _notifications.dispose();
    super.dispose();
  }

  Future<void> _openScanner() async {
    final trip = _shift.active;
    if (trip == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Open a trip first so the scan is checked against it.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (trip.isDeparted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('That trip has departed. Log roadside pickups from its manifest.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: _shift,
          child: QRScannerScreen(trip: trip, stopSequence: _shift.currentStop),
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
                  child: const Text('Mark all read', style: TextStyle(color: Colors.white)),
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
          'You will need to sign in again to scan tickets or log passengers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End shift'),
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
    final isDriver = auth.role == UserRole.driver;

    return ChangeNotifierProvider.value(
      value: _shift,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          centerTitle: false,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isDriver ? Icons.airline_seat_recline_normal : Icons.storefront,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile?.displayName ?? 'SabayGo',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    isDriver ? 'Driver' : 'Conductor',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            ListenableBuilder(
              listenable: _notifications,
              builder: (context, _) {
                final unread = _notifications.unreadCount;
                return IconButton(
                  tooltip: unread == 0 ? 'Notifications' : '$unread unread',
                  onPressed: _openNotifications,
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text('$unread'),
                    child: Icon(
                      unread > 0 ? Icons.notifications_active : Icons.notifications_none,
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'End shift',
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: _confirmSignOut,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: const ConductorTripsScreen(),
        // Scanning is the single most repeated action of a shift, so it
        // stays reachable from the list, not only from inside a manifest.
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openScanner,
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
