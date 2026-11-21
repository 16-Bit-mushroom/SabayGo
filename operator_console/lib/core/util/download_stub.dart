import 'dart:typed_data';

/// Off the web there is no browser to hand a file to (the console's tests
/// run on the Dart VM): saying so beats pretending a file was saved.
void downloadBytes(Uint8List bytes, {required String filename, required String mimeType}) =>
    throw UnsupportedError('Saving $filename needs the browser: the console runs on the web.');
