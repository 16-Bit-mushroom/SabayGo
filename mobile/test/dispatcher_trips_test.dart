import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_v2_uv_express/core/network/api_client.dart';
import 'package:mobile_v2_uv_express/core/storage/token_storage.dart';
import 'package:mobile_v2_uv_express/data/repositories/auth_repository.dart';
import 'package:mobile_v2_uv_express/data/repositories/operations_repository.dart';
import 'package:mobile_v2_uv_express/viewmodels/auth_provider.dart';
import 'package:mobile_v2_uv_express/viewmodels/shift_viewmodel.dart';
import 'package:mobile_v2_uv_express/views/dispatcher/dispatcher_main_screen.dart';
import 'package:mobile_v2_uv_express/views/dispatcher/dispatcher_trips_screen.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

class _Token extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => 'test';

  @override
  Future<void> clear() async {}
}

/// The Dispatcher's trip list (20 Nov): every card is the same size. The
/// next trip stands out by its green outline and countdown, no longer by
/// an Open button of its own, and a trip with no van yet keeps the van row.
void main() {
  setUpAll(loadRealFonts);

  final day = DateTime.now().add(const Duration(days: 1));
  DateTime at(int h, int m) => DateTime(day.year, day.month, day.day, h, m);
  final stops = [
    for (final (i, name) in ['Cooperative Van Terminal – Ecoland', 'Digos City Terminal', 'Kidapawan City Terminal',
      'Cotabato City Integrated Transport Terminal'].indexed)
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

  Map<String, dynamic> trip(String id, DateTime when, {String? plate}) => {
        'trip_id': id,
        'trip_label': 'Davao (Ecoland) – Cotabato City',
        'route_name': 'Davao (Ecoland) – Cotabato City',
        'service_date': when.toIso8601String().substring(0, 10),
        'departure_datetime': when.toIso8601String(),
        'status': 'scheduled',
        'plate_number': plate,
        'seat_capacity': 14,
        'stops': stops,
        'operator_name': plate == null ? null : 'Arnel Bautista',
        'operator_licence': plate == null ? null : 'D01-23-456789',
        'payment_status': 'unpaid',
        'crew_aboard': false,
        'rental': null,
      };

  final trips = [
    trip('T1', at(5, 30), plate: 'LCT-9042'), // next: outlined, with a countdown
    trip('T2', at(7, 30)), // no van yet
    trip('T3', at(9, 30), plate: 'TST-1023'),
  ];

  Widget screen() {
    final api = ApiClient(
      tokenStorage: _Token(),
      baseUrl: 'http://x/api/v1',
      httpClient: MockClient((req) async => req.url.path.endsWith('/trips/assigned')
          ? http.Response(jsonEncode(trips), 200, headers: {'content-type': 'application/json; charset=utf-8'})
          : http.Response(jsonEncode({'detail': 'Not found.'}), 404)),
    );
    return ChangeNotifierProvider<ShiftViewModel>(
      create: (_) => ShiftViewModel(OperationsRepository(api)),
      child: const Scaffold(body: DispatcherTripsScreen()),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // Tall enough that every card is built: the width and the text size set a
  // card's size, the screen's height does not.
  for (final (width, scale) in [(320.0, 1.0), (320.0, 2.0), (390.0, 1.0)]) {
    testWidgets('dispatcher trips · every card the same size · ${width.round()}dp · ${(scale * 100).round()}% text',
        (tester) async {
      await pumpScreen(tester, screen(), size: Size(width, 2400), textScale: scale);
      await settle(tester);
      expect(tester.takeException(), isNull);
      Size card(String time) =>
          tester.getSize(find.ancestor(of: find.text(time), matching: find.byType(InkWell)).first);
      final next = card('5:30 AM');
      expect(card('7:30 AM'), next, reason: 'a card with no van yet');
      expect(card('9:30 AM'), next, reason: 'a later card with a van');
    });
  }

  testWidgets('dispatcher trips · no Open button on the next card; the van row says when there is no van',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(tester, screen(), size: const Size(390, 2400));
    await settle(tester);
    expect(find.text('Open passenger list'), findsNothing);
    expect(find.text('No van yet'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(3));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  // 20 Nov: beside the van mark and three labelled buttons the name and
  // the role were cut to "Nonoy…" and "DISP…". 363 dp is the owner's
  // preview; 390 dp a common phone.
  for (final width in [363.0, 390.0]) {
    testWidgets('dispatcher home · the name and the role are whole at the top · ${width.round()}dp', (tester) async {
      final api = ApiClient(
        tokenStorage: _Token(),
        baseUrl: 'http://x/api/v1',
        httpClient: MockClient((req) async {
          final body = switch (req.url.path.replaceFirst('/api/v1', '')) {
            '/auth/me' => <String, Object?>{
                'user_id': 'U-NONOY',
                'email': 'nonoy@a2z.dev',
                'role': 'dispatcher',
                'account_status': 'active',
                'display_name': 'Nonoy Abellana',
                'first_name': 'Nonoy',
                'last_name': 'Abellana',
              },
            '/trips/assigned' => trips,
            '/notifications' => <String, Object?>{'unread_count': 4, 'items': <Object>[]},
            '/conversations' => <Object>[],
            _ => null,
          };
          return body == null
              ? http.Response(jsonEncode({'detail': 'Not found.'}), 404)
              : http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );
      final auth = AuthProvider(repository: AuthRepository(api), tokens: _Token());
      await auth.restore();
      await pumpScreen(
        tester,
        MultiProvider(
          providers: [
            Provider<ApiClient>.value(value: api),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: const DispatcherMainScreen(),
        ),
        size: Size(width, 760),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      for (final text in ['Nonoy Abellana', 'DISPATCHER']) {
        expect(tester.renderObject<RenderParagraph>(find.text(text)).didExceedMaxLines, isFalse,
            reason: '$text is whole');
      }
    });
  }
}
