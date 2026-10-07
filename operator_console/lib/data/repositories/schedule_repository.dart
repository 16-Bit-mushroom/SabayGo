import '../../core/network/api_client.dart';

class ScheduleTemplate {
  const ScheduleTemplate({
    required this.templateId,
    required this.routeId,
    required this.departureTime,
    required this.daysOfWeek,
    this.tripLabel,
    this.defaultVanId,
    this.defaultDriverId,
    this.defaultConductorId,
    required this.isActive,
    required this.validFrom,
    this.validUntil,
  });

  final String templateId;
  final String routeId;
  final String departureTime; // "HH:MM:SS"
  final String daysOfWeek; // Monday-first 7-char mask, e.g. "1111100"
  final String? tripLabel;
  final String? defaultVanId;
  final String? defaultDriverId;
  final String? defaultConductorId;
  final bool isActive;
  final DateTime validFrom;
  final DateTime? validUntil;

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String get daysSummary {
    if (daysOfWeek == '1111111') return 'Every day';
    if (daysOfWeek == '1111100') return 'Weekdays';
    if (daysOfWeek == '0000011') return 'Weekends';
    final active = <String>[];
    for (var i = 0; i < daysOfWeek.length && i < _dayLabels.length; i++) {
      if (daysOfWeek[i] == '1') active.add(_dayLabels[i]);
    }
    return active.isEmpty ? 'Never' : active.join(', ');
  }

  factory ScheduleTemplate.fromJson(Map<String, dynamic> json) => ScheduleTemplate(
        templateId: json['template_id'] as String,
        routeId: json['route_id'] as String,
        departureTime: json['departure_time'] as String,
        daysOfWeek: json['days_of_week'] as String,
        tripLabel: json['trip_label'] as String?,
        defaultVanId: json['default_van_id'] as String?,
        defaultDriverId: json['default_driver_id'] as String?,
        defaultConductorId: json['default_conductor_id'] as String?,
        isActive: json['is_active'] as bool,
        validFrom: DateTime.parse(json['valid_from'] as String),
        validUntil: json['valid_until'] != null
            ? DateTime.parse(json['valid_until'] as String)
            : null,
      );
}

class GenerationReport {
  const GenerationReport({
    required this.serviceDate,
    required this.templatesConsidered,
    required this.tripsCreated,
    required this.tripsSkipped,
    required this.seatLegsCreated,
    required this.warnings,
  });

  final DateTime serviceDate;
  final int templatesConsidered;
  final int tripsCreated;
  final int tripsSkipped;
  final int seatLegsCreated;
  final List<String> warnings;

  factory GenerationReport.fromJson(Map<String, dynamic> json) => GenerationReport(
        serviceDate: DateTime.parse(json['service_date'] as String),
        templatesConsidered: json['templates_considered'] as int,
        tripsCreated: json['trips_created'] as int,
        tripsSkipped: json['trips_skipped'] as int,
        seatLegsCreated: json['seat_legs_created'] as int,
        warnings: (json['warnings'] as List).cast<String>(),
      );
}

class ScheduleRepository {
  ScheduleRepository(this._api);
  final ApiClient _api;

  Future<List<ScheduleTemplate>> listTemplates() async {
    final json = await _api.get('/config/schedule-templates');
    return (json as List)
        .map((e) => ScheduleTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createTemplate({
    required String routeId,
    required String departureTime, // "HH:MM" or "HH:MM:SS"
    required String daysOfWeek,
    String? defaultVanId,
    String? defaultDriverId,
    String? defaultConductorId,
    String? tripLabel,
  }) async {
    await _api.post('/config/schedule-templates', body: {
      'route_id': routeId,
      'departure_time': departureTime,
      'days_of_week': daysOfWeek,
      if (defaultVanId != null) 'default_van_id': defaultVanId,
      if (defaultDriverId != null) 'default_driver_id': defaultDriverId,
      if (defaultConductorId != null) 'default_conductor_id': defaultConductorId,
      if (tripLabel != null && tripLabel.isNotEmpty) 'trip_label': tripLabel,
    });
  }

  Future<void> setTemplateActive(String templateId, bool isActive) async {
    await _api.patch('/config/schedule-templates/$templateId/active',
        query: {'is_active': isActive});
  }

  /// Materialises trips from active templates -- safe to run repeatedly,
  /// per the backend's own idempotency guarantee on (template_id, service_date).
  Future<List<GenerationReport>> generateTrips({int daysAhead = 1}) async {
    final result = await _api.post(
      '/config/trips/generate',
      query: {'days_ahead': daysAhead},
    );
    return (result as List)
        .map((e) => GenerationReport.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
