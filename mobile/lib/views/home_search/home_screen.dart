import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
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
      // and the wording should not imply the trip is full.
      _snack('The seat map is busy. Please try again.');
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
      return _Placeholder(
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
      return const _Placeholder(
        icon: Icons.route_outlined,
        title: 'Where are you going?',
        body: 'Pick your boarding terminal and destination to see the '
            'departures running that journey.',
      );
    }

    final trips = _vm.filteredTrips;
    if (trips.isEmpty) {
      return _Placeholder(
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
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: trips.length,
      itemBuilder: (context, i) {
        final trip = trips[i];
        return InkWell(
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
          child: TripCard(trip: trip),
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
          const SizedBox(height: 8),
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
                const SizedBox(height: 12),
                if (_vm.hasSearched)
                  TimeBlockFilterBar(
                    selected: _vm.selectedTimeBlock,
                    onSelected: _vm.setTimeBlock,
                  ),
                const SizedBox(height: 8),
                Expanded(child: _tripList()),
              ],
            ),
          ),
        ],
      );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({
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
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: constraints.maxHeight,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 52, color: AppColors.textMuted),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      height: 1.4,
                    ),
                  ),
                  if (action != null) ...[const SizedBox(height: 20), action!],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}