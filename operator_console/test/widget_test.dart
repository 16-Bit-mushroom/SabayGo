import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:operator_console/main.dart';

void main() {
  testWidgets('Console boots without crashing', (WidgetTester tester) async {
    // Session restore reads flutter_secure_storage, which has no platform
    // channel handler under `flutter test` -- so this only checks the
    // splash frame renders, not the sign-in screen it leads to.
    await tester.pumpWidget(const SabayGoOperatorConsole());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
