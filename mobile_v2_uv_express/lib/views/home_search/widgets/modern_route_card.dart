import 'package:flutter/material.dart';
import '../../../models/transit_node_model.dart';
import 'node_selector_field.dart';

class ModernRouteCard extends StatelessWidget {
  final TransitNodeModel? origin;
  final TransitNodeModel? destination;
  final ValueChanged<TransitNodeModel?> onOriginChanged;
  final ValueChanged<TransitNodeModel?> onDestinationChanged;

  const ModernRouteCard({
    super.key,
    required this.origin,
    required this.destination,
    required this.onOriginChanged,
    required this.onDestinationChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Stack(
        children: [
          // The connecting line between Origin and Destination
          Positioned(
            left: 23,
            top: 40,
            bottom: 40,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Column(
            children: [
              // Origin Selector
              NodeSelectorField(
                label: 'Origin',
                icon: Icons.my_location,
                iconColor: const Color(0xFF00A859), // Green for start
                nodes: const [], // TODO: Pass nodes from ViewModel
                selected: origin,
                onChanged: onOriginChanged,
              ),
              const SizedBox(height: 12),
              // Divider to separate the fields cleanly
              const Divider(height: 1, indent: 45),
              const SizedBox(height: 12),
              // Destination Selector
              NodeSelectorField(
                label: 'Destination',
                icon: Icons.location_on,
                iconColor: const Color(0xFFD9534F), // Red for end
                nodes: const [], // TODO: Pass nodes from ViewModel
                selected: destination,
                onChanged: onDestinationChanged,
              ),
            ],
          ),
          // Optional: A sleek swap button on the right edge
          Positioned(
            right: 0,
            top: 35,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.swap_vert, color: Colors.grey),
                onPressed: () {
                  // Swap logic can go here
                  final temp = origin;
                  onOriginChanged(destination);
                  onDestinationChanged(temp);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}