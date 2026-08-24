/// Represents a fixed pick-up / drop-off point used across the app.
/// Passengers can only choose an origin or destination from this
/// predefined list — no free-form address entry (FR-3).
class TransitNodeModel {
  const TransitNodeModel({
    required this.id,
    required this.name,
    required this.area,
  });

  final String id;
  final String name; // e.g. "UM Matina Gate"
  final String area; // e.g. "Matina, Davao City"

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TransitNodeModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
