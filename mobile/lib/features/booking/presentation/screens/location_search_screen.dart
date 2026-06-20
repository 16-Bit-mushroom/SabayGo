import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/booking_viewmodel.dart';

class LocationSelectionScreen extends StatefulWidget {
  const LocationSelectionScreen({Key? key}) : super(key: key);

  @override
  State<LocationSelectionScreen> createState() => _LocationSelectionScreenState();
}

class _LocationSelectionScreenState extends State<LocationSelectionScreen> {
  late TextEditingController _pickupController;
  late TextEditingController _dropoffController;

  // Mock recent locations for a realistic prototype feel
  final List<Map<String, String>> _recentPlaces = [
    {"name": "University of Mindanao - Matina", "address": "Matina Crossing, Davao City", "icon": "school"},
    {"name": "SM City Davao", "address": "Quimpo Blvd, Ecoland, Davao City", "icon": "shopping_bag"},
    {"name": "Ulas Junction", "address": "Ulas, Davao City", "icon": "history"},
    {"name": "Ecoland Bus Terminal", "address": "Candelaria St, Davao City", "icon": "directions_bus"},
  ];

  @override
  void initState() {
    super.initState();
    // Grab the existing data from the ViewModel if the user is editing their route
    final vm = context.read<BookingViewModel>();
    _pickupController = TextEditingController(text: vm.selectedPickup ?? "Current Location");
    _dropoffController = TextEditingController(text: vm.selectedDropoff ?? "");
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    super.dispose();
  }

  void _confirmRoute() {
    if (_pickupController.text.isNotEmpty && _dropoffController.text.isNotEmpty) {
      
      // CALL THE NEW METHOD INSTEAD OF requestRide
      context.read<BookingViewModel>().setRouteAndSelectRide(
        _pickupController.text, 
        _dropoffController.text
      );
      
      // Pop back to the Dashboard
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter both pickup and drop-off locations.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // TOP SECTION: The Search Inputs
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 5))
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const Expanded(
                        child: Text(
                          "Plan Your Ride", 
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 20), // Balance the back button
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // The Input Fields with the connecting line
                  Row(
                    children: [
                      // Visual Route Indicators
                      Column(
                        children: [
                          const Icon(Icons.my_location, color: Colors.blue, size: 20),
                          Container(height: 30, width: 2, color: Colors.grey.shade300),
                          const Icon(Icons.location_on, color: Colors.red, size: 20),
                        ],
                      ),
                      const SizedBox(width: 16),
                      // Text Fields
                      Expanded(
                        child: Column(
                          children: [
                            TextField(
                              controller: _pickupController,
                              decoration: InputDecoration(
                                hintText: "Pickup Location",
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _dropoffController,
                              autofocus: true, // Automatically pops the keyboard for the destination
                              decoration: InputDecoration(
                                hintText: "Where to?",
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // BOTTOM SECTION: Saved & Recent Places
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(20),
                itemCount: _recentPlaces.length,
                separatorBuilder: (context, index) => Divider(color: Colors.grey.shade200),
                itemBuilder: (context, index) {
                  final place = _recentPlaces[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Colors.grey.shade100,
                      child: Icon(_getIcon(place["icon"]!), color: const Color(0xFF2D2059), size: 20),
                    ),
                    title: Text(place["name"]!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    subtitle: Text(place["address"]!, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    onTap: () {
                      // Instantly fill the drop-off and confirm
                      setState(() {
                        _dropoffController.text = place["name"]!;
                      });
                      _confirmRoute();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      // FLOATING CONFIRM BUTTON
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _confirmRoute,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D2059),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text("Confirm Route", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  IconData _getIcon(String iconName) {
    switch (iconName) {
      case 'school': return Icons.school;
      case 'shopping_bag': return Icons.shopping_bag;
      case 'directions_bus': return Icons.directions_bus;
      default: return Icons.history;
    }
  }
}