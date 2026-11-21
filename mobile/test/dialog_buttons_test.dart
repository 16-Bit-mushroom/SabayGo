import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_v2_uv_express/core/design/components/dialog_buttons.dart';

import 'support/harness.dart';

/// Every two-button dialog in the app ends on [DialogButtons] (20 Nov): the
/// action and the way out are the same width and height and lined up, the
/// way out under the action, at every width and text size, including a
/// label long enough to wrap onto two lines.
void main() {
  setUpAll(loadRealFonts);

  Widget opener(DialogButtons buttons) => Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('End shift?'),
                  content: const Text('You will need to sign in again to mark seats Paid or log passengers.'),
                  actions: [buttons],
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

  // A busy button spins for ever, so the dialog is pumped, never settled.
  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Open'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Finder inDialog(Type type) => find.descendant(of: find.byType(AlertDialog), matching: find.byType(type));

  final pairs = <String, DialogButtons Function()>{
    'End shift / Stay': () => DialogButtons(action: 'End shift', onAction: () {}, cancel: 'Stay'),
    'Cancel reservation / Keep it': () =>
        DialogButtons(action: 'Cancel reservation', onAction: () {}, cancel: 'Keep it', danger: true),
    'Delete account, busy': () =>
        const DialogButtons(action: 'Delete account', onAction: null, danger: true, busy: true),
  };

  for (final MapEntry(key: name, value: build) in pairs.entries) {
    for (final (size, scale) in [(kSmallPhone, 1.0), (kSmallPhone, 2.0), (kPhone, 1.0)]) {
      testWidgets('dialog buttons · $name · ${size.width.round()}dp · ${(scale * 100).round()}% text',
          (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpScreen(tester, opener(build()), size: size, textScale: scale);
        await open(tester);
        expect(tester.takeException(), isNull);
        final action = tester.getRect(inDialog(FilledButton));
        final way = tester.getRect(inDialog(OutlinedButton));
        expect(way.size, action.size, reason: 'the same width and height');
        expect(way.left, action.left, reason: 'lined up');
        expect(way.top, greaterThan(action.bottom), reason: 'the way out under the action');
        if (size == kPhone) {
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        }
        semantics.dispose();
      });
    }
  }

  testWidgets('dialog buttons · a screen reader hears each button once, by its own label', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(tester, opener(pairs['Cancel reservation / Keep it']!()));
    await open(tester);
    expect(tester.getSemantics(inDialog(FilledButton)).label, 'Cancel reservation');
    expect(tester.getSemantics(inDialog(OutlinedButton)).label, 'Keep it');
    semantics.dispose();
  });

  testWidgets('dialog buttons · busy: a spinner, the label still read, neither button takes a tap', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpScreen(tester, opener(pairs['Delete account, busy']!()));
    await open(tester);
    expect(inDialog(CircularProgressIndicator), findsOneWidget);
    expect(tester.getSemantics(inDialog(FilledButton)).label, 'Delete account');
    expect(tester.widget<FilledButton>(inDialog(FilledButton)).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(inDialog(OutlinedButton)).onPressed, isNull);
    semantics.dispose();
  });

  testWidgets('dialog buttons · the way out closes the dialog by default', (tester) async {
    await pumpScreen(tester, opener(pairs['End shift / Stay']!()));
    await open(tester);
    await tester.tap(inDialog(OutlinedButton));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
