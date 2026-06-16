import 'package:flutter/material.dart';
import 'package:mobile/core/theme/app_colors.dart';
import '../widgets/premium_feature_card.dart';
import '../widgets/premium_comparison_table.dart';

class GoPremiumScreen extends StatelessWidget {
  final VoidCallback onBackPressed;
  final VoidCallback onSubscribe;

  const GoPremiumScreen({
    Key? key,
    required this.onBackPressed,
    required this.onSubscribe,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                // 1. Premium Gradient Header
                Container(
                  padding: const EdgeInsets.only(bottom: 40),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF3B2E92), Color(0xFF9E54B0), Color(0xFFD6A04B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40), bottomRight: Radius.circular(40)),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            // FIX: Added explicit top padding to push it away from the edge
                            padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0), 
                            child: Row(
                              children: [
                                InkWell(
                                  onTap: onBackPressed,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                                    child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
                                  ),
                                ),
                                const Spacer(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withOpacity(0.3)),
                          ),
                          child: const Icon(Icons.workspace_premium, color: Colors.orangeAccent, size: 48),
                        ),
                        const SizedBox(height: 16),
                        const Text("EXCLUSIVE OFFER", style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text("Upgrade to\nCommute+", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, height: 1.2)),
                        const SizedBox(height: 16),
                        const Text("The smarter way to commute — only", style: TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withOpacity(0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text("₱250", style: TextStyle(color: Colors.amber, fontSize: 24, fontWeight: FontWeight.bold)),
                              Text(" /month", style: TextStyle(color: Colors.white70, fontSize: 14)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 2. Features List
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text("WHAT'S INCLUDED", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2, color: AppColors.textPrimary)),
                      SizedBox(height: 16),
                      PremiumFeatureCard(icon: Icons.flash_on, iconColor: Colors.orange, title: "100% Ad-Free Experience", description: "No banners, no interruptions. Just seamless rides."),
                      PremiumFeatureCard(icon: Icons.trending_up, iconColor: Colors.deepPurple, title: "Priority Matching During Peak Hours", description: "Get matched first when demand is high — always."),
                      PremiumFeatureCard(icon: Icons.shield_outlined, iconColor: AppColors.success, title: "Fixed-Price Protection", description: "No surge pricing, ever. Pay what you see."),
                      PremiumFeatureCard(icon: Icons.star_outline, iconColor: Colors.redAccent, title: "Premium Driver Quality", description: "Exclusively matched with 4.8★+ rated drivers."),
                      
                      SizedBox(height: 24),
                      PremiumComparisonTable(),
                      SizedBox(height: 40), 
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 3. Sticky Bottom Subscribe Bar
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16), // Adjusted bottom padding slightly to fit nav bar cleanly
            decoration: const BoxDecoration(
              color: AppColors.surface,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -4))],
            ),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(colors: [Color(0xFF2E3192), Color(0xFFD6A04B)]),
                  ),
                  child: ElevatedButton(
                    onPressed: onSubscribe,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.workspace_premium, color: Colors.orangeAccent, size: 20),
                        SizedBox(width: 8),
                        Text("Subscribe Now for ₱250/month", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text("By subscribing you agree to our Terms of Service", style: TextStyle(color: Colors.grey, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
      
     
    );
  }
}