import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_capture_app/main.dart';

void main() {
  testWidgets('renders the capture screen with a send button',
      (WidgetTester tester) async {
    await tester.pumpWidget(const AiCaptureApp());

    expect(find.text('Take photo & send to AI node'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
  });
}
