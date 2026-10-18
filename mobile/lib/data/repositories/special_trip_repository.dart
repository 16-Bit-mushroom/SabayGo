import '../../core/network/api_client.dart';

/// A request to rent the whole van (brief 2.5, Table 34).
class SpecialTripRequest {
  const SpecialTripRequest({
    required this.requestId,
    required this.pickupAt,
    required this.pickupAddress,
    required this.destinationAddress,
    required this.passengerCount,
    required this.fee,
    required this.feeNote,
    required this.paymentStatus,
    required this.status,
  });

  final String requestId;
  final DateTime pickupAt;
  final String pickupAddress;
  final String destinationAddress;
  final int passengerCount;
  /// Agreed by A2Z when it approves; null until then.
  final double? fee;
  final String? feeNote;
  final String paymentStatus; // unpaid | paid
  final String status; // requested | approved | rejected | completed | cancelled

  bool get canWithdraw => status == 'requested';
  bool get canPay => status == 'approved' && paymentStatus != 'paid' && fee != null;

  factory SpecialTripRequest.fromJson(Map<String, dynamic> j) => SpecialTripRequest(
        requestId: j['request_id'] as String,
        pickupAt: DateTime.parse(j['pickup_at'] as String),
        pickupAddress: j['pickup_address'] as String,
        destinationAddress: j['destination_address'] as String,
        passengerCount: j['passenger_count'] as int,
        fee: j['rental_fee'] == null ? null : double.parse(j['rental_fee'].toString()),
        feeNote: j['fee_note'] as String?,
        paymentStatus: j['payment_status'] as String,
        status: j['status'] as String,
      );
}

/// Renting the whole van: request, follow, withdraw before approval, pay
/// the agreed fee through the gateway before the van leaves.
class SpecialTripRepository {
  SpecialTripRepository(this._api);
  final ApiClient _api;

  Future<SpecialTripRequest> request({
    required DateTime pickupAt,
    required String pickupAddress,
    required String destinationAddress,
    required int passengerCount,
  }) async =>
      SpecialTripRequest.fromJson(await _api.post('/special-trips', body: {
        'pickup_at': pickupAt.toIso8601String(),
        'pickup': {'address': pickupAddress},
        'destination': {'address': destinationAddress},
        'passenger_count': passengerCount,
      }) as Map<String, dynamic>);

  Future<List<SpecialTripRequest>> mine() async => [
        for (final r in await _api.get('/special-trips/mine') as List)
          SpecialTripRequest.fromJson(r as Map<String, dynamic>)
      ];

  Future<void> withdraw(String requestId) => _api.post('/special-trips/$requestId/withdraw');

  /// The gateway page for the agreed fee. Only the verified webhook marks
  /// it paid.
  Future<String> checkout(String requestId) async =>
      (await _api.post('/special-trips/$requestId/checkout') as Map<String, dynamic>)['checkout_url'] as String;
}
