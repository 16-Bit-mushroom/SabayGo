/// A fixed pick-up / drop-off point.
///
/// Passengers choose an origin and destination from this list only —
/// no free-form address entry (FR-3).
class TransitNodeModel {
  const TransitNodeModel({
    required this.id,
    required this.name,
    required this.area,
    this.stopSequence,
  });

  final String id;
  final String name; // e.g. "Ecoland Terminal"
  final String area; // e.g. "Davao City"

  /// Position on the route, 1-based.
  ///
  /// Booking works in stop sequences rather than terminal IDs, because
  /// the fare matrix and the seat inventory are both keyed on position:
  /// the same terminal can be stop 2 on one route and stop 5 on another.
  ///
  /// Nullable so the model still constructs where the sequence is not
  /// known — a saved destination, for instance, which is a place rather
  /// than a position on a particular route.
  final int? stopSequence;

  factory TransitNodeModel.fromApi(Map<String, dynamic> j) => TransitNodeModel(
        id: j['terminal_id'] as String,
        name: j['terminal_name'] as String,
        area: j['city'] as String? ?? '',
        stopSequence: j['stop_sequence'] as int?,
      );

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TransitNodeModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}