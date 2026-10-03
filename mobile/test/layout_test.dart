import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_v2_uv_express/core/design/components/app_card.dart';
import 'package:mobile_v2_uv_express/core/design/components/empty_state.dart';
import 'package:mobile_v2_uv_express/core/design/components/info_row.dart';
import 'package:mobile_v2_uv_express/core/design/components/journey_strip.dart';
import 'package:mobile_v2_uv_express/core/design/components/money.dart';
import 'package:mobile_v2_uv_express/core/design/components/picker_row.dart';
import 'package:mobile_v2_uv_express/core/design/components/status_band.dart';
import 'package:mobile_v2_uv_express/core/design/components/status_chip.dart';
import 'package:mobile_v2_uv_express/models/transit_node_model.dart';
import 'package:mobile_v2_uv_express/models/uv_trip_model.dart';
import 'package:mobile_v2_uv_express/viewmodels/home_search_viewmodel.dart';
import 'package:mobile_v2_uv_express/data/repositories/operations_repository.dart';
import 'package:mobile_v2_uv_express/data/repositories/trip_repository.dart';
import 'package:mobile_v2_uv_express/views/auth/welcome_screen.dart';
import 'package:mobile_v2_uv_express/views/conductor/drive_panel.dart';
import 'package:mobile_v2_uv_express/views/home_search/widgets/time_block_filter.dart';
import 'package:mobile_v2_uv_express/views/home_search/widgets/trip_card.dart';
import 'package:mobile_v2_uv_express/views/home_search/widgets/trip_details_sheet.dart';
import 'package:mobile_v2_uv_express/views/passenger_main_screen.dart';

import 'support/harness.dart';

