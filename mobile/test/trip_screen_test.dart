import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_v2_uv_express/core/design/components/status_chip.dart';
import 'package:mobile_v2_uv_express/core/design/tokens.dart';
import 'package:mobile_v2_uv_express/core/network/api_client.dart';
import 'package:mobile_v2_uv_express/core/offline/offline_sync_service.dart';
import 'package:mobile_v2_uv_express/core/offline/pending_walk_in.dart';
import 'package:mobile_v2_uv_express/core/offline/seat_mark_queue.dart';
import 'package:mobile_v2_uv_express/core/storage/token_storage.dart';
import 'package:mobile_v2_uv_express/data/repositories/operations_repository.dart';
import 'package:mobile_v2_uv_express/viewmodels/shift_viewmodel.dart';
import 'package:mobile_v2_uv_express/views/dispatcher/trip_manifest_screen.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

class _Token extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => 'test';

  @override
  Future<void> clear() async {}
}

/// Nothing waiting offline. The real service opens SQLite and listens to
/// the connectivity plugin, neither of which runs under `flutter test`.
class _NoOffline extends ChangeNotifier implements OfflineSyncService {
  @override
  List<PendingWalkIn> pendingFor(String tripId) => const [];
  @override
  Map<String, PendingSeatMark> marksFor(String tripId) => const {};
  @override
  List<String> takeNotices() => const [];
  @override
  Future<void> flush() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The whole Dispatcher trip screen after the 20 Nov redesign, against a
/// fake server: header, tabs, cards and the pinned action bar must lay out
/// together, at 320 dp and 200 % text, in each of the trip's main states.
void main() {
  setUpAll(loadRealFonts);

  const tripId = 'TRIP-1';
  final dep = DateTime(2026, 11, 20, 10, 30);
  final stops = [
    for (final (i, name) in ['Cooperative Van Terminal – Ecoland', 'Digos City Terminal', 'Kidapawan City Terminal',
      'Cotabato City Terminal'].indexed)
      {
        'stop_sequence': i + 1,
        'terminal_id': 'T$i',
        'terminal_name': name,
        'city': 'Mindanao',
        'offset_minutes': i * 60,
        'latitude': 7.0,
        'longitude': 125.0,
      },
  ];

  Map<String, dynamic> crewTrip(String status, {Map<String, dynamic>? rental}) => {
        'trip_id': tripId,
        'trip_label': 'Davao (Ecoland) – Cotabato City',
        'route_name': 'Davao (Ecoland) – Cotabato City',
        'service_date': '2026-11-20',
        'departure_datetime': dep.toIso8601String(),
        'status': status,
        'plate_number': 'TST-1023',
        'seat_capacity': 14,
        'stops': stops,
        'operator_name': 'Arnel Bautista',
        'operator_licence': 'D01-23-456789',
        'payment_status': 'unpaid',
        'crew_aboard': false,
        'rental': rental,
      };

  Map<String, dynamic> passenger(String code, String status, String pay, {String type = 'app'}) => {
        'booking_id': 'B-$code',
        'booking_code': code,
        'booking_type': type,
        'boarding_stop': 1,
        'alighting_stop': 4,
        'fare_amount': '363.00',
        'name': 'Maria Consolacion Dela Cruz-Villanueva',
        'payment_status': pay,
        'status': status,
        'passenger_name': 'Maria Consolacion Dela Cruz-Villanueva',
        'contact_number': null,
        'is_home_pickup_seat': false,
        'paid_at': null,
      };

  Map<String, dynamic> manifest(String status) => {
        'trip_id': tripId,
        'trip_label': 'Davao (Ecoland) – Cotabato City',
        'departure_datetime': dep.toIso8601String(),
        'status': status,
        'seat_capacity': 14,
        'total_bookings': 3,
        'unpaid': 2,
        'checked_in': 1,
        'boarded': status == 'departed' ? 1 : 0,
        'awaiting': 0,
        'passengers': [
          passenger('SG-7K2Q9M', status == 'departed' ? 'boarded' : 'checked_in', 'unpaid'),
          passenger('SG-4M8P2L', 'confirmed', 'unpaid'),
          passenger('SG-2B6N8K', status == 'departed' ? 'boarded' : 'confirmed', 'paid'),
        ],
      };

  final share = {
    'payment_status': 'unpaid',
    'amount_due': '567.00',
    'disputed': '0',
    'operator_share_owed': '2373.00',
    'operator_share_given': '0',
    'operator_share_held': '0',
    'operator_share_over': '0',
    'lines': [
      {
        'line_id': 'L1',
        'dest_terminal_name': 'Cotabato City Terminal',
        'passenger_count': 3,
        'fare_per_passenger': '363.00',
        'share_amount': '163.35',
        'is_top_up': false,
      },
    ],
  };

  ApiClient server({required String status, Map<String, dynamic>? rental, bool mismatch = true}) => ApiClient(
        tokenStorage: _Token(),
        baseUrl: 'http://x/api/v1',
        httpClient: MockClient((req) async {
          final p = req.url.path.replaceFirst('/api/v1', '');
          Object? body = switch (p) {
            '/trips/$tripId/manifest' => manifest(status),
            '/trips/$tripId/door-check' => {
                'aboard': mismatch ? 4 : null,
                'camera': mismatch ? 'live' : 'no_phone',
                'listed': 3,
                'explained': 0,
                'excess': mismatch ? 1 : 0,
                'crew_aboard': false,
                'unlisted': [
                  if (mismatch)
                    {
                      'event_id': 'E1',
                      'event_at': dep.subtract(const Duration(minutes: 5)).toIso8601String(),
                      'resolution_status': 'pending',
                      'resolution_note': null,
                    },
                ],
              },
            '/trips/$tripId/share' => share,
            '/bookings/trip/$tripId/seats' => [
                for (final s in (manifest(status)['passengers'] as List)) s,
              ],
            '/home-pickups' => [
                {
                  'pickup_id': 'P1',
                  'beneficiary_name': 'Nenita Bautista-Villanueva',
                  'beneficiary_contact': '09008234567',
                  'pickup_latitude': '7.05',
                  'pickup_longitude': '125.58',
                  'pickup_note': 'Green gate beside the sari-sari store',
                  'status': 'requested',
                  'photo_message_id': null,
                  'arrived_at': null,
                },
              ],
            '/driving-flags' => [
                {
                  'driving_event_id': 'F1',
                  'flag_type': 'Over the speed limit',
                  'start_at': dep.add(const Duration(minutes: 40)).toIso8601String(),
                  'place': 'near Digos',
                  'flagged': true,
                  'review_status': 'open',
                  'dispute_status': null,
                },
              ],
            _ => null,
          };
          return body == null
              ? http.Response(jsonEncode({'detail': 'Not found.'}), 404)
              : http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );

  Widget screen(ApiClient api, CrewTrip trip) => MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<OfflineSyncService>(create: (_) => _NoOffline()),
          ChangeNotifierProvider<ShiftViewModel>(create: (_) => ShiftViewModel(OperationsRepository(api))),
        ],
        child: TripManifestScreen(trip: trip),
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  final states = {
    'boarding, camera counts one more than listed': (
      server(status: 'boarding'),
      CrewTrip.fromJson(crewTrip('boarding')),
    ),
    'boarding, no camera phone': (
      server(status: 'boarding', mismatch: false),
      CrewTrip.fromJson(crewTrip('boarding')),
    ),
    'on the road': (server(status: 'departed'), CrewTrip.fromJson(crewTrip('departed'))),
    'van rental': (
      server(status: 'boarding'),
      CrewTrip.fromJson(crewTrip('boarding', rental: {
        'request_id': 'R1',
        'customer_name': 'Ramil Sevilla',
        'customer_contact': '09007112233',
        'pickup_address': 'Matina Town Square, Davao City',
        'destination_address': 'Lake Sebu, South Cotabato',
        'passenger_count': 14,
        'rental_fee': '3500.00',
        'payment_status': 'unpaid',
      })),
    ),
  };

  for (final MapEntry(key: name, value: (api, trip)) in states.entries) {
    for (final (size, scale) in [(kSmallPhone, 1.0), (kSmallPhone, 2.0), (kPhone, 1.0)]) {
      testWidgets('trip screen · $name · ${size.width.round()}dp · ${(scale * 100).round()}% text', (tester) async {
        await pumpScreen(tester, screen(api, trip), size: size, textScale: scale);
        await settle(tester);
        expect(tester.takeException(), isNull);
        // Every tab lays out too, not only the first.
        for (final label in ['Pickups', 'Fees & flags', 'Rental']) {
          final tab = find.textContaining(label, findRichText: true);
          if (tab.evaluate().isEmpty) continue;
          await tester.tap(tab.first, warnIfMissed: false);
          await settle(tester);
          expect(tester.takeException(), isNull, reason: 'the $label tab');
        }
      });
    }
  }

  testWidgets('Depart is held, with its reason, while the camera counts more than listed', (tester) async {
    final (api, trip) = states['boarding, camera counts one more than listed']!;
    await pumpScreen(tester, screen(api, trip));
    await settle(tester);
    expect(find.textContaining('Depart waits:'), findsOneWidget);
    final depart = tester.widget<ButtonStyleButton>(
        find.ancestor(of: find.text('Depart'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first);
    expect(depart.onPressed, isNull);
  });

  testWidgets('no camera phone: the count says Not counted, never 0', (tester) async {
    final (api, trip) = states['boarding, no camera phone']!;
    await pumpScreen(tester, screen(api, trip));
    await settle(tester);
    expect(find.text('Not counted'), findsOneWidget);
    expect(find.text('NOT COUNTED'), findsOneWidget);
  });

  // 20 Nov: on the passenger list, each passenger's state and fare sit at
  // the card's right edge, under the LOCKED chip, a clear gap from the name
  // and the route; they used to sit against the text, mid-row.
  for (final (size, scale) in [(const Size(408, 860), 1.0), (kSmallPhone, 1.0), (kSmallPhone, 2.0)]) {
    testWidgets('trip screen · passenger list: state and fare at the right edge · '
        '${size.width.round()}dp · ${(scale * 100).round()}% text', (tester) async {
      final (api, trip) = states['on the road']!;
      await pumpScreen(tester, screen(api, trip), size: size, textScale: scale);
      await settle(tester);
      expect(tester.takeException(), isNull);
      // At large text the list is far down the tab: scroll to its header,
      // which brings the first row with it.
      await tester.scrollUntilVisible(find.text('LOCKED'), 120,
          scrollable: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first);
      final locked = find.ancestor(of: find.text('LOCKED'), matching: find.byType(StatusChip)).first;
      final boarded = find.ancestor(of: find.text('BOARDED').first, matching: find.byType(StatusChip)).first;
      expect(tester.getRect(boarded).right, closeTo(tester.getRect(locked).right, 0.5),
          reason: 'lined up with the right edge of the card');
      final words = tester.getRect(find
          .ancestor(of: find.text('Maria Consolacion Dela Cruz-Villanueva').first, matching: find.byType(Column))
          .first);
      final state = tester.getRect(find.ancestor(of: boarded, matching: find.byType(Column)).first);
      expect(state.left - words.right, greaterThanOrEqualTo(AppSpacing.lg - 0.5), reason: 'a clear gap from the name');
    });
  }

  // 20 Nov: the four counts are one size in every layout ("At terminal"
  // wraps on a narrow phone), and the van line has a row of its own under
  // the bar, whole where the screen allows. 363 dp is the owner's preview.
  for (final (size, scale) in [(const Size(363, 760), 1.0), (kSmallPhone, 1.0), (kSmallPhone, 2.0), (kPhone, 1.0)]) {
    testWidgets('trip screen · the four counts are one size · ${size.width.round()}dp · ${(scale * 100).round()}% text',
        (tester) async {
      final (api, trip) = states['on the road']!;
      await pumpScreen(tester, screen(api, trip), size: size, textScale: scale);
      await settle(tester);
      expect(tester.takeException(), isNull);
      // By the words under each count: at large text the card around them
      // is read as one label, so a tile has no label of its own to find.
      Rect tile(String label) =>
          tester.getRect(find.ancestor(of: find.text(label), matching: find.byType(Container)).first);
      final paid = tile('Paid');
      for (final label in ['Unpaid', 'At terminal', 'Seats left']) {
        expect(tile(label).size, paid.size, reason: '$label is the size of Paid');
      }
      expect(tile('Unpaid').top, paid.top, reason: 'a row lines up');
      expect(tile('Seats left').top, tile('At terminal').top, reason: 'a row lines up');
      if (scale == 1.0) {
        final line = tester.renderObject<RenderParagraph>(
            find.textContaining('Licence D01-23-456789', findRichText: true));
        expect(line.didExceedMaxLines, isFalse, reason: 'the van line is whole');
      }
    });
  }
}
