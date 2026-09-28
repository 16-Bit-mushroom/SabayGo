/// A walk-in logged while offline, waiting to reach the server.
///
/// `clientRequestId` is generated once, at the moment the conductor taps
/// submit, and sent on every retry. The backend dedupes bookings on
/// `(trip_id, client_request_id)`, so replaying this row after a
/// connectivity drop can never create a second booking for the same
/// passenger.
class PendingWalkIn {
  const PendingWalkIn({
    required this.clientRequestId,
    required this.tripId,
    required this.boardingStop,
    required this.alightingStop,
    required this.wantsReceipt,
    required this.isRoadsidePickup,
    required this.queuedAt,
    this.name,
    this.phone,
    this.pickupLandmark,
    this.fareOverride,
    this.fareNote,
  });

  final String clientRequestId;
  final String tripId;
  final int boardingStop;
  final int alightingStop;
  final String? name;
  final String? phone;
  final bool wantsReceipt;
  final bool isRoadsidePickup;
  final String? pickupLandmark;
  final double? fareOverride;
  final String? fareNote;
  final DateTime queuedAt;

  Map<String, Object?> toMap() => {
        'client_request_id': clientRequestId,
        'trip_id': tripId,
        'boarding_stop': boardingStop,
        'alighting_stop': alightingStop,
        'name': name,
        'phone': phone,
        'wants_receipt': wantsReceipt ? 1 : 0,
        'is_roadside_pickup': isRoadsidePickup ? 1 : 0,
        'pickup_landmark': pickupLandmark,
        'fare_override': fareOverride,
        'fare_note': fareNote,
        'queued_at': queuedAt.toIso8601String(),
      };

  factory PendingWalkIn.fromMap(Map<String, Object?> m) => PendingWalkIn(
        clientRequestId: m['client_request_id'] as String,
        tripId: m['trip_id'] as String,
        boardingStop: m['boarding_stop'] as int,
        alightingStop: m['alighting_stop'] as int,
        name: m['name'] as String?,
        phone: m['phone'] as String?,
        wantsReceipt: (m['wants_receipt'] as int) == 1,
        isRoadsidePickup: (m['is_roadside_pickup'] as int) == 1,
        pickupLandmark: m['pickup_landmark'] as String?,
        fareOverride: m['fare_override'] as double?,
        fareNote: m['fare_note'] as String?,
        queuedAt: DateTime.parse(m['queued_at'] as String),
      );
}
