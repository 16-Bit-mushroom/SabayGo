import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';

class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [

            // Plan 1: Student Pass
            _buildPlanCard(
              context,
              title: "Student Commuter Pass",
              price: "₱150",
              features: ["Unlimited matching", "All Matina-Ulas nodes", "Priority support"],
              isRecommended: true,
            ),
            const SizedBox(height: 16),

            // Plan 2: Regular Pass
            _buildPlanCard(
              context,
              title: "Regular Commuter Pass",
              price: "₱300",
              features: ["Unlimited matching", "All corridor nodes", "Eco-Impact Reports"],
              isRecommended: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context, {required String title, required String price, required List<String> features, required bool isRecommended}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isRecommended ? Colors.amber : Colors.grey.shade200, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              Text(price, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: AppColors.primaryAction)),
            ],
          ),
          const SizedBox(height: 16),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [const Icon(Icons.check, size: 16, color: Colors.green), const SizedBox(width: 8), Text(f)]),
          )),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Subscription activated successfully!")));
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2D2059), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text("Subscribe Now", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}