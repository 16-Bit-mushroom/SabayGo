import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// --- DATA MODEL ---
class TripRecord {
  final String tripId;
  final String plateNumber;
  final int manifestCount;
  int? visualCount;
  String? base64Image;
  bool isAuditing;
  bool hasBeenAudited;

  TripRecord({
    required this.tripId,
    required this.plateNumber,
    required this.manifestCount,
    this.visualCount,
    this.base64Image,
    this.isAuditing = false,
    this.hasBeenAudited = false,
  });

  bool get hasDiscrepancy => hasBeenAudited && visualCount != manifestCount;
  int get variance => hasBeenAudited ? (visualCount! - manifestCount).abs() : 0;
}

class OperatorRevenueDashboard extends StatefulWidget {
  const OperatorRevenueDashboard({super.key});

  @override
  State<OperatorRevenueDashboard> createState() => _OperatorRevenueDashboardState();
}

class _OperatorRevenueDashboardState extends State<OperatorRevenueDashboard> {
  final double totalDigitalRevenue = 12500.00;
  final double totalCashRevenue = 3200.00;
  final int totalPassengers = 104;

  late List<TripRecord> _recentTrips;

  @override
  void initState() {
    super.initState();
    _recentTrips = [
      TripRecord(tripId: 'TXN-88492', plateNumber: 'DVO-1234', manifestCount: 12),
      TripRecord(
        tripId: 'TXN-88491', 
        plateNumber: 'ABC-9876', 
        manifestCount: 14, 
        visualCount: 14, 
        hasBeenAudited: true 
      ), 
      TripRecord(tripId: 'TXN-88490', plateNumber: 'XYZ-5555', manifestCount: 10),
    ];
  }

  Future<void> _triggerAuditForTrip(int index) async {
    setState(() {
      _recentTrips[index].isAuditing = true;
      // Clear the old data out when a re-scan is triggered
      _recentTrips[index].hasBeenAudited = false;
      _recentTrips[index].visualCount = null; 
      _recentTrips[index].base64Image = null;
    });

    try {
      final response = await http.get(Uri.parse('http://10.247.15.183:5000/api/audit/live')).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _recentTrips[index].visualCount = data['visual_count'];
          _recentTrips[index].base64Image = data['image_data'];
          _recentTrips[index].hasBeenAudited = true;
        });
      } else {
        throw Exception('Failed to connect to AI node');
      }
    } catch (e) {
      await Future.delayed(const Duration(seconds: 2)); 
      
      setState(() {
        _recentTrips[index].visualCount = 1; 
        _recentTrips[index].base64Image = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=";
        _recentTrips[index].hasBeenAudited = true;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Vehicle camera unavailable. Loaded local fallback data.'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    } finally {
      setState(() {
        _recentTrips[index].isAuditing = false;
      });
    }
  }

  void _showFullScreenImage(BuildContext context, String base64String) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(10),
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(
                    base64Decode(base64String),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.white, size: 36),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
              Row(
                children: [
                  Expanded(child: _buildMetricCard('Digital (PayMongo)', '₱${totalDigitalRevenue.toStringAsFixed(0)}', Icons.account_balance_wallet, Colors.blue)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMetricCard('Walk-in (Cash)', '₱${totalCashRevenue.toStringAsFixed(0)}', Icons.payments, Colors.green)),
                ],
              ),
              const SizedBox(height: 12),
              _buildMetricCard('Total Verified Passengers', totalPassengers.toString(), Icons.people_alt, const Color(0xFF2D2059), isFullWidth: true),
              
              const SizedBox(height: 32),
              const Text(
                'Live Cabin Inspections',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2D2059)),
              ),
              const SizedBox(height: 16),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentTrips.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildReconciliationCard(_recentTrips[index], index),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

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

  Widget _buildReconciliationCard(TripRecord trip, int index) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: trip.hasBeenAudited 
              ? (trip.hasDiscrepancy ? Colors.red.shade300 : Colors.green.shade300) 
              : Colors.grey.shade200,
          width: trip.hasBeenAudited ? 2 : 1,
        ),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Trip ${trip.tripId}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (trip.hasBeenAudited)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: trip.hasDiscrepancy ? Colors.red.shade50 : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      trip.hasDiscrepancy ? 'Unaccounted: ${trip.variance}' : 'Reconciled',
                      style: TextStyle(
                        color: trip.hasDiscrepancy ? Colors.red.shade700 : Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  )
              ],
            ),
            const SizedBox(height: 4),
            Text('Plate: ${trip.plateNumber}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildCountColumn('Manifested Seats', trip.manifestCount.toString(), trip.hasDiscrepancy ? Colors.red : Colors.black87),
                Container(width: 1, height: 40, color: Colors.grey.shade300),
                _buildCountColumn(
                  'Actual Headcount', 
                  trip.hasBeenAudited ? trip.visualCount.toString() : '--', 
                  trip.hasDiscrepancy ? Colors.red : Colors.black87
                ),
              ],
            ),
            
            if (trip.base64Image != null) ...[
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              const Text('Cabin Snapshot', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              
              GestureDetector(
                onTap: () => _showFullScreenImage(context, trip.base64Image!),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      height: 160,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.black12,
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Image.memory(
                        base64Decode(trip.base64Image!),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => const Center(
                          child: Icon(Icons.broken_image, color: Colors.grey, size: 48)
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.zoom_out_map, color: Colors.white, size: 24),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 16),

            // --- ACTION BUTTONS ---
            if (trip.hasDiscrepancy)
              Row(
                children: [
                  // Alert Driver Button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Alert sent to Conductor of ${trip.plateNumber}.'),
                            backgroundColor: Colors.orange.shade800,
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.notification_important, size: 18),
                      label: const Text('Alert Conductor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Prominent Re-Scan Button
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: trip.isAuditing ? null : () => _triggerAuditForTrip(index),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.grey.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: trip.isAuditing 
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.refresh, size: 16),
                      label: Text(
                        trip.isAuditing ? 'Scanning...' : 'Re-Scan Cabin',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)
                      ),
                    ),
                  ),
                ],
              )
            else
              // Standard Scan / Re-Scan button for normal trips
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: trip.isAuditing ? null : () => _triggerAuditForTrip(index),
                  style: FilledButton.styleFrom(
                    backgroundColor: trip.hasBeenAudited ? Colors.grey.shade700 : const Color(0xFF00A859),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: trip.isAuditing 
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.camera_alt, size: 16),
                  label: Text(
                    trip.isAuditing 
                        ? 'Scanning...' 
                        : (trip.hasBeenAudited ? 'Re-Scan Cabin' : 'Scan Cabin'), 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountColumn(String label, String countStr, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          countStr,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}