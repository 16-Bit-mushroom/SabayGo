import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';

class PendingAudit {
  const PendingAudit({
    required this.auditId,
    required this.tripId,
    this.tripLabel,
    required this.serviceDate,
    required this.legSequence,
    required this.visualCount,
    required this.bookedCount,
    required this.variance,
    this.snapshotUrl,
    this.confidenceAvg,
    required this.capturedAt,
  });

  final String auditId;
  final String tripId;
  final String? tripLabel;
  final DateTime serviceDate;
  final int legSequence;
  final int visualCount;
  final int bookedCount;
  final int variance;
  final String? snapshotUrl;
  final double? confidenceAvg;
  final DateTime capturedAt;

  /// The snapshot path the backend returns is server-relative
  /// (`/media/audits/...`), served off the API host but outside the
  /// `/api/v1` prefix -- so it is resolved against the host, not the
  /// configured API base path.
  String? get snapshotAbsoluteUrl {
    if (snapshotUrl == null) return null;
    final apiUri = Uri.parse(AppConfig.apiBaseUrl);
    final hostUri = Uri(scheme: apiUri.scheme, host: apiUri.host, port: apiUri.port);
    return hostUri.resolve(snapshotUrl!).toString();
  }

  factory PendingAudit.fromJson(Map<String, dynamic> json) => PendingAudit(
        auditId: json['audit_id'] as String,
        tripId: json['trip_id'] as String,
        tripLabel: json['trip_label'] as String?,
        serviceDate: DateTime.parse(json['service_date'] as String),
        legSequence: json['leg_sequence'] as int,
        visualCount: json['visual_count'] as int,
        bookedCount: json['booked_count'] as int,
        variance: json['variance'] as int,
        snapshotUrl: json['snapshot_url'] as String?,
        confidenceAvg: (json['confidence_avg'] as num?)?.toDouble(),
        capturedAt: DateTime.parse(json['captured_at'] as String),
      );
}

class AuditRepository {
  AuditRepository(this._api);
  final ApiClient _api;

  Future<List<PendingAudit>> pending() async {
    final json = await _api.get('/audits/pending');
    return (json as List)
        .map((e) => PendingAudit.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `resolution` is "resolved" (action taken -- e.g. driver flagged) or
  /// "ignored" (reviewed, no action -- e.g. a standee, not a stowaway).
  Future<void> resolve({
    required String auditId,
    required String resolution,
    required String notes,
  }) async {
    await _api.post('/audits/$auditId/resolve', body: {
      'resolution': resolution,
      'notes': notes,
    });
  }
}
