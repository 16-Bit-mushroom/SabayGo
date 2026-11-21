import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_v2_uv_express/core/offline/seat_mark_queue.dart';
import 'package:mobile_v2_uv_express/data/repositories/operations_repository.dart';
import 'package:mobile_v2_uv_express/views/dispatcher/dashboard_panels.dart';
import 'package:mobile_v2_uv_express/views/dispatcher/walk_in_screen.dart';

import 'support/harness.dart';

/// The Dispatcher's trip screen pieces after the 20 Nov redesign, laid out
/// at the sizes and text scales used at a van door: each case must lay out
/// with no overflow on the smallest phone at 100 % and 200 % text, and meet
/// flutter_test's tap-target, label and contrast guidelines at 390 dp.
void main() {
  setUpAll(loadRealFonts);

  void layoutCase(String name, Widget Function() build, {bool checkContrast = true}) {
    Widget screen() => Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: build()),
          ),
        );
    for (final scale in const [1.0, 2.0]) {
      testWidgets('$name · 320dp · ${(scale * 100).round()}% text', (tester) async {
        await pumpScreen(tester, screen(), size: kSmallPhone, textScale: scale);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('$name · 390dp · 100% text', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, screen());
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      if (checkContrast) await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    });
  }

  final now = DateTime(2026, 11, 20, 10, 42);
  UnlistedBoarding unlisted(String id, String status, {String? note}) => UnlistedBoarding.fromJson({
        'event_id': id,
        'event_at': now.toIso8601String(),
        'resolution_status': status,
        'resolution_note': note,
      });
  SeatOnList seat(String code, {String status = 'confirmed', String pay = 'unpaid', String type = 'app'}) =>
      SeatOnList.fromJson({
        'booking_id': 'B-$code',
        'booking_code': code,
        'passenger_name': 'Maria Consolacion Dela Cruz-Villanueva',
        'contact_number': null,
        'alighting_stop': 4,
        'fare_amount': '363.00',
        'booking_type': type,
        'status': status,
        'payment_status': pay,
        'is_home_pickup_seat': false,
        'paid_at': null,
      });

  // ── Boarding tab ───────────────────────────────────────────────────────
  layoutCase(
    'door camera · no phone, not counted',
    () => DoorCheckPanel(
      check: const DoorCheck(
        aboard: null,
        camera: 'no_phone',
        listed: 3,
        explained: 0,
        excess: 0,
        crewAboard: false,
        unlisted: [],
      ),
      busy: false,
      onList: (_) {},
      onExplain: (_) {},
      onCrew: (_) {},
    ),
  );

  layoutCase(
    'door camera · more aboard than listed',
    () => DoorCheckPanel(
      check: DoorCheck(
        aboard: 6,
        camera: 'live',
        listed: 3,
        explained: 1,
        excess: 2,
        crewAboard: true,
        unlisted: [
          unlisted('E1', 'pending'),
          unlisted('E2', 'pending'),
          unlisted('E3', 'explained', note: 'The operator\'s child, riding free to the next terminal'),
        ],
      ),
      busy: false,
      onList: (_) {},
      onExplain: (_) {},
      onCrew: (_) {},
    ),
  );

  layoutCase(
    'trip counts',
    () => const TripCounts(paid: 9, unpaid: 3, atTerminal: 1, seatsLeft: 2),
  );

  layoutCase(
    'seat cards',
    () => Column(children: [
      SeatCard(
        seat: seat('SG-7K2Q9M', status: 'checked_in'),
        stopName: 'Cotabato City Terminal',
        busy: false,
        onPaid: () {},
        onCancel: () {},
      ),
      const SizedBox(height: 12),
      SeatCard(
        seat: seat('SG-4M8P2L', pay: 'paid'),
        stopName: 'Kidapawan City Terminal',
        busy: false,
        onPaid: () {},
        onCancel: () {},
      ),
      const SizedBox(height: 12),
      SeatCard(
        seat: seat('SG-9R1T5W'),
        stopName: 'Digos City Terminal',
        mark: PendingSeatMark(
            bookingId: 'B-SG-9R1T5W', tripId: 'T', kind: 'paid', at: now, label: 'Maria'),
        busy: false,
        onPaid: () {},
        onCancel: () {},
      ),
    ]),
  );

  // ── Pickups, Rental ────────────────────────────────────────────────────
  layoutCase(
    'home pickups',
    () => HomePickupsPanel(
      pickups: [
        HomePickup.fromJson({
          'pickup_id': 'P1',
          'beneficiary_name': 'Nenita Bautista-Villanueva',
          'beneficiary_contact': '09008234567',
          'pickup_latitude': '7.051048',
          'pickup_longitude': '125.587456',
          'pickup_note': 'Green gate beside the sari-sari store',
          'status': 'requested',
          'photo_message_id': 'M1',
          'arrived_at': null,
        }),
        HomePickup.fromJson({
          'pickup_id': 'P2',
          'beneficiary_name': 'Lola Nena',
          'beneficiary_contact': '09008234568',
          'pickup_latitude': '7.0',
          'pickup_longitude': '125.5',
          'pickup_note': null,
          'status': 'arrived',
          'photo_message_id': null,
          'arrived_at': now.toIso8601String(),
        }),
      ],
      departed: true,
      busy: false,
      onAction: (_, _) {},
    ),
  );

  layoutCase(
    'van rental · fee unpaid',
    () => RentalPanel(
      rental: Rental.fromJson({
        'request_id': 'R1',
        'customer_name': 'Ramil Sevilla',
        'customer_contact': '09007112233',
        'pickup_address': 'Matina Town Square, Davao City',
        'destination_address': 'Lake Sebu, South Cotabato',
        'passenger_count': 14,
        'rental_fee': '3500.00',
        'payment_status': 'unpaid',
      }),
      busy: false,
      onCash: () {},
    ),
  );

  // ── Fees & flags ───────────────────────────────────────────────────────
  layoutCase(
    'terminal fees',
    () => SharePanel(
      share: TripShare.fromJson({
        'payment_status': 'unpaid',
        'amount_due': '567.00',
        'disputed': '54.45',
        'operator_share_owed': '2373.00',
        'operator_share_given': '0',
        'operator_share_held': '0',
        'operator_share_over': '0',
        'lines': [
          {
            'line_id': 'L1',
            'dest_terminal_name': 'Cotabato City Terminal',
            'passenger_count': 4,
            'fare_per_passenger': '363.00',
            'share_amount': '217.80',
            'is_top_up': false,
          },
          {
            'line_id': 'L2',
            'dest_terminal_name': 'Kidapawan City Terminal',
            'passenger_count': 1,
            'fare_per_passenger': '340.00',
            'share_amount': '51.00',
            'is_top_up': true,
          },
        ],
      }),
      disputedLines: const {'L2'},
      busy: false,
      onDispute: (_) {},
    ),
  );

  layoutCase(
    'driving flags',
    () => FlagsPanel(
      flags: [
        TripFlag.fromJson({
          'driving_event_id': 'F1',
          'flag_type': 'Over the speed limit',
          'start_at': now.toIso8601String(),
          'place': 'between Digos and Bansalan',
          'flagged': true,
          'review_status': 'open',
          'dispute_status': null,
        }),
      ],
      busy: false,
      onDispute: (_) {},
    ),
  );

  // ── Walk-in till ───────────────────────────────────────────────────────
  layoutCase(
    'walk-in destinations',
    () => Column(children: [
      DestinationTile(name: 'Kidapawan City Terminal', selected: true, fare: 340, peso: _peso, onTap: () {}),
      const SizedBox(height: 8),
      DestinationTile(
          name: 'Cotabato City Integrated Terminal', selected: false, fare: null, peso: _peso, onTap: () {}),
    ]),
  );
}

String _peso(double v) => '₱${v.toStringAsFixed(2)}';
