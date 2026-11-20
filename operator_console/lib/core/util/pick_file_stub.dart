import 'picked_file.dart';

/// Off the web there is no browser to pick a file in (the console's tests
/// run on the Dart VM): saying so beats returning nothing, which would read
/// as the person cancelling.
Future<PickedFile?> pickFile({String accept = '*/*'}) =>
    throw UnsupportedError('Picking a file needs the browser: the console runs on the web.');
