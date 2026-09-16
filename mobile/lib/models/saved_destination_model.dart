/// A passenger's own saved place, as returned by
/// `GET /users/me/saved-destinations` (G.8).
///
/// Distinct from [TransitNodeModel]: a saved destination is a personal
/// label the passenger picked, with an optional link to a fixed terminal
/// and/or a free-text address -- not itself a stop on a route.
class SavedDestinationModel {
  const SavedDestinationModel({
    required this.id,
    required this.label,
    this.terminalId,
    this.address,
  });

  final String id;
  final String label;
  final String? terminalId;
  final String? address;

  factory SavedDestinationModel.fromApi(Map<String, dynamic> j) =>
      SavedDestinationModel(
        id: j['destination_id'] as String,
        label: j['label'] as String,
        terminalId: j['terminal_id'] as String?,
        address: j['address'] as String?,
      );
}
