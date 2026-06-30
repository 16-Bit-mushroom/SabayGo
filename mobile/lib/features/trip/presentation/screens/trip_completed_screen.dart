import 'package:flutter/material.dart';

class TripCompletedScreen extends StatelessWidget {
  final String driverName;
  final String origin;
  final String destination;
  final VoidCallback onReturnHome;

  const TripCompletedScreen({
    Key? key,
    required this.driverName,
    required this.origin,
    required this.destination,
    required this.onReturnHome,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Mocking the variables for the SabayGo formula: S = (D * (F+M)) / (P+1)
    const double distanceKm = 8.5; 
    const double fuelRatePerKm = 6.00;
    const double maintRatePerKm = 2.00;
    const int passengers = 3; // 3 commuters + 1 driver = 4 people sharing

    // The actual math
    const double totalRunningCost = distanceKm * (fuelRatePerKm + maintRatePerKm);
    const double sharedContribution = totalRunningCost / (passengers + 1);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text("Trip Completed", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: const Color(0xFFE5F6EE), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle, color: Color(0xFF00A859), size: 44),
            ),
            const SizedBox(height: 12),
            const Text("You've arrived at your destination!", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("Driver: $driverName", style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),

            // THE P2P COST-SHARE CALCULATOR (Objective 2.2.4)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calculate_outlined, color: Color(0xFF2D2059)),
                      const SizedBox(width: 8),
                      const Text("Cost-Share Breakdown", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2D2059))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text("Calculated strictly for non-profit cost recovery.", style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const Divider(height: 22),
                  
                  _buildMathRow("Distance Traveled (D)", "${distanceKm.toStringAsFixed(1)} km"),
                  const SizedBox(height: 8),
                  _buildMathRow("Fuel & Maint. Rate (F+M)", "₱${(fuelRatePerKm + maintRatePerKm).toStringAsFixed(2)} / km"),
                  const SizedBox(height: 8),
                  _buildMathRow("Total Running Cost", "₱${totalRunningCost.toStringAsFixed(2)}"),
                  const SizedBox(height: 8),
                  _buildMathRow("Total Occupants (P+1)", "${passengers + 1} persons"),
                  
                  const Divider(height: 32),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Your Contribution", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text("₱${sharedContribution.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Color(0xFF00A859))),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // DECENTRALIZED P2P SETTLEMENT
            const Text("Settle Directly with Driver", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Simulating GCash App launch for direct P2P transfer..."))
                  );
                },
                icon: const Icon(Icons.account_balance_wallet, color: Colors.white),
                label: const Text("Send via GCash (0% Platform Fee)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton(
                onPressed: onReturnHome,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2D2059)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("I paid in exact cash", style: TextStyle(color: Color(0xFF2D2059), fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildMathRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade700)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}