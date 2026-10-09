import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';

class PendingAudit {
  const PendingAudit({
    required this.auditId,
    required this.tripId,
    this.tripLabel,
    required this.serviceDate,
    required this.legSequence,
    required this.triggerType,
    required this.visualCount,
    required this.bookedCount,
    required this.variance,
    this.snapshotUrl,
    this.confidenceAvg,
    required this.capturedAt,
    this.resolutionStatus = 'pending',
    this.resolvedBy,
    this.resolvedAt,
    this.resolutionNotes,
    required this.verdict,
    required this.headline,
    required this.explanation,
    required this.nextStep,
    this.caution,
  });

  final String auditId;
  final String tripId;
  final String? tripLabel;
  final DateTime serviceDate;
  final int legSequence;

  /// How the capture began: `manual` (someone asked), `door_close` (the
  /// crew closed boarding and departed) or `gps_node` (the van left a
  /// terminal's geofence). The last two are the systematic check -- worth
  /// showing, because an audit the crew cannot decline is a different
  /// piece of evidence from one they chose to run.
  final String triggerType;
  final int visualCount;
  final int bookedCount;
  final int variance;
  final String? snapshotUrl;
  final double? confidenceAvg;
  final DateTime capturedAt;

  /// G.2: history rows carry how the audit was closed and by whom.
  /// `pending` rows leave these null.
  final String resolutionStatus;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final String? resolutionNotes;

  /// What the counts mean, written by the backend (domain/audit_reading.py)
  /// so every screen says the same thing about the same result.
  /// `verdict` is match / more_than_manifest / fewer_than_manifest.
  final String verdict;
  final String headline;
  final String explanation;
  final String nextStep;
  final String? caution;

  bool get isPending => resolutionStatus == 'pending';

  bool get isAutomatic => triggerType != 'manual';

  /// The office's words, not the enum's.
  String get triggerLabel => switch (triggerType) {
        // door_close fires when the conductor closes boarding and departs;
        // there is no door sensor, so the label says what really happened.
        'door_close' => 'Automatic — van departed',
        'gps_node' => 'Automatic — van left a stop',
        'scheduled' => 'Automatic — scheduled',
        'manual' => 'Requested by the office',
        _ => triggerType,
      };

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
        triggerType: json['trigger_type'] as String? ?? 'manual',
        visualCount: json['visual_count'] as int,
        bookedCount: json['booked_count'] as int,
        variance: json['variance'] as int,
        snapshotUrl: json['snapshot_url'] as String?,
        confidenceAvg: (json['confidence_avg'] as num?)?.toDouble(),
        capturedAt: DateTime.parse(json['captured_at'] as String),
        resolutionStatus: json['resolution_status'] as String? ?? 'pending',
        resolvedBy: json['resolved_by'] as String?,
        resolvedAt: json['resolved_at'] == null
            ? null
            : DateTime.parse(json['resolved_at'] as String),
        resolutionNotes: json['resolution_notes'] as String?,
        verdict: json['verdict'] as String,
        headline: json['headline'] as String,
        explanation: json['explanation'] as String,
        nextStep: json['next_step'] as String,
        caution: json['caution'] as String?,
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

  /// Every audit of one trip, open or closed, newest first -- for the
  /// Trips screen.
  Future<List<PendingAudit>> forTrip(String tripId) async {
    final json = await _api.get('/audits/trips/$tripId');
    return (json as List)
        .map((e) => PendingAudit.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Audits that have left the queue, newest first (G.2). Pass `status`
  /// to narrow to one of reconciled / resolved / ignored / failed.
  Future<List<PendingAudit>> history({String? status}) async {
    final json = await _api.get(
      '/audits/history',
      query: {if (status != null) 'status': status},
    );
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

  /// Asks the phone-as-camera PoC (ai_capture_app) to capture next time it
  /// polls -- the same role the Orange Pi will fill once that hardware is
  /// in hand. Returns immediately with the request's `requested_at`, which
  /// identifies it in [phoneStatus]. The backend refuses here, not later,
  /// when the trip is not boarding or departed.
  Future<String> triggerPhone({
    required String tripId,
    required int legSequence,
  }) async {
    final json = await _api.post('/audits/trigger-phone', body: {
      'trip_id': tripId,
      'leg_sequence': legSequence,
    }) as Map<String, dynamic>;
    return json['requested_at'] as String;
  }

  /// What became of the latest phone request: `state` is idle, pending,
  /// fulfilled (with `result`) or failed (with `error`). Needed because a
  /// capture that matches the manifest is filed as reconciled -- history,
  /// not the queue -- and a failed one writes no audit at all.
  Future<Map<String, dynamic>> phoneStatus() async {
    return await _api.get('/audits/phone/status') as Map<String, dynamic>;
  }
}
