import 'package:geolocator/geolocator.dart';

/// One definition of "where is this phone".
///
/// Lived inside TicketViewModel until the SOS button needed the same
/// answer. The two callers want opposite failure behaviour, which is why
/// there are two entry points rather than one with a flag:
///
///   [resolvePosition]  throws. Check-in is a location claim, and a
///                      claim that cannot be substantiated must fail.
///   [tryPosition]      returns null. An emergency is not a location
///                      claim; a denied permission must never be the
///                      reason nobody was told.
class CurrentPosition {
  const CurrentPosition._();

  static Future<Position> resolve({
    Duration timeLimit = const Duration(seconds: 15),
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw const LocationServiceDisabledException();

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw PermissionDeniedException('Location permission denied');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw PermissionDeniedException('Location permission permanently denied');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeLimit,
      ),
    );
  }

  /// Best effort, for callers where a missing fix is a detail rather than
  /// a failure. Never throws, and never waits long enough to matter.
  static Future<Position?> tryResolve({
    Duration timeLimit = const Duration(seconds: 8),
  }) async {
    try {
      return await resolve(timeLimit: timeLimit);
    } catch (_) {
      return null;
    }
  }
}
