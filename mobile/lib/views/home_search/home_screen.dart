import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/empty_state.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/booking_repository.dart';
import '../../data/repositories/trip_repository.dart';
import '../../models/uv_trip_model.dart';
import '../../viewmodels/home_search_viewmodel.dart';
import '../ticket/ticket_screen.dart';
import 'widgets/journey_picker_card.dart';
import 'widgets/time_block_filter.dart';
import 'widgets/trip_card.dart';
import 'widgets/trip_details_sheet.dart';

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
          builder: (_) => TicketScreen(bookedTrip: trip, reservation: result),
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

  Widget _tripList() {
    if (_vm.isLoadingTrips) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_vm.error != null) {
      return AppEmptyState(
        icon: Icons.cloud_off,
        title: 'Could not load trips',
        body: _vm.error!,
        action: FilledButton(
          onPressed: _vm.search,
          child: const Text('Try again'),
        ),
      );
    }

    // Three empty states, not one. "Choose a journey" and "nothing runs
    // that day" are different situations and a single message for both
    // would leave the person unsure whether they had done something
    // wrong.
    if (!_vm.hasSearched) {
      return const AppEmptyState(
        icon: Icons.route_outlined,
        title: 'Where are you going?',
        body: 'Pick your boarding terminal and destination to see the '
            'departures running that journey.',
      );
    }

    final trips = _vm.filteredTrips;
    if (trips.isEmpty) {
      return AppEmptyState(
        icon: Icons.event_busy,
        title: 'No departures found',
        body: _vm.selectedTimeBlock == TimeBlock.all
            ? 'Nothing runs this journey on the date you picked. Try '
                'another day.'
            : 'No departures in this time block. Try "All".',
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      itemCount: trips.length,
      itemBuilder: (context, i) {
        final trip = trips[i];
        final card = TripCard(trip: trip);
        return Semantics(
          button: true,
          // The card owns the sentence, so the spoken and the printed
          // versions cannot drift apart. Children are excluded to stop a
          // screen reader reading the same row twice.
          label: '${card.semanticSummary()} Opens trip details.',
          excludeSemantics: true,
          child: InkWell(
          onTap: _booking
              ? null
              : () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (sheetContext) => TripDetailsSheet(
                      trip: trip,
                      onBook: () {
                        Navigator.pop(sheetContext);
                        _handleBook(trip);
                      },
                    ),
                  ),
          child: card,
          ),
        );
      },
    );
  }

  Widget _narrow() => Column(
        children: [
          JourneyPickerCard(vm: _vm),
          if (_vm.hasSearched)
            TimeBlockFilterBar(
              selected: _vm.selectedTimeBlock,
              onSelected: _vm.setTimeBlock,
            ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _tripList()),
        ],
      );

  Widget _wide() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 340, child: JourneyPickerCard(vm: _vm)),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.md),
                if (_vm.hasSearched)
                  TimeBlockFilterBar(
                    selected: _vm.selectedTimeBlock,
                    onSelected: _vm.setTimeBlock,
                  ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(child: _tripList()),
              ],
            ),
          ),
        ],
      );
}
