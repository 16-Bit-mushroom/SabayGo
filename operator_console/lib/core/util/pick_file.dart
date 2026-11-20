/// Ask the browser for one file (`pickFile`), and what it hands back
/// (`PickedFile`).
///
/// The console runs on the web only; the browser code lives in
/// `pick_file_web.dart`. The stub lets the console's tests compile on the
/// Dart VM, where `dart:js_interop` and `package:web` do not exist (20 Nov).
library;

export 'pick_file_stub.dart' if (dart.library.js_interop) 'pick_file_web.dart';
export 'picked_file.dart';
