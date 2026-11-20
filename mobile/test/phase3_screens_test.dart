import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_v2_uv_express/core/network/api_client.dart';
import 'package:mobile_v2_uv_express/core/storage/token_storage.dart';
import 'package:mobile_v2_uv_express/data/repositories/auth_repository.dart';
import 'package:mobile_v2_uv_express/viewmodels/auth_provider.dart';
import 'package:mobile_v2_uv_express/views/auth/login_screen.dart';
import 'package:mobile_v2_uv_express/views/auth/signup_screen.dart';
import 'package:mobile_v2_uv_express/views/messages/conversation_thread_screen.dart';
import 'package:mobile_v2_uv_express/views/messages/conversations_screen.dart';
import 'package:mobile_v2_uv_express/views/messages/new_conversation_screen.dart';
import 'package:mobile_v2_uv_express/views/notifications/notifications_screen.dart';
import 'package:mobile_v2_uv_express/views/profile/profile_screen.dart';
import 'package:mobile_v2_uv_express/views/safety/sos_button.dart';
import 'package:mobile_v2_uv_express/views/special_trips/special_trips_screen.dart';
import 'package:provider/provider.dart';

import 'support/harness.dart';

class _Token extends TokenStorage {
  @override
  Future<String?> readAccessToken() async => 'test';

  @override
  Future<void> clear() async {}
}

