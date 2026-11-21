import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_v2_uv_express/core/network/api_client.dart';
import 'package:mobile_v2_uv_express/core/storage/token_storage.dart';
import 'package:mobile_v2_uv_express/data/repositories/auth_repository.dart';
import 'package:mobile_v2_uv_express/data/repositories/booking_repository.dart';
import 'package:mobile_v2_uv_express/viewmodels/auth_provider.dart';
import 'package:mobile_v2_uv_express/views/home_search/home_screen.dart';
import 'package:mobile_v2_uv_express/views/reservations/reservation_screen.dart';
import 'package:mobile_v2_uv_express/views/reservations/reservations_screen.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

class _Token extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => 'test';

  @override
  Future<void> clear() async {}
}

/// The passenger's booking screens after the 20 Nov redesign (phase 2),
/// whole, against a fake server: every state must lay out at 320 dp and
/// 200 % text, and meet the tap-target and label guidelines at 390 dp.
void main() {
  setUpAll(loadRealFonts);
  // Home remembers the last journey in the phone's secure store, which has
  // no platform under `flutter test`.
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  final dep = DateTime.now().add(const Duration(hours: 1, minutes: 20));

  Map<String, dynamic> booking(
    String id, {
    String status = 'confirmed',
    String pay = 'unpaid',
    bool canCancel = true,
    String? cancelReason,
    DateTime? at,
    String tripStatus = 'scheduled',
  }) {
    final when = at ?? dep;
    return {
      'booking_id': id,
      'booking_code': 'SG-7K2Q9M',
      'trip_id': 'TRIP-$id',
      'route_id': 'R1',
      'route_name': 'Davao (Ecoland) – Cotabato City',
      'departure_datetime': when.toIso8601String(),
      'boarding_stop': 1,
      'alighting_stop': 4,
      'boarding_terminal': 'Cooperative Van Terminal – Ecoland',
      'alighting_terminal': 'Cotabato City Integrated Transport Terminal',
      'fare_amount': '363.00',
      'status': status,
      'trip_status': tripStatus,
      'payment_status': pay,
      'paid_at': pay == 'paid' ? when.subtract(const Duration(minutes: 40)).toIso8601String() : null,
      'can_cancel': canCancel,
      'cancel_reason': cancelReason,
      'pay_by': when.subtract(const Duration(minutes: 30)).toIso8601String(),
      'boarding_due_at': null,
      'checkin_opens_at': when.subtract(const Duration(minutes: 60)).toIso8601String(),
      'home_pickup': null,
    };
  }

  ApiClient server(Object? Function(String path) answer) => ApiClient(
        tokenStorage: _Token(),
        baseUrl: 'http://x/api/v1',
        httpClient: MockClient((req) async {
          final body = answer(req.url.path.replaceFirst('/api/v1', ''));
          return body == null
              ? http.Response(jsonEncode({'detail': 'Not found.'}), 404)
              : http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );

  Widget wrap(ApiClient api, Widget child) => MultiProvider(
        providers: [
          Provider<ApiClient>.value(value: api),
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => AuthProvider(repository: AuthRepository(api), tokens: _Token()),
          ),
        ],
        child: child,
      );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void screenCase(String name, Widget Function() build) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('$name · 320dp · ${(scale * 100).round()}% text', (tester) async {
        await pumpScreen(tester, build(), size: kSmallPhone, textScale: scale);
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('$name · 390dp · 100% text', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, build());
      await settle(tester);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });
  }

  // ── Reservation, in each state the passenger meets ─────────────────────
  final reservations = {
    'reserved, unpaid': booking('B1'),
    'here to pay': booking('B2', status: 'checked_in'),
    'paid': booking('B3', pay: 'paid', canCancel: false),
    'released, unpaid': booking('B4', status: 'cancelled', canCancel: false, cancelReason: 'auto_release'),
    'on board': booking('B5', status: 'boarded', pay: 'paid', canCancel: false, tripStatus: 'departed'),
  };
  for (final MapEntry(key: name, value: json) in reservations.entries) {
    screenCase('reservation · $name', () {
      final api = server((p) => p == '/bookings/${json['booking_id']}' ? json : null);
      return wrap(api, ReservationScreen.fromBooking(booking: BookingSummary.fromJson(json)));
    });
  }

  testWidgets('reservation · the code comes first, and a released seat offers Book again', (tester) async {
    final json = reservations['released, unpaid']!;
    final api = server((p) => p == '/bookings/${json['booking_id']}' ? json : null);
    await pumpScreen(tester, wrap(api, ReservationScreen.fromBooking(booking: BookingSummary.fromJson(json))));
    await settle(tester);
    expect(find.text('BOOKING CODE'), findsOneWidget);
    expect(find.text('Book again'), findsOneWidget);
    final codeY = tester.getTopLeft(find.text('BOOKING CODE')).dy;
    final bandY = tester.getTopLeft(find.text('Released: not paid in time')).dy;
    expect(codeY, lessThan(bandY));
  });

  testWidgets('reservation · unpaid: the pay-by time on the band and in the details, not a third time', (tester) async {
    final json = reservations['reserved, unpaid']!;
    final api = server((p) => p == '/bookings/${json['booking_id']}' ? json : null);
    await pumpScreen(tester, wrap(api, ReservationScreen.fromBooking(booking: BookingSummary.fromJson(json))));
    await settle(tester);
    expect(find.text('Pay before'), findsOneWidget);
    expect(find.textContaining('By '), findsNothing);
    expect(find.text("I'm here to pay"), findsOneWidget);
  });

  // ── Trips ──────────────────────────────────────────────────────────────
  screenCase('trips · next, also booked, past and cancelled', () {
    final api = server((p) => p == '/bookings/mine'
        ? [
            booking('N1'),
            booking('N2', at: dep.add(const Duration(days: 1))),
            booking('P1', status: 'completed', pay: 'paid', canCancel: false,
                at: dep.subtract(const Duration(days: 3)), tripStatus: 'completed'),
            booking('C1', status: 'cancelled', canCancel: false, cancelReason: 'auto_release',
                at: dep.subtract(const Duration(days: 1))),
          ]
        : null);
    return wrap(api, const Scaffold(body: ReservationsScreen()));
  });

  screenCase('trips · nothing booked', () {
    final api = server((p) => p == '/bookings/mine' ? <Object>[] : null);
    return wrap(api, const Scaffold(body: ReservationsScreen()));
  });

  testWidgets('trips · nothing booked: the card alone, no heading over it', (tester) async {
    final api = server((p) => p == '/bookings/mine' ? <Object>[] : null);
    await pumpScreen(tester, wrap(api, const Scaffold(body: ReservationsScreen())));
    await settle(tester);
    expect(find.text('Find a departure'), findsOneWidget);
    expect(find.text('Next trip'), findsNothing);
    expect(find.text('Upcoming'), findsNothing);
  });

  testWidgets('trips · booked: one Upcoming heading with the count', (tester) async {
    final api = server((p) => p == '/bookings/mine'
        ? [booking('N1'), booking('N2', at: dep.add(const Duration(days: 1)))]
        : null);
    await pumpScreen(tester, wrap(api, const Scaffold(body: ReservationsScreen())));
    await settle(tester);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('2 trips booked'), findsOneWidget);
    expect(find.text('Also booked'), findsNothing);
  });

  // ── Home ───────────────────────────────────────────────────────────────
  Object? terminals(String p) => p == '/trips/terminals'
      ? [
          for (final (i, name) in ['Cooperative Van Terminal – Ecoland', 'Digos City Terminal',
            'Kidapawan City Terminal', 'Cotabato City Integrated Transport Terminal'].indexed)
            {'terminal_id': 'T$i', 'terminal_name': name, 'city': 'Mindanao', 'stop_sequence': i + 1},
        ]
      : null;

  screenCase('home · before a journey is chosen', () => wrap(server(terminals), const Scaffold(body: HomeScreen())));

  testWidgets('home · the cash tip shows once and can be dismissed', (tester) async {
    await pumpScreen(tester, wrap(server(terminals), const Scaffold(body: HomeScreen())));
    await settle(tester);
    expect(find.textContaining('Cash only.', findRichText: true), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await settle(tester);
    expect(find.textContaining('Cash only.', findRichText: true), findsNothing);
  });

  testWidgets('home · the day is one field that opens the calendar', (tester) async {
    await pumpScreen(tester, wrap(server(terminals), const Scaffold(body: HomeScreen())));
    await settle(tester);
    expect(find.text('Tomorrow'), findsNothing);
    expect(find.text('Other day'), findsNothing);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Day: ')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
}
