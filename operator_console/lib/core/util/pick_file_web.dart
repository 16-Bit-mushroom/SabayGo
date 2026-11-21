import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'picked_file.dart';

/// Ask the browser for one file. Null when the person cancels.
///
/// The counterpart of `downloadBytes`: the console is Flutter Web only, so
/// this is a hidden file input and its change (or cancel) event.
Future<PickedFile?> pickFile({String accept = '*/*'}) {
  final done = Completer<PickedFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept;
  input.addEventListener('change', (web.Event _) {
    final file = input.files?.item(0);
    if (file == null) {
      if (!done.isCompleted) done.complete(null);
      return;
    }
    file.arrayBuffer().toDart.then((buffer) {
      if (!done.isCompleted) done.complete(PickedFile(file.name, buffer.toDart.asUint8List()));
    });
  }.toJS);
  input.addEventListener('cancel', (web.Event _) {
    if (!done.isCompleted) done.complete(null);
  }.toJS);
  input.click();
  return done.future;
}
