import 'package:flutter/material.dart';
import '../../../models/transit_node_model.dart';
import 'node_selector_field.dart';

class WhereToCard extends StatelessWidget {
  final TransitNodeModel? destination;
  final List<TransitNodeModel> nodes;
  final ValueChanged<TransitNodeModel?> onDestinationChanged;

  const WhereToCard({
    super.key,
    required this.destination,
    required this.nodes,
    required this.onDestinationChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // Reduced vertical padding since the huge text is gone
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      color: Colors.white,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(16),
        ),
        child: NodeSelectorField(
          icon: Icons.location_on, // Swapped to location icon
          iconColor: const Color(0xFFD9534F), // Red color for destination
          nodes: nodes,
          selected: destination,
          onChanged: onDestinationChanged, hintText: 'Where to?',
        ),
      ),
    );
  }
}