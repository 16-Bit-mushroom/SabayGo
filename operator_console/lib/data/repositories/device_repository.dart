import '../../core/network/api_client.dart';

DateTime? _time(Object? v) => v == null ? null : DateTime.parse(v as String);

/// A phone in A2Z's pool (Table 28) and its open check-out (Table 29).
class Phone {
  const Phone({
    required this.deviceId,
    required this.model,
    required this.androidVersion,
    required this.appVersion,
    required this.status,
    required this.lastReportAt,
    required this.batteryPct,
    required this.batteryTempC,
    required this.cameraOk,
    required this.gpsOk,
    required this.silent,
    required this.checkout,
  });

  final String deviceId;
  final String model;
  final String? androidVersion;
  final String? appVersion;
  final String status; // in_office | checked_out | retired
  final DateTime? lastReportAt;
  final int? batteryPct;
  final double? batteryTempC;
  final bool? cameraOk;
  final bool? gpsOk;
  final bool silent;
  final PhoneCheckout? checkout;

  factory Phone.fromJson(Map<String, dynamic> j) => Phone(
        deviceId: j['device_id'] as String,
        model: j['device_model'] as String,
        androidVersion: j['android_version'] as String?,
        appVersion: j['app_version'] as String?,
        status: j['status'] as String,
        lastReportAt: _time(j['last_heartbeat_at']),
        batteryPct: j['battery_pct'] as int?,
        batteryTempC: j['battery_temp_c'] == null ? null : (j['battery_temp_c'] as num).toDouble(),
        cameraOk: j['camera_ok'] as bool?,
        gpsOk: j['gps_ok'] as bool?,
        silent: j['silent'] as bool,
        checkout: j['checkout'] == null
            ? null
            : PhoneCheckout.fromJson(j['checkout'] as Map<String, dynamic>),
      );
}

class PhoneCheckout {
  const PhoneCheckout({required this.plateNumber, required this.dispatcherName, required this.at});
  final String plateNumber;
  final String dispatcherName;
  final DateTime at;

  factory PhoneCheckout.fromJson(Map<String, dynamic> j) => PhoneCheckout(
        plateNumber: j['plate_number'] as String,
        dispatcherName: j['dispatcher_name'] as String,
        at: DateTime.parse(j['checked_out_at'] as String),
      );
}

/// The phone pool (brief 5.5): the Terminal Manager adds and retires; the
/// office checks a phone out to a Dispatcher and van and takes it back.
/// One phone as the door-camera page shows it (`GET /devices/live`, 12 Nov):
/// its latest report, the last two hours of reports, today's door counts,
/// and the trip its van is on. A reading the phone did not send is null --
/// shown as "not reported", never as zero.
class DoorCamera {
  DoorCamera.fromJson(Map<String, dynamic> j)
      : phone = Phone.fromJson(j),
        charging = j['charging'] as bool?,
        lensBlocked = j['lens_blocked'] as bool?,
        detectionRate = (j['detection_rate_hz'] as num?)?.toDouble(),
        reportsInWindow = j['report_count_window'] as int? ?? 0,
        history = [for (final p in j['history'] as List? ?? const []) ReportPoint.fromJson(p as Map<String, dynamic>)],
        boardedToday = j['boarded_today'] as int? ?? 0,
        alightedToday = j['alighted_today'] as int? ?? 0,
        trip = j['trip'] == null ? null : CameraTrip.fromJson(j['trip'] as Map<String, dynamic>);

  final Phone phone;
  final bool? charging;
  final bool? lensBlocked;
  final double? detectionRate;
  final int reportsInWindow;
  final List<ReportPoint> history;
  final int boardedToday;
  final int alightedToday;
  final CameraTrip? trip;
}

class ReportPoint {
  ReportPoint.fromJson(Map<String, dynamic> j)
      : at = DateTime.parse(j['at'] as String),
        detectionRate = (j['detection_rate_hz'] as num?)?.toDouble(),
        tempC = (j['battery_temp_c'] as num?)?.toDouble(),
        batteryPct = j['battery_pct'] as int?;
  final DateTime at;
  final double? detectionRate;
  final double? tempC;
  final int? batteryPct;
}

class CameraTrip {
  CameraTrip.fromJson(Map<String, dynamic> j)
      : tripId = j['trip_id'] as String,
        departure = DateTime.parse(j['departure_datetime'] as String),
        label = j['trip_label'] as String?,
        status = j['status'] as String,
        listed = j['listed'] as int? ?? 0,
        boarded = j['boarded'] as int? ?? 0,
        alighted = j['alighted'] as int? ?? 0,
        aboard = j['aboard'] as int? ?? 0;
  final String tripId;
  final DateTime departure;
  final String? label;
  final String status;
  final int listed;
  final int boarded;
  final int alighted;
  final int aboard;
}

class DeviceRepository {
  DeviceRepository(this._api);
  final ApiClient _api;

  /// The door-camera page's readings, the last [minutes] of reports.
  Future<List<DoorCamera>> live({int minutes = 120}) async => [
        for (final d in await _api.get('/devices/live', query: {'minutes': '$minutes'}) as List)
          DoorCamera.fromJson(d as Map<String, dynamic>)
      ];

  Future<List<Phone>> list() async => [
        for (final d in await _api.get('/devices') as List) Phone.fromJson(d as Map<String, dynamic>)
      ];

  /// The phone's token is shown once, here.
  Future<String> add({required String model, String? android}) async {
    final json = await _api.post('/devices', body: {
      'device_model': model,
      if (android != null && android.isNotEmpty) 'android_version': android,
    }) as Map<String, dynamic>;
    return json['device_token'] as String;
  }

  Future<String> reissueToken(String deviceId) async =>
      (await _api.post('/devices/$deviceId/token') as Map<String, dynamic>)['device_token'] as String;

  /// Warnings about the phone's last report; never a refusal.
  Future<List<String>> checkout(String deviceId, {required String vanId, required String dispatcherId}) async {
    final json = await _api.post('/devices/$deviceId/checkout',
        body: {'van_id': vanId, 'dispatcher_id': dispatcherId}) as Map<String, dynamic>;
    return [for (final w in json['warnings'] as List) w as String];
  }

  Future<void> giveBack(String deviceId, {String? note}) => _api.post('/devices/$deviceId/return',
      body: {if (note != null && note.isNotEmpty) 'return_note': note});

  Future<void> retire(String deviceId) => _api.post('/devices/$deviceId/retire');
}
