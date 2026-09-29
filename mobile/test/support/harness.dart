import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_v2_uv_express/core/design/theme.dart';

/// Phone sizes worth caring about.
///
/// 320×640 is the small Android still in use across the cooperative's
/// passengers; it is also where every layout mistake shows up first.
const kSmallPhone = Size(320, 640);
const kPhone = Size(390, 844);
const kWide = Size(760, 1024);

/// Registers the app's own bundled Roboto.
///
/// Without it `flutter test` measures every string in Ahem — a fixed-pitch
/// block font whose metrics match nothing — so a layout that overflows on a
/// handset can pass here, and one that fits can fail. These are the same
/// files `pubspec.yaml` ships, so the widths measured are the widths the
/// passenger gets.
Future<void> loadRealFonts() async {
  final dir = Directory('assets/fonts');
  if (!dir.existsSync()) return;

  final loader = FontLoader('Roboto');
  for (final name in const [
    'Roboto-Regular.ttf',
    'Roboto-Medium.ttf',
    'Roboto-Bold.ttf',
  ]) {
    final file = File('${dir.path}/$name');
    if (file.existsSync()) {
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
  }
  await loader.load();
  await _loadMaterialIcons();
}

/// The icon font, from the SDK cache.
///
/// Icons occupy their declared `size` whatever glyph resolves, so this does
/// not change any layout — it is here so a rendered screen can be looked at
/// and judged rather than read as a grid of tofu boxes.
Future<void> _loadMaterialIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!file.existsSync()) return;

  await (FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync()))))
      .load();
}

/// Renders [child] in the real app theme at a given size and text scale.
///
/// Any overflow during layout is reported as an exception, which fails the
/// test — that is the whole point of this harness. WCAG 1.4.4 asks for 200%
/// text without loss of content, and the only way to know is to lay it out
/// at 200% and look.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget child, {
  Size size = kPhone,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      // The real theme, unmodified: it names the font family itself now, so
      // a test that patched the family in would be testing a different app.
      theme: buildAppTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}
