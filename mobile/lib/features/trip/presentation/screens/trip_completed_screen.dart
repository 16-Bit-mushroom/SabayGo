import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';

class TripCompletedScreen extends StatefulWidget {
  final String driverName;
  final String origin;
  final String destination;
  final double fare;
  final String paymentMethod;
  final VoidCallback onReturnHome;

  const TripCompletedScreen({
    Key? key,
    required this.driverName,
    required this.origin,
    required this.destination,
    required this.fare,
    required this.paymentMethod,
    required this.onReturnHome,
  }) : super(key: key);

  @override
  State<TripCompletedScreen> createState() => _TripCompletedScreenState();
}

class _TripCompletedScreenState extends State<TripCompletedScreen> {
  int _rating = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    // 1. Success Header
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle, color: AppColors.success, size: 64),
                    ),
                    const SizedBox(height: 16),
                    const Text("You've Arrived!", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    Text("Hope you enjoyed your ride with ${widget.driverName.split(' ').first}.", style: const TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                    const SizedBox(height: 32),

                    // 2. Rating System
                    const Text("Rate your driver", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return IconButton(
                          iconSize: 40,
                          icon: Icon(
                            index < _rating ? Icons.star : Icons.star_border,
                            color: index < _rating ? Colors.amber : Colors.grey.shade300,
                          ),
                          onPressed: () => setState(() => _rating = index + 1),
                        );
                      }),
                    ),
                    const SizedBox(height: 32),

                    // 3. Comprehensive Trip Summary Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // A. Proof of Service (Route)
                          const Text("Trip Route", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Column(
                                children: [
                                  const Icon(Icons.circle, color: Colors.blue, size: 12),
                                  Container(height: 20, width: 2, color: Colors.grey.shade300),
                                  const Icon(Icons.location_on, color: Colors.red, size: 12),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(widget.origin, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 14),
                                    Text(widget.destination, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              )
                            ],
                          ),
                          const Divider(height: 32),

                          // B. Financial Breakdown
                          const Text("Fare Breakdown", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 16),
                          _buildReceiptRow("Base Fare", "PHP 50.00"),
                          const SizedBox(height: 8),
                          // Dynamically calculating distance fare for realism
                          _buildReceiptRow("Distance Fare", "PHP ${(widget.fare - 50.0 + 10.0).toStringAsFixed(2)}"),
                          const SizedBox(height: 8),
                          _buildReceiptRow("Promo Applied", "-PHP 10.00", isGreen: true),
                          const Padding(padding: EdgeInsets.symmetric(vertical: 12.0), child: Divider(height: 1)),
                          _buildReceiptRow("Total Paid via ${widget.paymentMethod.toUpperCase()}", "PHP ${widget.fare.toStringAsFixed(2)}", isBold: true),
                          const Divider(height: 32),
                          
                          // C. Gamification (Eco-Impact)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              children: [
                                const Icon(Icons.eco, color: Colors.green, size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: const [
                                      Text("Eco-Impact", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                                      Text("You saved 1.2kg of CO2 on this shared ride!", style: TextStyle(fontSize: 12, color: Colors.green)),
                                    ],
                                  ),
                                )
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // 4. Submit Action
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: widget.onReturnHome,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryAction,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text("Submit & Finish", style: TextStyle(color: AppColors.surface, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, {bool isBold = false, bool isGreen = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        Text(
          value, 
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            fontSize: isBold ? 16 : 14,
            color: isGreen ? AppColors.success : AppColors.textPrimary,
          )
        ),
      ],
    );
  }
}