import '../../core/network/api_client.dart';

/// A request to rent the whole van (brief 2.5, Table 34): from the
/// passenger's app, or entered at the counter for a walk-in customer.
class RentalRequest {
  const RentalRequest({
    required this.requestId,
    required this.fromApp,
    required this.customerName,
    required this.customerContact,
    required this.pickupAt,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.passengerCount,
    required this.fee,
    required this.feeNote,
    required this.paymentStatus,
    required this.status,
    required this.tripId,
    required this.createdAt,
  });

  final String requestId;
  final bool fromApp;
  final String? customerName;
  final String? customerContact;
  final DateTime pickupAt;
  final String pickupAddress;
  final String destinationAddress;
  final int passengerCount;
  final double? fee;
  final String? feeNote;
  final String paymentStatus; // unpaid | paid
  final String status; // requested | approved | rejected | completed | cancelled
  final String? tripId;
  final DateTime createdAt;

  factory RentalRequest.fromJson(Map<String, dynamic> j) => RentalRequest(
        requestId: j['request_id'] as String,
        fromApp: j['passenger_user_id'] != null,
        customerName: j['customer_name'] as String?,
        customerContact: j['customer_contact'] as String?,
        pickupAt: DateTime.parse(j['pickup_at'] as String),
        pickupAddress: j['pickup_address'] as String,
        destinationAddress: j['destination_address'] as String,
        passengerCount: j['passenger_count'] as int,
        fee: j['rental_fee'] == null ? null : double.parse(j['rental_fee'].toString()),
        feeNote: j['fee_note'] as String?,
        paymentStatus: j['payment_status'] as String,
        status: j['status'] as String,
        tripId: j['trip_id'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

/// The office's side of special trips: review requests, enter a walk-in,
/// agree the fee (which creates the trip), or refuse with a reason.
class RentalRepository {
  RentalRepository(this._api);
  final ApiClient _api;

  Future<List<RentalRequest>> list({String? status}) async => [
        for (final r in await _api.get('/special-trips', query: {if (status != null) 'status': status}) as List)
          RentalRequest.fromJson(r as Map<String, dynamic>)
      ];

  Future<void> walkIn({
    required String name,
    required String contact,
    required DateTime pickupAt,
    required String pickup,
    required String destination,
    required int passengers,
    required String fee,
    required String feeNote,
  }) =>
      _api.post('/special-trips/walk-in', body: {
        'customer_name': name,
        'customer_contact': contact,
        'pickup_at': pickupAt.toIso8601String(),
        'pickup': {'address': pickup},
        'destination': {'address': destination},
        'passenger_count': passengers,
        'fee': fee,
        'fee_note': feeNote,
      });

  Future<void> approve(String requestId, {required String fee, required String feeNote}) =>
      _api.post('/special-trips/$requestId/approve', body: {'fee': fee, 'fee_note': feeNote});

  Future<void> reject(String requestId, String reason) =>
      _api.post('/special-trips/$requestId/reject', body: {'reason': reason});
}
