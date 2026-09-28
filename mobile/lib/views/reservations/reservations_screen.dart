import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/repositories/trip_repository.dart';
import '../../viewmodels/reservations_viewmodel.dart';
import '../ticket/ticket_screen.dart';
import 'reschedule_sheet.dart';

class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key});

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  late final ReservationsViewModel _vm;
  late final TripRepository _trips;

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiClient>();
    _trips = TripRepository(api);
    _vm = ReservationsViewModel(BookingRepository(api))..addListener(_onChanged);
    _vm.load();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    _vm.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openTicket(BookingSummary b) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TicketScreen.fromBooking(booking: b)),
    );
    // Payment, check-in or cancel may have happened on that screen.
    _vm.load();
  }

  Future<void> _cancel(BookingSummary b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this reservation?'),
        content: const Text(
          'Your space will be released. The cooperative does not issue '
          'refunds, so any fare already paid is not returned.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel reservation', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await _vm.cancel(b.bookingId);
    _snack(err ?? 'Reservation cancelled.');
  }

  Future<void> _reschedule(BookingSummary b) async {
    final newTripId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RescheduleSheet(booking: b, trips: _trips),
    );
    if (newTripId == null) return;
    final err = await _vm.reschedule(b.bookingId, newTripId);
    _snack(err ?? 'Moved to the new departure.');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _vm.load,
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Current Reservation',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: -0.5),
                        ),
                        const SizedBox(height: 16),
                        _currentSection(),
                        for (final b in _vm.upcoming) ...[
                          const SizedBox(height: 12),
                          _upcomingRow(b),
                        ],
                      ],
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyTabBarDelegate(
                    TabBar(
                      indicatorColor: AppColors.accent,
                      labelColor: AppColors.accent,
                      unselectedLabelColor: Colors.grey,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                      tabs: const [
                        Tab(text: 'Trip History'),
                        Tab(text: 'Canceled'),
                      ],
                    ),
                  ),
                ),
              ];
            },
            body: TabBarView(
              children: [
                _list(_vm.history, isCanceled: false),
                _list(_vm.cancelled, isCanceled: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _currentSection() {
    if (_vm.isLoading && !_vm.hasLoaded) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_vm.error != null && _vm.current == null) {
      return _placeholder(
        icon: Icons.cloud_off,
        text: _vm.error!,
        action: TextButton(onPressed: _vm.load, child: const Text('Try again')),
      );
    }
    final b = _vm.current;
    if (b == null) {
      return _placeholder(icon: Icons.directions_car_outlined, text: 'No upcoming trips');
    }
    return _currentCard(b);
  }

  Widget _currentCard(BookingSummary b) {
    final busy = _vm.isBusy(b.bookingId);
    final colour = b.isAwaitingPayment ? AppColors.warning : AppColors.accent;
    return Container(
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: colour.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: busy ? null : () => _openTicket(b),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                        child: Text(b.statusLabel.toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1)),
                      ),
                      Text(DateFormat('MMM dd').format(b.departure),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.departure_board, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(b.boardingTerminal,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 11, top: 4, bottom: 4),
                    child: Icon(Icons.more_vert, color: Colors.white54, size: 20),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(b.alightingTerminal,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Departure', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text(DateFormat('hh:mm a').format(b.departure),
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Fare', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text('₱${b.fare.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Icon(b.isAwaitingPayment ? Icons.payment : Icons.qr_code, color: Colors.white, size: 32),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Colors.white24),
          Row(
            children: [
              if (b.canReschedule)
                Expanded(
                  child: TextButton.icon(
                    onPressed: busy ? null : () => _reschedule(b),
                    icon: const Icon(Icons.event_repeat, color: Colors.white, size: 18),
                    label: const Text('Reschedule', style: TextStyle(color: Colors.white)),
                  ),
                ),
              Expanded(
                child: TextButton.icon(
                  onPressed: busy ? null : () => _cancel(b),
                  icon: busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.cancel_outlined, color: Colors.white, size: 18),
                  label: const Text('Cancel', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _upcomingRow(BookingSummary b) {
    return ListTile(
      onTap: () => _openTicket(b),
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: const Icon(Icons.confirmation_number_outlined, color: AppColors.primary),
      title: Text('${b.boardingTerminal} → ${b.alightingTerminal}',
          style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
      subtitle: Text('${DateFormat('MMM dd • hh:mm a').format(b.departure)} · ${b.statusLabel}'),
      trailing: const Icon(Icons.chevron_right),
    );
  }

  Widget _placeholder({required IconData icon, required String text, Widget? action}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Icon(icon, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          ?action,
        ],
      ),
    );
  }

  Widget _list(List<BookingSummary> bookings, {required bool isCanceled}) {
    if (bookings.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text('No ${isCanceled ? 'canceled' : 'past'} reservations.',
                  style: const TextStyle(color: Colors.grey)),
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      itemCount: bookings.length,
      separatorBuilder: (_, _) => const Divider(height: 32),
      itemBuilder: (context, index) {
        final b = bookings[index];
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: isCanceled ? Colors.red.shade50 : Colors.blue.shade50, shape: BoxShape.circle),
              child: Icon(isCanceled ? Icons.cancel_outlined : Icons.check_circle_outline, color: isCanceled ? Colors.red : Colors.blue),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${b.boardingTerminal} to ${b.alightingTerminal}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(DateFormat('MMM dd, yyyy • hh:mm a').format(b.departure), style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text('${b.ticketNumber} · ${b.statusLabel}', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                ],
              ),
            ),
            Text('₱${b.fare.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        );
      },
    );
  }
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _StickyTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.grey.shade100,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) => false;
}
