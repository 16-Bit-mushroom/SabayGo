import '../../core/network/api_client.dart';

/// One SMS the backend tried to send for an alert, with what actually
/// happened to it. A 'skipped' row means no attempt was made and says
/// why -- the console never renders an untried message as delivered.
class SosDispatch {
  const SosDispatch({
    required this.recipient,
    required this.provider,
    required this.status,
    this.error,
  });

  final String recipient;
  final String provider;
  final String status; // sent | failed | skipped
  final String? error;

  factory SosDispatch.fromJson(Map<String, dynamic> j) => SosDispatch(
        recipient: j['recipient'] as String,
        provider: j['provider'] as String,
        status: j['status'] as String,
        error: j['error'] as String?,
      );
}

class SosAlert {
  const SosAlert({
    required this.sosId,
    required this.status,
    required this.category,
    this.note,
    required this.raisedBy,
    required this.raisedByRole,
    this.raisedByPhone,
    required this.raisedAt,
    this.tripId,
    this.tripLabel,
    this.latitude,
    this.longitude,
    this.accuracyM,
    this.mapUrl,
    this.acknowledgedBy,
    this.acknowledgedAt,
    this.resolvedAt,
    this.resolutionNotes,
    required this.smsAttempted,
    required this.smsSent,
    required this.smsFailed,
    required this.smsSkipped,
    required this.dispatches,
  });

  final String sosId;
  final String status; // open | acknowledged | resolved
  final String category;
  final String? note;
  final String raisedBy;
  final String raisedByRole;
  final String? raisedByPhone;
  final DateTime raisedAt;
  final String? tripId;
  final String? tripLabel;
  final double? latitude;
  final double? longitude;
  final double? accuracyM;
  final String? mapUrl;
  final String? acknowledgedBy;
  final DateTime? acknowledgedAt;
  final DateTime? resolvedAt;
  final String? resolutionNotes;
  final int smsAttempted;
  final int smsSent;
  final int smsFailed;
  final int smsSkipped;
  final List<SosDispatch> dispatches;

  bool get isOpen => status == 'open';
  bool get isResolved => status == 'resolved';
  bool get hasLocation => latitude != null && longitude != null;

  factory SosAlert.fromJson(Map<String, dynamic> j) {
    final sms = j['sms'] as Map<String, dynamic>;
    return SosAlert(
      sosId: j['sos_id'] as String,
      status: j['status'] as String,
      category: j['category'] as String,
      note: j['note'] as String?,
      raisedBy: j['raised_by'] as String,
      raisedByRole: j['raised_by_role'] as String,
      raisedByPhone: j['raised_by_phone'] as String?,
      raisedAt: DateTime.parse(j['raised_at'] as String),
      tripId: j['trip_id'] as String?,
      tripLabel: j['trip_label'] as String?,
      latitude: (j['latitude'] as num?)?.toDouble(),
      longitude: (j['longitude'] as num?)?.toDouble(),
      accuracyM: (j['accuracy_m'] as num?)?.toDouble(),
      mapUrl: j['map_url'] as String?,
      acknowledgedBy: j['acknowledged_by'] as String?,
      acknowledgedAt: j['acknowledged_at'] == null
          ? null
          : DateTime.parse(j['acknowledged_at'] as String),
      resolvedAt: j['resolved_at'] == null
          ? null
          : DateTime.parse(j['resolved_at'] as String),
      resolutionNotes: j['resolution_notes'] as String?,
      smsAttempted: sms['attempted'] as int,
      smsSent: sms['sent'] as int,
      smsFailed: sms['failed'] as int,
      smsSkipped: sms['skipped'] as int,
      dispatches: (sms['recipients'] as List)
          .map((e) => SosDispatch.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SosRepository {
  SosRepository(this._api);
  final ApiClient _api;

  Future<List<SosAlert>> list({String? status, int limit = 50}) async {
    final json = await _api.get('/sos', query: {
      if (status != null) 'status': status,
      'limit': limit.toString(),
    }) as List<dynamic>;
    return json
        .map((e) => SosAlert.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> acknowledge(String sosId) => _api.post('/sos/$sosId/acknowledge');

  Future<void> resolve(String sosId, String notes) =>
      _api.post('/sos/$sosId/resolve', body: {'notes': notes});
}
