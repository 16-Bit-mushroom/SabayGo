import 'package:flutter/material.dart';

class CarpoolNode {
  final String id;
  final String name;
  final String landmark;
  final double latitude;
  final double longitude;

  const CarpoolNode({
    required this.id,
    required this.name,
    required this.landmark,
    required this.latitude,
    required this.longitude,
  });
}

class NodeSelectionHud extends StatelessWidget {
  final CarpoolNode? selectedPickup;
  final CarpoolNode? selectedDropoff;
  final Function(CarpoolNode) onSelectPickup;
  final Function(CarpoolNode) onSelectDropoff;
  final VoidCallback onRequestRide;

  const NodeSelectionHud({
    Key? key,
    required this.selectedPickup,
    required this.selectedDropoff,
    required this.onSelectPickup,
    required this.onSelectDropoff,
    required this.onRequestRide,
  }) : super(key: key);

  // Curated Geofenced Nodes along McArthur Highway Corridor
  static const List<CarpoolNode> corridorNodes = [
    CarpoolNode(id: 'node_1', name: 'UM Matina Gate', landmark: 'University of Mindanao Front Gate', latitude: 7.0644, longitude: 125.5581),
    CarpoolNode(id: 'node_2', name: 'Matina Crossing Overpass', landmark: 'Near Centerpoint Plaza', latitude: 7.0589, longitude: 125.5532),
    CarpoolNode(id: 'node_3', name: 'Bangkal Checkpoint Area', landmark: 'San Lorenzo Ruiz Parish Corridor', latitude: 7.0492, longitude: 125.5445),
    CarpoolNode(id: 'node_4', name: 'Ulas Junction Hub', landmark: 'Talomo Highway Split', latitude: 7.0381, longitude: 125.5320),
    CarpoolNode(id: 'node_5', name: 'Ecoland / SM City Turnoff', landmark: 'Quimpo Blvd Intersection', latitude: 7.0521, longitude: 125.5612),
  ];

  void _showNodePicker(BuildContext context, bool isPickup) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPickup ? "Select Pick-up Node" : "Select Drop-off Node",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D2059)),
              ),
              const SizedBox(height: 4),
              const Text(
                "Strict geofencing active along McArthur Highway corridor.",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: corridorNodes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final node = corridorNodes[index];
                    final isSelected = isPickup 
                        ? selectedPickup?.id == node.id 
                        : selectedDropoff?.id == node.id;

                    return ListTile(
                      leading: Icon(
                        isPickup ? Icons.my_location : Icons.flag,
                        color: isSelected ? const Color(0xFF00A859) : const Color(0xFF2D2059),
                      ),
                      title: Text(node.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                      subtitle: Text(node.landmark, style: const TextStyle(fontSize: 12)),
                      trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF00A859)) : null,
                      onTap: () {
                        if (isPickup) {
                          onSelectPickup(node);
                        } else {
                          onSelectDropoff(node);
                        }
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canRequest = selectedPickup != null && selectedDropoff != null && selectedPickup?.id != selectedDropoff?.id;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 14, color: Colors.amber),
              const SizedBox(width: 6),
              Text(
                "CORRIDOR RESTRICTED ROUTING",
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Pick-up Selector
          InkWell(
            onTap: () => _showNodePicker(context, true),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: Row(
                children: [
                  const Icon(Icons.radio_button_checked, color: Color(0xFF00A859), size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      selectedPickup?.name ?? "Select Pick-up Node...",
                      style: TextStyle(fontWeight: selectedPickup != null ? FontWeight.bold : FontWeight.normal, color: selectedPickup != null ? Colors.black : Colors.grey),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Drop-off Selector
          InkWell(
            onTap: () => _showNodePicker(context, false),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      selectedDropoff?.name ?? "Select Drop-off Node...",
                      style: TextStyle(fontWeight: selectedDropoff != null ? FontWeight.bold : FontWeight.normal, color: selectedDropoff != null ? Colors.black : Colors.grey),
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Request Ride Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: canRequest ? onRequestRide : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2D2059),
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text("Find a ride", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}