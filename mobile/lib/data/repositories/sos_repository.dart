import '../../core/network/api_client.dart';

/// What the server actually did with one emergency contact number.
class SosDispatch {
  const SosDispatch({required this.recipient, required this.status, this.error});

  final String recipient;
  final String status; // sent | failed | skipped
  final String? error;

  factory SosDispatch.fromJson(Map<String, dynamic> j) => SosDispatch(
        recipient: j['recipient'] as String,
        status: j['status'] as String,
        error: j['error'] as String?,
      );
}

/// The reply to pressing SOS. `message` is written by the server and is
/// deliberately honest about delivery -- the screen shows it verbatim
/// rather than composing its own reassurance.
class SosResult {
  const SosResult({
    required this.sosId,
    required this.duplicate,
    required this.notifiedInApp,
    required this.smsAttempted,
    required this.smsSent,
    required this.message,
    required this.dispatches,
  });

  final String sosId;
  final bool duplicate;
  final int notifiedInApp;
  final int smsAttempted;
  final int smsSent;
  final String message;
  final List<SosDispatch> dispatches;

  factory SosResult.fromJson(Map<String, dynamic> j) {
    final sms = j['sms'] as Map<String, dynamic>;
    return SosResult(
      sosId: j['sos_id'] as String,
      duplicate: j['duplicate'] as bool,
      notifiedInApp: j['notified_in_app'] as int,
      smsAttempted: sms['attempted'] as int,
      smsSent: sms['sent'] as int,
      message: j['message'] as String,
      dispatches: (sms['recipients'] as List)
          .map((e) => SosDispatch.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Raising an emergency. Open to every signed-in role -- see the backend's
/// app/application/safety/sos.py for why the trip id is authorised
/// separately from the alert itself.
class SosRepository {
  SosRepository(this._api);
  final ApiClient _api;

  Future<SosResult> raise({
    required String category,
    String? tripId,
    String? note,
    double? latitude,
    double? longitude,
    double? accuracyM,
  }) async {
    final json = await _api.post('/sos', body: {
      'category': category,
      if (tripId != null) 'trip_id': tripId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (accuracyM != null) 'accuracy_m': accuracyM,
    });
    return SosResult.fromJson(json as Map<String, dynamic>);
  }
}
