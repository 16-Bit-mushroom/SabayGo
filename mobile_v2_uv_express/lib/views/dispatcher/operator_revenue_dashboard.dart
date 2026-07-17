import 'package:flutter/material.dart';

class OperatorRevenueDashboard extends StatelessWidget {
  const OperatorRevenueDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    // MOCK DATA: Simulating a day's operations to demonstrate Objective 1.3.2.4
    const double totalDigitalRevenue = 12500.00;
    const double totalCashRevenue = 3200.00;
    const int totalPassengers = 104;
    
    // Simulating a discrepancy flag for the leakage alert
    const bool hasLeakage = true; 

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Revenue & Reconciliation', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF2D2059),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 1. HIGH LEVEL METRICS ---
              Row(
                children: [
                  Expanded(child: _buildMetricCard('Digital (PayMongo)', '₱${totalDigitalRevenue.toStringAsFixed(0)}', Icons.account_balance_wallet, Colors.blue)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMetricCard('Walk-in (Cash)', '₱${totalCashRevenue.toStringAsFixed(0)}', Icons.payments, Colors.green)),
                ],
              ),
              const SizedBox(height: 12),
              _buildMetricCard('Total Verified Passengers', totalPassengers.toString(), Icons.people_alt, const Color(0xFF2D2059), isFullWidth: true),
              
              const SizedBox(height: 24),

              // --- 2. REVENUE LEAKAGE ALERT (Objective 1.3.2.4) ---
              if (hasLeakage)
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade300, width: 2),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Discrepancy Detected',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Trip TXN-88492 (Plate: DVO-1234) departed with 14 passengers, but only 12 tickets were manifested. Potential leakage: ₱300.00.',
                              style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // --- 3. SEAT RECONCILIATION LIST ---
              const Text(
                'Recent Trip Reconciliation',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D2059)),
              ),
              const SizedBox(height: 16),
              
              // Mock Trip 1: Discrepancy (The issue flagged above)
              _buildReconciliationCard(
                tripId: 'TXN-88492',
                plateNumber: 'DVO-1234',
                manifestCount: 12,
                driverHeadcount: 14,
                hasDiscrepancy: true,
              ),
              
              const SizedBox(height: 12),

              // Mock Trip 2: Perfect Match
              _buildReconciliationCard(
                tripId: 'TXN-88491',
                plateNumber: 'ABC-9876',
                manifestCount: 14,
                driverHeadcount: 14,
                hasDiscrepancy: false,
              ),

              const SizedBox(height: 12),

              // Mock Trip 3: Perfect Match
              _buildReconciliationCard(
                tripId: 'TXN-88490',
                plateNumber: 'XYZ-5555',
                manifestCount: 10,
                driverHeadcount: 10,
                hasDiscrepancy: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper for Top Metrics
  Widget _buildMetricCard(String title, String value, IconData icon, Color color, {bool isFullWidth = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(fontSize: isFullWidth ? 24 : 20, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  // Helper for Reconciliation List Items
  Widget _buildReconciliationCard({
    required String tripId, 
    required String plateNumber, 
    required int manifestCount, 
    required int driverHeadcount, 
    required bool hasDiscrepancy
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasDiscrepancy ? Colors.red.shade200 : Colors.grey.shade200),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Trip $tripId', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasDiscrepancy ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hasDiscrepancy ? 'Audit Required' : 'Reconciled',
                    style: TextStyle(
                      color: hasDiscrepancy ? Colors.red.shade700 : Colors.green.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildCountColumn('Manifested', manifestCount, hasDiscrepancy ? Colors.red : Colors.black87),
                Container(width: 1, height: 40, color: Colors.grey.shade300),
                _buildCountColumn('Driver Headcount', driverHeadcount, hasDiscrepancy ? Colors.red : Colors.black87),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountColumn(String label, int count, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}