/// Layout, at the sizes and text scales real passengers use.
///
/// These tests assert one thing each: that laying the widget out reports no
/// exception. Flutter reports an overflow as an exception during layout, so a
/// silent `RenderFlex overflowed` — the defect that shipped a blank purple
/// welcome screen, and the one `flutter analyze` cannot see — fails here
/// instead of on someone's handset.
///
/// 200% is not an arbitrary ceiling: it is what WCAG 1.4.4 requires text to
/// survive, and the app claims to meet AA.
void main() {
  setUpAll(loadRealFonts);

  /// The long terminal names are the real ones from the Davao network. A
  /// layout that only holds "Digos" is not a layout that holds this route.
  UvTripModel trip({
    int seats = 8,
    double fare = 185,
    String origin = 'Davao City Overland Terminal',
    String destination = 'Digos City Integrated Transport Terminal',
  }) =>
      UvTripModel(
        id: 'TRIP-DEMO-00000001',
        tripLabel: 'Ecoland – Digos via Santa Cruz',
        departureTime: DateTime(2026, 10, 4, 5, 30),
        origin: TransitNodeModel(
            id: 'stop-1', name: origin, area: 'Davao City', stopSequence: 1),
        destination: TransitNodeModel(
            id: 'stop-4', name: destination, area: 'Digos', stopSequence: 4),
        boardingStop: 1,
        alightingStop: 4,
        availableSeats: seats,
        approximateFare: fare,
        plateNumber: 'ABC 1234',
      );

  /// Every case runs at both scales on the smallest phone, because that is
  /// where the width runs out, and once at a comfortable size to be sure the
  /// layout has not been built only to survive the hard case.
  void layoutCase(String name, Widget Function() build) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('$name · 320dp · ${(scale * 100).round()}% text',
          (tester) async {
        await pumpScreen(tester, build(),
            size: kSmallPhone, textScale: scale);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$name · 390dp · 100% text', (tester) async {
      await pumpScreen(tester, build());
      expect(tester.takeException(), isNull);
    });
  }

  // ── screens ────────────────────────────────────────────────────────────
  layoutCase('welcome', () => const WelcomeScreen());

  layoutCase(
    'navigation bar',
    () => Scaffold(
      bottomNavigationBar: PassengerNavBar(
        selectedIndex: 0,
        onSelected: (_) {},
      ),
    ),
  );

  layoutCase(
    'results list',
    () => Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TripCard(trip: trip(), onTap: () {}),
          const SizedBox(height: 12),
          // Scarce: the chip appears and has to share the row with a plate.
          TripCard(trip: trip(seats: 2), onTap: () {}),
          const SizedBox(height: 12),
          TripCard(trip: trip(seats: 0, fare: 1250), onTap: () {}),
        ],
      ),
    ),
  );

  layoutCase(
    'reserve sheet',
    () => Scaffold(
      body: TripDetailsSheet(trip: trip(seats: 2), onBook: () {}),
    ),
  );

  // ── components ─────────────────────────────────────────────────────────
  layoutCase(
    'journey strip',
    () => Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: JourneyStrip(
            origin: 'Davao City Overland Terminal',
            destination: 'Digos City Integrated Transport Terminal',
            originNote: 'Departs 5:30 AM',
            destinationNote: 'Arrives about 7:10 AM',
          ),
        ),
      ),
    ),
  );

  layoutCase(
    'status band',
    () => const Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: StatusBand(
            tone: StatusTone.warning,
            icon: Icons.schedule,
            title: 'Waiting for payment',
            body: 'Your space is held while the payment is pending. Pay to '
                'get the QR ticket the conductor scans.',
          ),
        ),
      ),
    ),
  );

  layoutCase(
    'picker row and info row',
    () => Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    AppPickerRow(
                      leading: const JourneyMarker(JourneyEnd.boarding),
                      label: 'From',
                      value: 'Davao City Overland Terminal',
                      placeholder: 'Choose a terminal',
                      onTap: () {},
                    ),
                    const Divider(height: 1),
                    AppPickerRow(
                      leading: const Icon(Icons.calendar_today_outlined,
                          size: 16),
                      label: 'Travel date',
                      value: null,
                      placeholder: 'Pick a date',
                      onTap: () {},
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  children: [
                    const AppInfoRow(
                      label: 'Passenger',
                      value: 'Maria Consolacion Dela Cruz-Villanueva',
                    ),
                    const SizedBox(height: 12),
                    AppInfoRow(
                      label: 'Fare',
                      value: Money.format(1250),
                      valueWidget: const Money(1250),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  layoutCase(
    'time filter',
    () => Scaffold(
      body: TimeBlockFilterBar(
        selected: TimeBlock.nextAvailable,
        onSelected: (_) {},
      ),
    ),
  );

  layoutCase(
    'empty state',
    () => const Scaffold(
      body: AppEmptyState(
        icon: Icons.route_outlined,
        title: 'Where are you going?',
        body: 'Pick your boarding terminal and destination to see the '
            'departures running that journey.',
      ),
    ),
  );

  // ── driver ─────────────────────────────────────────────────────────────
  // The drive panel sets the next stop at 32sp and the figures at 40sp so
  // they read at a glance; that is exactly what overflows first on a small
  // phone at 200% text, with a real terminal name.
  RouteStopDetail stop(int seq, String name) => RouteStopDetail(
        stopSequence: seq,
        terminalId: 'term-$seq',
        terminalName: name,
        city: 'Davao',
        offsetMinutes: (seq - 1) * 30,
        latitude: 7.0,
        longitude: 125.6,
      );
  ManifestPassenger rider(int on, int off, String status) => ManifestPassenger(
        bookingId: 'b-$on-$off-$status',
        ticketNumber: 'SG-0001',
        boardingStop: on,
        alightingStop: off,
        bookingType: 'app',
        status: status,
        fare: 110,
        fareIsManual: false,
        isRoadsidePickup: false,
      );
  final crewTrip = CrewTrip(
    tripId: 'TRIP-DEMO-00000001',
    routeName: 'Ecoland – Digos via Santa Cruz',
    serviceDate: DateTime(2026, 10, 4),
    departure: DateTime(2026, 10, 4, 5, 30),
    status: 'departed',
    seatCapacity: 14,
    roleOnTrip: 'driver',
    stops: [
      stop(1, 'Davao City Overland Terminal'),
      stop(2, 'Toril Public Market Terminal'),
      stop(3, 'Digos City Integrated Transport Terminal'),
    ],
    plateNumber: 'ABC 1234',
  );
  final manifest = Manifest(
    tripId: crewTrip.tripId,
    departure: crewTrip.departure,
    status: 'departed',
    seatCapacity: 14,
    totalBookings: 4,
    boarded: 3,
    checkedIn: 1,
    awaiting: 0,
    unpaid: 0,
    passengers: [
      rider(1, 2, 'boarded'),
      rider(1, 3, 'boarded'),
      rider(1, 3, 'boarded'),
      rider(2, 3, 'checked_in'),
    ],
  );

  layoutCase(
    'drive panel',
    () => Scaffold(
      body: SingleChildScrollView(
        child: DrivePanel(
          trip: crewTrip,
          manifest: manifest,
          currentStop: 1,
          onArrived: (_) {},
        ),
      ),
    ),
  );

  layoutCase(
    'drive panel · final stop',
    () => Scaffold(
      body: SingleChildScrollView(
        child: DrivePanel(
          trip: crewTrip,
          manifest: manifest,
          currentStop: 3,
          onArrived: (_) {},
        ),
      ),
    ),
  );

  // The figures are what a driver acts on, so they are asserted, not only
  // laid out: leg 1 carries all three boarded riders; one gets off at
  // stop 2 and the checked-in passenger waits there.
  testWidgets('drive panel counts by leg', (tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: DrivePanel(
          trip: crewTrip,
          manifest: manifest,
          currentStop: 1,
          onArrived: (_) {},
        ),
      ),
    );
    expect(find.bySemanticsLabel('3 Aboard now'), findsOneWidget);
    expect(find.bySemanticsLabel('1 Getting off next'), findsOneWidget);
    expect(find.bySemanticsLabel('1 To pick up next'), findsOneWidget);
    expect(find.text('Toril Public Market Terminal'), findsOneWidget);
  });

  // Opens the real dialog at the hardest size and drives it: starts at
  // zero (never the manifest's figure), cannot go below it, and returns
  // what was counted.
  for (final scale in const [1.0, 2.0]) {
    testWidgets('headcount stepper · 320dp · ${(scale * 100).round()}% text', (tester) async {
      int? result;
      await pumpScreen(
        tester,
        // The app theme's InkSparkle splash loads a shader the headless
        // test renderer has no build of, so a tap would fail on the ripple
        // rather than on anything under test. A plain ripple here.
        Builder(
          builder: (context) => Theme(
            data: Theme.of(context).copyWith(splashFactory: InkRipple.splashFactory),
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () async => result = await showHeadcountDialog(context,
                        stopName: 'Toril Public Market Terminal', seatCapacity: 14),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
        size: kSmallPhone,
        textScale: scale,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Record 0 aboard'), findsOneWidget);

      await tester.tap(find.byTooltip('One fewer'));
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byTooltip('One more'));
      }
      await tester.pump();
      await tester.tap(find.text('Record 3 aboard'));
      await tester.pumpAndSettle();
      expect(result, 3);
    });
  }
}
