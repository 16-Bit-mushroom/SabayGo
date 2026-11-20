import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Hand a byte buffer to the browser as a file download.
///
/// The console is Flutter Web only, so this reaches straight for the DOM:
/// a Blob, an object URL, and a click on an invisible anchor.
void downloadBytes(Uint8List bytes, {required String filename, required String mimeType}) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