/// The rest of the passenger app after the 20 Nov redesign (phase 3),
/// whole, against a fake server: each screen lays out at 320 dp and 200 %
/// text, and meets the tap-target and label guidelines at 390 dp. The two
/// map screens (home pickup, live map) load OpenStreetMap tiles over the
/// network and are left to `flutter analyze`.
void main() {
  setUpAll(loadRealFonts);
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  final now = DateTime.now();

  final answers = <String, Object>{
    '/auth/me': {
      'user_id': 'U1',
      'email': 'maria.dela.cruz@example.com',
      'first_name': 'Maria Consolacion',
      'last_name': 'Dela Cruz-Villanueva',
      'phone_number': '09007234567',
      'home_address': 'Matina, Davao City',
      'gender': 'female',
      'emergency_contact_name': 'Jose Dela Cruz',
      'emergency_contact_relation': 'Brother',
      'emergency_contact_number': '09008234567',
      'role': 'passenger',
    },
    '/users/me/settings': {'push_enabled': true, 'trip_updates': true, 'tailored_schedules': false},
    '/users/me/saved-destinations': [
      {'destination_id': 'D1', 'label': "Mom's house", 'address': 'Digos City', 'terminal_id': null},
    ],
    '/notifications': {
      'unread_count': 1,
      'items': [
        {
          'notification_id': 'N1',
          'type': 'departure_reminder',
          'title': 'Pay ₱363 at Ecoland by 10:00 AM',
          'message': 'Your seat SG-7K2Q9M is still unpaid. Hand the cash to the Dispatcher before 10:00 AM.',
          'created_at': now.subtract(const Duration(minutes: 5)).toIso8601String(),
          'is_read': false,
          'related_entity_type': 'trip',
          'related_entity_id': 'T1',
        },
        {
          'notification_id': 'N2',
          'type': 'tailored_schedule',
          'title': 'Morning vans to Digos',
          'message': 'New departures to your saved destination "Mom\'s house" are open for booking.',
          'created_at': now.subtract(const Duration(days: 2)).toIso8601String(),
          'is_read': true,
          'related_entity_type': null,
          'related_entity_id': null,
        },
      ],
    },
    '/conversations': [
      {
        'conversation_id': 'C1',
        'kind': 'passenger_dispatcher',
        'trip_id': 'T1',
        'peer_user_id': 'D1',
        'peer_role': 'dispatcher',
        'peer_name': 'Nonoy Abellana',
        'last_message': 'Look for the van at bay 3.',
        'last_message_at': now.subtract(const Duration(minutes: 3)).toIso8601String(),
        'unread_count': 2,
        'created_at': now.subtract(const Duration(hours: 1)).toIso8601String(),
      },
      {
        'conversation_id': 'C2',
        'kind': 'office',
        'trip_id': null,
        'peer_user_id': null,
        'peer_role': 'terminal_manager',
        'peer_name': 'A2Z office',
        'last_message': 'Your van rental request is approved.',
        'last_message_at': now.subtract(const Duration(days: 1)).toIso8601String(),
        'unread_count': 0,
        'created_at': now.subtract(const Duration(days: 2)).toIso8601String(),
      },
    ],
    '/conversations/contacts': [
      {'peer_user_id': 'D1', 'peer_role': 'dispatcher', 'peer_name': 'Nonoy Abellana', 'trip_id': 'T1',
        'trip_label': 'Davao (Ecoland) – Cotabato City, today 10:30 AM'},
      {'peer_user_id': null, 'peer_role': 'terminal_manager', 'peer_name': 'A2Z office', 'trip_id': null,
        'trip_label': null},
    ],
    '/conversations/C1/messages': [
      {
        'message_id': 'M1', 'conversation_id': 'C1', 'sender_id': 'D1', 'sender_role': 'dispatcher',
        'body': 'Good morning. Look for van TST-1023 at bay 3.', 'is_mine': false, 'can_change': false,
        'created_at': now.subtract(const Duration(minutes: 9)).toIso8601String(), 'read_at': null,
        'edited_at': null, 'deleted_at': null,
      },
      {
        'message_id': 'M2', 'conversation_id': 'C1', 'sender_id': 'U1', 'sender_role': 'passenger',
        'body': 'Thank you. We are walking to bay 3 now with the cash ready.', 'is_mine': true,
        'can_change': true, 'created_at': now.subtract(const Duration(minutes: 7)).toIso8601String(),
        'read_at': null, 'edited_at': now.subtract(const Duration(minutes: 6)).toIso8601String(), 'deleted_at': null,
      },
      {
        'message_id': 'M3', 'conversation_id': 'C1', 'sender_id': 'U1', 'sender_role': 'passenger',
        'body': '', 'is_mine': true, 'can_change': false,
        'created_at': now.subtract(const Duration(minutes: 5)).toIso8601String(), 'read_at': null,
        'edited_at': null, 'deleted_at': now.subtract(const Duration(minutes: 4)).toIso8601String(),
      },
    ],
    '/special-trips/mine': [
      {
        'request_id': 'R1', 'status': 'approved', 'payment_status': 'unpaid',
        'pickup_at': now.add(const Duration(days: 3)).toIso8601String(),
        'pickup_address': 'Matina Town Square, Davao City', 'destination_address': 'Lake Sebu, South Cotabato',
        'passenger_count': 14, 'rental_fee': '3500.00', 'fee_note': 'Agreed fee',
      },
      {
        'request_id': 'R2', 'status': 'requested', 'payment_status': 'unpaid',
        'pickup_at': now.add(const Duration(days: 8)).toIso8601String(),
        'pickup_address': 'Ecoland Terminal', 'destination_address': 'Tagum City Hall',
        'passenger_count': 1, 'rental_fee': null, 'fee_note': null,
      },
    ],
  };

  ApiClient server() => ApiClient(
        tokenStorage: _Token(),
        baseUrl: 'http://x/api/v1',
        httpClient: MockClient((req) async {
          final body = answers[req.url.path.replaceFirst('/api/v1', '')];
          return body == null
              ? http.Response(jsonEncode({'detail': 'Not found.'}), 404)
              : http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );

  Widget wrap(Widget child) {
    final api = server();
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(repository: AuthRepository(api), tokens: _Token()),
        ),
      ],
      child: child,
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void screenCase(String name, Widget Function() build, {Future<void> Function(WidgetTester)? then}) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('$name · 320dp · ${(scale * 100).round()}% text', (tester) async {
        await pumpScreen(tester, wrap(build()), size: kSmallPhone, textScale: scale);
        await settle(tester);
        if (then != null) await then(tester);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('$name · 390dp · 100% text', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpScreen(tester, wrap(build()));
      await settle(tester);
      if (then != null) await then(tester);
      expect(tester.takeException(), isNull);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });
  }

  screenCase('sign in', () => const LoginScreen());
  screenCase('create account', () => const SignupScreen());
  screenCase('profile', () => const Scaffold(body: ProfileScreen()));
  screenCase('edit profile', () => const Scaffold(body: ProfileScreen()), then: (tester) async {
    await tester.ensureVisible(find.text('Edit profile'));
    await tester.tap(find.text('Edit profile'));
    await settle(tester);
    expect(find.text('Personal details'), findsOneWidget);
  });
  screenCase('updates', () => const Scaffold(body: NotificationsScreen()));
  screenCase('chat · conversations', () => const ConversationsScreen());
  screenCase('chat · new message', () => const NewConversationScreen());
  screenCase(
    'chat · thread',
    () => const ConversationThreadScreen(conversationId: 'C1', peerName: 'Nonoy Abellana', peerRole: 'dispatcher'),
  );
  screenCase('rent a van', () => const SpecialTripsScreen());
  screenCase(
    'SOS sheet',
    () => const Scaffold(body: Center(child: SosButton(tripId: 'T1'))),
    then: (tester) async {
      await tester.tap(find.byType(OutlinedButton));
      await settle(tester);
      expect(find.text('Emergency SOS'), findsOneWidget);
    },
  );

  testWidgets('profile · the notification switches are on the page, not in a sheet', (tester) async {
    await pumpScreen(tester, wrap(const Scaffold(body: ProfileScreen())));
    await settle(tester);
    expect(find.text('Changes to my trips'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(3));
  });

  testWidgets('updates · "Book a seat" goes Home without throwing', (tester) async {
    await pumpScreen(tester, wrap(const Scaffold(body: NotificationsScreen())));
    await settle(tester);
    await tester.tap(find.text('Book a seat'));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile · rented vans are on the page, with their state', (tester) async {
    await pumpScreen(tester, wrap(const Scaffold(body: ProfileScreen())));
    await settle(tester);
    expect(find.text('Rented vans'), findsOneWidget);
    expect(find.text('APPROVED: PAY IN CASH'), findsOneWidget);
    expect(find.text('WAITING FOR A2Z'), findsOneWidget);
  });

  testWidgets('sign out · the two buttons are the same size and lined up', (tester) async {
    await pumpScreen(tester, wrap(const Scaffold(body: ProfileScreen())), size: kSmallPhone);
    await settle(tester);
    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await settle(tester);
    Rect rect(Type type) =>
        tester.getRect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(type)));
    final action = rect(FilledButton);
    final way = rect(OutlinedButton);
    expect(way.size, action.size);
    expect(way.left, action.left);
    expect(way.top, greaterThan(action.bottom));
  });

  testWidgets('rent a van · with no requests, one way to request a van, not two', (tester) async {
    final saved = answers['/special-trips/mine']!;
    answers['/special-trips/mine'] = <Object>[];
    addTearDown(() => answers['/special-trips/mine'] = saved);
    await pumpScreen(tester, wrap(const SpecialTripsScreen()));
    await settle(tester);
    expect(find.text('Request a van'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
