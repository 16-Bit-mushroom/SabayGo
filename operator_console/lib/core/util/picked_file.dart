import 'dart:typed_data';

/// A file the person picked in the browser.
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}
