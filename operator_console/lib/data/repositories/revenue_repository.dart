import 'dart:typed_data';

import '../../core/network/api_client.dart';

class RevenueSummary {
  const RevenueSummary({
    required this.trips,
    required this.totalBookings,
    required this.appBookings,
    required this.walkinBookings,
    required this.collectedFare,
    required this.cashInHand,
    required this.expectedFare,
    required this.unreconciledAmount,
    required this.pendingAudits,
    required this.walkinSharePct,
  });

  final int trips;
  final int totalBookings;
  final int appBookings;
  final int walkinBookings;
  final double collectedFare;
  final double cashInHand;
  final double expectedFare;
  final double unreconciledAmount;
  final int pendingAudits;
  final double walkinSharePct;

  // This endpoint returns a raw SQL row, not a Pydantic model -- MySQL's
  // SUM() over the reconciliation view comes back as a Decimal that
  // FastAPI's default encoder renders as a JSON string (e.g. "1"), unlike
  // /revenue/trips, which types these properly through a response_model.
  // Parsed leniently here so either shape works.
  static int _int(dynamic v) => v is int ? v : int.parse('$v');
  static double _double(dynamic v) => v is num ? v.toDouble() : double.parse('$v');

  factory RevenueSummary.fromJson(Map<String, dynamic> json) => RevenueSummary(
        trips: _int(json['trips']),
        totalBookings: _int(json['total_bookings']),
        appBookings: _int(json['app_bookings']),
        walkinBookings: _int(json['walkin_bookings']),
        collectedFare: _double(json['collected_fare']),
        cashInHand: _double(json['cash_in_hand']),
        expectedFare: _double(json['expected_fare']),
        unreconciledAmount: _double(json['unreconciled_amount']),
        pendingAudits: _int(json['pending_audits']),
        walkinSharePct: _double(json['walkin_share_pct']),
      );
}

/// Per-trip reconciliation row.
///
/// `cashInHand` is cash the crew has collected but not yet remitted to the
/// office -- it is deliberately kept separate from `unreconciledAmount`,
/// which is fare nobody has accounted for at all. Conflating the two would
/// make every honest conductor look like they were stealing until they
/// physically handed the cash over.
class TripRevenue {
  const TripRevenue({
    required this.tripId,
    required this.serviceDate,
    required this.departureDatetime,
    required this.routeName,
    this.plateNumber,
    required this.seatCapacity,
    required this.totalBookings,
    required this.appBookings,
    required this.walkinBookings,
    required this.collectedFare,
    required this.cashInHand,
    required this.expectedFare,
    required this.unreconciledAmount,
    this.maxYoloVariance,
    required this.pendingAudits,
  });

  final String tripId;
  final DateTime serviceDate;
  final DateTime departureDatetime;
  final String routeName;
  final String? plateNumber;
  final int seatCapacity;
  final int totalBookings;
  final int appBookings;
  final int walkinBookings;
  final double collectedFare;
  final double cashInHand;
  final double expectedFare;
  final double unreconciledAmount;
  final int? maxYoloVariance;
  final int pendingAudits;

  factory TripRevenue.fromJson(Map<String, dynamic> json) => TripRevenue(
        tripId: json['trip_id'] as String,
        serviceDate: DateTime.parse(json['service_date'] as String),
        departureDatetime: DateTime.parse(json['departure_datetime'] as String),
        routeName: json['route_name'] as String,
        plateNumber: json['plate_number'] as String?,
        seatCapacity: json['seat_capacity'] as int,
        totalBookings: json['total_bookings'] as int,
        appBookings: json['app_bookings'] as int,
        walkinBookings: json['walkin_bookings'] as int,
        collectedFare: double.parse('${json['collected_fare']}'),
        cashInHand: double.parse('${json['cash_in_hand']}'),
        expectedFare: double.parse('${json['expected_fare']}'),
        unreconciledAmount: double.parse('${json['unreconciled_amount']}'),
        maxYoloVariance: json['max_yolo_variance'] as int?,
        pendingAudits: json['pending_audits'] as int,
      );
}

class RevenueRepository {
  RevenueRepository(this._api);
  final ApiClient _api;

  Future<RevenueSummary> summary({DateTime? dateFrom, DateTime? dateTo}) async {
    final json = await _api.get('/revenue/summary', query: {
      if (dateFrom != null) 'date_from': _dateOnly(dateFrom),
      if (dateTo != null) 'date_to': _dateOnly(dateTo),
    });
    return RevenueSummary.fromJson(json as Map<String, dynamic>);
  }

  /// The reconciliation as a spreadsheet (G.1). `format` is 'xlsx' or 'csv'.
  Future<Uint8List> export({
    String format = 'xlsx',
    DateTime? dateFrom,
    DateTime? dateTo,
  }) =>
      _api.getBytes('/revenue/export', query: {
        'format': format,
        if (dateFrom != null) 'date_from': _dateOnly(dateFrom),
        if (dateTo != null) 'date_to': _dateOnly(dateTo),
      });

  Future<List<TripRevenue>> trips({DateTime? dateFrom, DateTime? dateTo, int limit = 100}) async {
    final json = await _api.get('/revenue/trips', query: {
      if (dateFrom != null) 'date_from': _dateOnly(dateFrom),
      if (dateTo != null) 'date_to': _dateOnly(dateTo),
      'limit': limit,
    });
    return (json as List).map((e) => TripRevenue.fromJson(e as Map<String, dynamic>)).toList();
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
