import 'package:flutter/material.dart';

class SubscriptionPaywallModal extends StatelessWidget {
  final VoidCallback onSubscribeSuccess;

  const SubscriptionPaywallModal({Key? key, required this.onSubscribeSuccess}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF2D2059).withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.card_membership, color: Color(0xFF2D2059), size: 40),
            ),
            const SizedBox(height: 16),
            const Text("Active Subscription Required", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2D2059))),
            const SizedBox(height: 8),
            const Text(
              "SabayGo operates on a 0% commission model. To match with drivers along McArthur Highway, please activate your monthly network access pass.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),

            // Plan Option 1: Commuter Student Pass
            _buildPlanCard(
              title: "Student Commuter Pass",
              price: "₱150",
              period: "/ month",
              badge: "CORRIDOR SPECIAL",
              features: "Unlimited P2P matching · Verified UM nodes",
              isRecommended: true,
            ),
            const SizedBox(height: 12),

            // Plan Option 2: Standard Pass
            _buildPlanCard(
              title: "Regular Commuter Pass",
              price: "₱300",
              period: "/ month",
              features: "Unlimited P2P matching · All corridor nodes",
              isRecommended: false,
            ),
            const SizedBox(height: 24),

            // Activate Button (Simulates successful subscription in defense demo)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close modal
                  onSubscribeSuccess();   // Trigger mock activation & continue ride booking
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A859),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text("Activate Pass (Demo Unlock)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Maybe Later", style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard({required String title, required String price, required String period, String? badge, required String features, required bool isRecommended}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRecommended ? const Color(0xFFE5F6EE) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isRecommended ? const Color(0xFF00A859) : Colors.grey.shade300, width: isRecommended ? 2 : 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (badge != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFF00A859), borderRadius: BorderRadius.circular(6)),
                    child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(features, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(price, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF2D2059))),
              Text(period, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}