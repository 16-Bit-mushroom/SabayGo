import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/design/components/app_card.dart';
import '../../core/design/components/empty_state.dart';
import '../../core/design/components/money.dart';
import '../../core/design/components/journey_strip.dart';
import '../../core/design/components/section_header.dart';
import '../../core/design/components/status_chip.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/util/when.dart';
import '../../data/repositories/booking_repository.dart';
import '../../viewmodels/reservations_viewmodel.dart';
import 'reservation_screen.dart';

/// Everything the passenger has booked: the next one, the later ones, and
/// what has already happened.
///
/// The next trip used to be a block of saturated green (or amber when
/// unpaid) with a fifteen-pixel drop shadow — the loudest surface in the
/// app, on a tab a passenger opens several times a day. Filling a card with
/// a status colour also spends the colour before it is needed: white text on
/// green left the status chip, the fare, the terminals and both buttons all
/// equally white, so nothing inside the card had any hierarchy left.
///
/// Now the card is a card and the *chip* carries the status. That is the one
/// element whose job is to be noticed, and against white it can be.
class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key});

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  late final ReservationsViewModel _vm;

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiClient>();
    _vm = ReservationsViewModel(BookingRepository(api))
      ..addListener(_onChanged);
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

  Future<void> _openReservation(BookingSummary b) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReservationScreen.fromBooking(booking: b)),
    );
    // The Paid mark, a check-in or a cancel may have happened meanwhile.
    _vm.load();
  }

  Future<void> _cancel(BookingSummary b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this reservation?'),
        content: const Text(
          'Your space will be released for someone else. You have not paid, '
          'so there is nothing to hand back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Cancel reservation'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await _vm.cancel(b.bookingId);
    _snack(err ?? 'Reservation cancelled. The space has been released.');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _vm.load,
          child: NestedScrollView(
            headerSliverBuilder: (context, _) => [
              SliverToBoxAdapter(child: _header()),
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyTabBar(
                  const TabBar(
                    tabs: [
                      Tab(text: 'Past trips'),
                      Tab(text: 'Cancelled'),
                    ],
                  ),
                ),
              ),
            ],
            body: TabBarView(
              children: [
                _finishedList(
                  _vm.history,
                  emptyTitle: 'No past trips yet',
                  emptyBody: 'Trips you have taken will be listed here once '
                      'they are complete.',
                  tone: StatusTone.muted,
                ),
                _finishedList(
                  _vm.cancelled,
                  emptyTitle: 'Nothing cancelled',
                  emptyBody: 'Bookings you cancel, and any the cooperative '
                      'cancels, appear here.',
                  tone: StatusTone.danger,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader('Next trip'),
          const SizedBox(height: AppSpacing.md),
          _currentSection(),
          if (_vm.upcoming.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxl),
            AppSectionHeader(
              'Also booked',
              subtitle: '${_vm.upcoming.length} more '
                  '${_vm.upcoming.length == 1 ? 'trip' : 'trips'} ahead',
            ),
            const SizedBox(height: AppSpacing.md),
            for (final b in _vm.upcoming) ...[
              _BookingRow(
                booking: b,
                tone: _toneFor(b),
                onTap: () => _openReservation(b),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ],
      ),
    );
  }

  Widget _currentSection() {
    if (_vm.isLoading && !_vm.hasLoaded) {
      return const AppCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (_vm.error != null && _vm.current == null) {
      return _Notice(
        icon: Icons.cloud_off,
        title: 'Could not load your trips',
        body: _vm.error!,
        action: FilledButton(
          onPressed: _vm.load,
          child: const Text('Try again'),
        ),
      );
    }

    final b = _vm.current;
    if (b == null) {
      return const _Notice(
        icon: Icons.directions_bus_outlined,
        title: 'No trip booked',
        body: 'Search for a departure on the Home tab and your next trip '
            'will show up here.',
      );
    }
    return _nextTripCard(b);
  }

  /// One of a home pickup's two seats: who it is for, where they board,
  /// and the landmark photo for the Dispatcher (brief 2.6). Both seats are
  /// paid in cash at the terminal.
  Widget _homePickupBand(BookingSummary b, HomePickupRef p) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.accessible_forward, size: 18, color: AppColors.info),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              p.isPassengerSeat
                  ? '${p.beneficiaryName}\'s seat: the van stops for them at the pin.'
                  : 'Your seat, riding with ${p.beneficiaryName}. Pay both seats in cash to the Dispatcher '
                      'at the terminal.',
              style: text.bodyMedium,
            ),
          ),
        ]),
        if (p.isPassengerSeat && b.isActive) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            p.photoSent
                ? 'Landmark photo sent to the Dispatcher.'
                : 'Help the Dispatcher find the place: send a photo of a landmark near the pin.',
            style: text.bodySmall,
          ),
          TextButton.icon(
            onPressed: () => _sendLandmarkPhoto(p),
            icon: const Icon(Icons.image_outlined, size: 18),
            label: Text(p.photoSent ? 'Send another photo' : 'Send a landmark photo'),
          ),
        ],
      ]),
    );
  }

  Future<void> _sendLandmarkPhoto(HomePickupRef p) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null || !mounted) return;
    try {
      await BookingRepository(context.read<ApiClient>())
          .sendLandmarkPhoto(p.pickupId, await picked.readAsBytes(), picked.name);
      messenger.showSnackBar(const SnackBar(
        content: Text('Sent to the trip\'s Dispatcher in the chat.'),
        behavior: SnackBarBehavior.floating,
      ));
      _vm.load();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating));
    }
  }

  /// The one booking that matters right now, in full.
  Widget _nextTripCard(BookingSummary b) {
    final busy = _vm.isBusy(b.bookingId);
    final text = Theme.of(context).textTheme;
    // The server decides: only an unpaid seat, before the list locks.
    final canCancel = b.canCancel;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Semantics(
            button: true,
            label: '${b.statusLabel}. ${dayAndTime(b.departure)}. '
                '${b.boardingTerminal} to ${b.alightingTerminal}. '
                '${Money.format(b.fare)}. Booking code ${b.bookingCode}. Opens the reservation.',
            excludeSemantics: true,
            child: InkWell(
              onTap: busy ? null : () => _openReservation(b),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: StatusChip(
                            b.statusLabel.toUpperCase(),
                            tone: _toneFor(b),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            dayAndTime(b.departure),
                            textAlign: TextAlign.end,
                            style: text.bodyMedium!
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    JourneyStrip(
                      origin: b.boardingTerminal,
                      destination: b.alightingTerminal,
                      originNote: 'Departs ${clockTime(b.departure)}',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            b.isPaid
                                ? 'Code ${b.bookingCode}'
                                : 'Code ${b.bookingCode} · pay in cash'
                                    '${b.payBy != null ? ' by ${clockTime(b.payBy!)}' : ' at the terminal'}',
                            style: text.bodySmall,
                          ),
                        ),
                        Money(
                          b.fare,
                          style: text.titleMedium!
                              .copyWith(color: AppColors.primary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (b.homePickup case final pickup?) ...[
            const Divider(height: 1),
            _homePickupBand(b, pickup),
          ],
          if (canCancel) ...[
            const Divider(height: 1),
            Row(
              children: [
                if (canCancel)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: busy ? null : () => _cancel(b),
                      icon: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.close, size: 18),
                      label: const Text('Cancel'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Past and cancelled bookings. Deliberately quieter than the live ones:
  /// a finished trip is a record, not a thing to act on.
  Widget _finishedList(
    List<BookingSummary> bookings, {
    required String emptyTitle,
    required String emptyBody,
    required StatusTone tone,
  }) {
    if (bookings.isEmpty) {
      return AppEmptyState(
        icon: Icons.history,
        title: emptyTitle,
        body: emptyBody,
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, AppSpacing.section,
      ),
      itemCount: bookings.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, i) => _BookingRow(
        booking: bookings[i],
        tone: tone,
        showCode: true,
      ),
    );
  }

  static StatusTone _toneFor(BookingSummary b) {
    if (b.isCancelled) return StatusTone.danger;
    if (b.isActive && !b.isPaid) return StatusTone.warning;
    if (b.isPaid || b.isBoarded) return StatusTone.success;
    return StatusTone.info;
  }
}

/// A booking in a list: when, where, how much, what state.
///
/// Same reading order as a search result — the fact you scan for first, at
/// the top left; the money at the top right — so a passenger moving between
/// the two tabs is not learning a second layout.
class _BookingRow extends StatelessWidget {
  const _BookingRow({
    required this.booking,
    required this.tone,
    this.onTap,
    this.showCode = false,
  });

  final BookingSummary booking;
  final StatusTone tone;
  final VoidCallback? onTap;
  final bool showCode;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = booking;

    return AppCard(
      onTap: onTap,
      semanticLabel: '${dayAndTime(b.departure)}. ${b.boardingTerminal} to '
          '${b.alightingTerminal}. ${Money.format(b.fare)}. '
          '${b.statusLabel}.'
          '${onTap == null ? '' : ' Opens the reservation.'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dayAndTime(b.departure),
                  style: text.titleMedium,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Money(
                b.fare,
                showCentavos: false,
                style: text.titleMedium!.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Flexible(
                child: Text(
                  b.boardingTerminal,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Icon(Icons.arrow_forward,
                    size: 14, color: AppColors.textMuted),
              ),
              Flexible(
                child: Text(
                  b.alightingTerminal,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (showCode)
                Expanded(
                  child: Text(
                    b.cancelLabel ?? 'Code ${b.bookingCode}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: AppSpacing.sm),
              // "RELEASED, UNPAID" is a wide chip; flexible so it ellipsises
              // rather than pushing the code off the card.
              Flexible(
                child: StatusChip(b.statusLabel.toUpperCase(), tone: tone),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A card that explains why there is nothing to show.
///
/// Not [AppEmptyState]: that one measures the viewport to centre itself,
/// and inside a sliver header the viewport has no height to measure.
class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 32, color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpacing.md),
          Semantics(header: true, child: Text(title, style: text.titleMedium)),
          const SizedBox(height: AppSpacing.xs),
          Text(body, style: text.bodyMedium!
              .copyWith(color: AppColors.textMuted, height: 1.5)),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

class _StickyTabBar extends SliverPersistentHeaderDelegate {
  const _StickyTabBar(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      // Opaque, or the list scrolls visibly through the pinned header.
      ColoredBox(color: AppColors.surface, child: tabBar);

  @override
  bool shouldRebuild(_StickyTabBar oldDelegate) => false;
}
