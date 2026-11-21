/// Hand a byte buffer to the browser as a file download.
///
/// The console runs on the web only; the browser code lives in
/// `download_web.dart`. The stub lets the console's tests compile on the
/// Dart VM, where `dart:js_interop` and `package:web` do not exist, which
/// had kept `flutter test` from loading at all (20 Nov).
library;

export 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart';
