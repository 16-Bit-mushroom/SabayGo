import 'package:flutter/material.dart';
import '../../models/transit_node_model.dart';

class ManageDestinationsScreen extends StatefulWidget {
  final List<TransitNodeModel> destinations;
  
  const ManageDestinationsScreen({super.key, required this.destinations});

  @override
  State<ManageDestinationsScreen> createState() => _ManageDestinationsScreenState();
}

class _ManageDestinationsScreenState extends State<ManageDestinationsScreen> {
  late List<TransitNodeModel> _myDestinations;

  @override
  void initState() {
    super.initState();
    _myDestinations = List.from(widget.destinations);
  }

  void _deleteDestination(int index) {
    setState(() {
      _myDestinations.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Destination removed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Saved Destinations', style: TextStyle(fontSize: 18, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            onPressed: () {
              // TODO: Open Add Destination Modal
            },
            icon: const Icon(Icons.add, color: Color(0xFF00A859)),
          )
        ],
      ),
      body: SafeArea(
        child: _myDestinations.isEmpty
            ? _buildEmptyState()
            : ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: _myDestinations.length,
                separatorBuilder: (context, index) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final node = _myDestinations[index];
                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: const Color(0xFFD9534F).withOpacity(0.1), shape: BoxShape.circle),
                                child: const Icon(Icons.location_on, color: Color(0xFFD9534F), size: 20),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(node.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    const SizedBox(height: 2),
                                    Text(node.area, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  // TODO: Update destination logic
                                },
                                icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.grey),
                              ),
                              IconButton(
                                onPressed: () => _deleteDestination(index),
                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                // TODO: Navigate to Home Screen and auto-filter by this destination
                                DefaultTabController.of(context).animateTo(0);
                                Navigator.pop(context);
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF00A859).withOpacity(0.1),
                                foregroundColor: const Color(0xFF00A859),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.search, size: 18),
                              label: const Text('Check Available Trips', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          )
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bookmark_outline, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No saved destinations yet', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Add places you frequently travel to.', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }
}