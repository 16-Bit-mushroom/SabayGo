import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/app_card.dart';
import '../../core/design/components/empty_state.dart';
import '../../core/design/components/section_header.dart';
import '../../core/design/tokens.dart';
import '../../core/util/when.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/repositories/trip_repository.dart';
import '../../models/uv_trip_model.dart';
import '../../viewmodels/home_search_viewmodel.dart';
import '../reservations/reservation_screen.dart';
import 'widgets/journey_picker_card.dart';
import 'widgets/time_block_filter.dart';
import 'widgets/trip_card.dart';
import 'widgets/trip_details_sheet.dart';
import '../home_pickup/home_pickup_screen.dart';

const double kWideLayoutBreakpoint = 700;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeSearchViewModel _vm;
  late final BookingRepository _bookings;
  bool _booking = false;

  /// The one-line cash reminder at the top. Dismissed for this run of the
  /// app; it comes back next time, which suits a rule that is new to most
  /// passengers.
  bool _showCashTip = true;

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiClient>();
    _vm = HomeSearchViewModel(TripRepository(api))
      ..addListener(_onChanged);
    _bookings = BookingRepository(api);
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

  Future<void> _handleBook(UvTripModel trip) async {
    if (_booking) return;
    setState(() => _booking = true);

    try {
      final result = await _bookings.reserve(
        tripId: trip.id,
        boardingStop: trip.boardingStop,
        alightingStop: trip.alightingStop,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReservationScreen(bookedTrip: trip, reservation: result),
        ),
      );
      // Availability changed for everyone, so pull fresh numbers rather
      // than decrementing a local counter — the old prototype did that
      // and would drift from the server on any concurrent booking.
      _vm.refreshTrips();
    } on ContentionException {
      // Lost a race for the lock rather than sold out. Worth retrying,
      // and the wording must not imply the trip is full -- nor mention a
      // "seat map", which is not something this system shows anyone: space
      // is counted per leg and no seat number is ever assigned.
      _snack('Someone else is booking this trip right now. Please try again.');
    } on ConflictException catch (e) {
      _snack(e.message);
      _vm.refreshTrips();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= kWideLayoutBreakpoint;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _vm.refreshTrips,
        child: isWide ? _wide() : _narrow(),
      ),
    );
  }

  void _openDetails(UvTripModel trip) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => TripDetailsSheet(
        trip: trip,
        onBook: () {
          Navigator.pop(sheetContext);
          _handleBook(trip);
        },
        // Two seats are needed: the relative's and the passenger's.
        onBookForOther: trip.isSpecialTrip || trip.availableSeats < 2
            ? null
            : () async {
                Navigator.pop(sheetContext);
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => HomePickupScreen(trip: trip)),
                );
                _vm.refreshTrips();
              },
      ),
    );
  }

  /// Context for the list: how many departures, and for which day.
  ///
  /// Without it the results arrive as an unannounced stack of cards. A count
  /// also answers the question a short list raises — whether two departures
  /// is everything there is, or everything that got through the filter.
  Widget? _resultsHeader() {
    if (!_vm.hasSearched || _vm.isLoadingTrips || _vm.error != null) {
      return null;
    }
    final count = _vm.filteredTrips.length;
    if (count == 0) return null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter, AppSpacing.xl, AppSpacing.gutter, AppSpacing.md,
      ),
      child: AppSectionHeader(
        count == 1 ? '1 departure' : '$count departures',
        subtitle: dayFriendly(_vm.serviceDate),
      ),
    );
  }

  /// Header, filter, list -- as slivers of one scrolling page (20 Nov), so
  /// at large text the search card scrolls away with the results instead
  /// of pinning them under a card taller than the screen.
  List<Widget> _resultSlivers() {
    Widget box(Widget child) => SliverToBoxAdapter(child: child);
    final header = _resultsHeader();
    return [
      if (_vm.hasSearched) ...[
        if (header != null) box(header) else box(const SizedBox(height: AppSpacing.lg)),
        box(TimeBlockFilterBar(selected: _vm.selectedTimeBlock, onSelected: _vm.setTimeBlock)),
        box(const SizedBox(height: AppSpacing.lg)),
      ],
      ..._listSlivers(),
      box(const SizedBox(height: AppSpacing.section)),
    ];
  }

  List<Widget> _listSlivers() {
    Widget box(Widget child) => SliverToBoxAdapter(child: child);
    if (_vm.isLoadingTrips) return [box(const _LoadingList())];

    if (_vm.error != null) {
      return [
        box(AppEmptyState(
          icon: Icons.cloud_off,
          title: 'Could not load trips',
          body: _vm.error!,
          fillViewport: false,
          action: FilledButton(onPressed: _vm.search, child: const Text('Try again')),
        )),
      ];
    }

    // Three empty states, not one. "Choose a journey" and "nothing runs
    // that day" are different situations and a single message for both
    // would leave the person unsure whether they had done something wrong.
    if (!_vm.hasSearched) {
      return [
        box(const AppEmptyState(
          icon: Icons.route_outlined,
          title: 'Where are you going?',
          body: 'Pick your boarding terminal and destination to see the '
              'departures running that journey.',
          fillViewport: false,
        )),
      ];
    }

    final trips = _vm.filteredTrips;
    if (trips.isEmpty) {
      // No button here: Any time and the Day field are just above, and a
      // second control for the same thing was redundant (20 Nov, the owner).
      final filtered = _vm.selectedTimeBlock != TimeBlock.all;
      return [
        box(AppEmptyState(
          icon: Icons.event_busy,
          title: 'No departures found',
          body: filtered
              ? 'No departures in this part of the day. Try "Any time".'
              : 'Nothing runs this journey on the day you picked. Pick another day above.',
          fillViewport: false,
        )),
      ];
    }

    // Separated, not margined: spacing between rows belongs to the list
    // that arranges them.
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        sliver: SliverList.separated(
          itemCount: trips.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, i) {
            final trip = trips[i];
            return TripCard(trip: trip, onTap: _booking ? null : () => _openDetails(trip));
          },
        ),
      ),
    ];
  }

  Widget? _tip() => _showCashTip
      ? Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 0),
          child: _CashTip(onClose: () => setState(() => _showCashTip = false)),
        )
      : null;

  Widget _narrow() => CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_tip() case final tip?) SliverToBoxAdapter(child: tip),
          SliverToBoxAdapter(child: JourneyPickerCard(vm: _vm)),
          ..._resultSlivers(),
        ],
      );

  Widget _wide() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 340,
            child: SingleChildScrollView(
              child: Column(children: [?_tip(), JourneyPickerCard(vm: _vm)]),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: _resultSlivers(),
            ),
          ),
        ],
      );
}

/// "Cash only": the rule most passengers have not met before, said once at
/// the top of Home in one line, and dismissable.
class _CashTip extends StatelessWidget {
  const _CashTip({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.edge),
        ),
        child: Row(children: [
          const Icon(Icons.payments_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          const Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'Cash only. ', style: TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: 'Reserve here, then pay the Dispatcher in cash at the terminal before your '
                    'pay-before time.'),
              ]),
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.35),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onClose,
            icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
          ),
        ]),
      );
}

/// Three quiet placeholder cards while departures load, the shape of what
/// is coming, instead of a spinner on an empty page. Still, so it needs no
/// reduce-motion handling.
class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: AppColors.surfaceSunken,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        );
    return Semantics(
      label: 'Loading departures',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: Column(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(height: AppSpacing.md),
              ExcludeSemantics(
                child: AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [bar(96, 22), const Spacer(), bar(64, 22)]),
                    const SizedBox(height: AppSpacing.md),
                    bar(200, 14),
                    const SizedBox(height: AppSpacing.sm),
                    bar(160, 14),
                    const SizedBox(height: AppSpacing.md),
                    bar(140, 24),
                  ]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
