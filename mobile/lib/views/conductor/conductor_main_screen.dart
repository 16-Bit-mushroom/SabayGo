import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../data/repositories/auth_repository.dart';
import '../../viewmodels/auth_provider.dart';
import 'log_book_screen.dart';
import 'qr_scanner_screen.dart';
import 'conductor_trips_screen.dart';

/// Shell for crew working a van — conductor or driver.
///
/// The previous Dispatcher shell carried six destinations spanning two
/// unrelated jobs: fleet configuration, schedules and revenue alongside
/// scanning and the manifest. The first three belong to the cooperative
/// administrator at a desk and have moved to the web console. What
/// remains is what a person standing at a van door actually does.
class ConductorMainScreen extends StatefulWidget {
  const ConductorMainScreen({super.key});

  @override
  State<ConductorMainScreen> createState() => _ConductorMainScreenState();
}

class _ConductorMainScreenState extends State<ConductorMainScreen> {
  int _index = 0;

  static const List<Widget> _screens = <Widget>[
    ConductorTripsScreen(),
    LogBookScreen(),
  ];

  Future<void> _openScanner() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute<String>(builder: (_) => const QRScannerScreen()),
    );
    if (result != null && mounted) {
      _showScanResult(result as String);
    }
  }

  /// Verdict after a scan.
  ///
  /// The backend returns 200 with a `result` code even for a refused
  /// ticket, precisely so a conductor with a queue gets an answer rather
  /// than an error dialog. This sheet renders that verdict; it takes the
  /// real response once the scanner is wired in Phase 3.
  void _showScanResult(String payload) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.accent, size: 30),
                SizedBox(width: 10),
                Text(
                  'Valid ticket',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              payload,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Next passenger'),
            ),
          ],
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

    return Scaffold(
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
                // Was hardcoded to a cooperative name. It comes from the
                // signed-in account now, so the same build serves any
                // cooperative without an edit.
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
          IconButton(
            tooltip: 'End shift',
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _confirmSignOut,
          ),
          const SizedBox(width: 4),
        ],
      ),

      body: _screens[_index],

      // Scanning is the single most repeated action of a shift, so it
      // stays reachable from every tab rather than living behind one.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openScanner,
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Scan', style: TextStyle(fontWeight: FontWeight.w700)),
      ),

      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: AppColors.accent.withValues(alpha: 0.18),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people, color: AppColors.accent),
            label: 'Manifest',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book, color: AppColors.accent),
            label: 'Walk-ins',
          ),
        ],
      ),
    );
  }
}