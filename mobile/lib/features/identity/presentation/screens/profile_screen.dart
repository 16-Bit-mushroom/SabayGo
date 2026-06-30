import 'package:flutter/material.dart';
import 'package:mobile/features/identity/presentation/screens/passenger_verification_screen.dart';
import 'package:provider/provider.dart';
import 'package:mobile/core/theme/app_colors.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../widgets/settings_tile.dart';
import 'driver_registration_screen.dart'; 

class ProfileScreen extends StatelessWidget {
  final VoidCallback onEditProfile;
  final Function(String) onSettingsTap;
  final VoidCallback onSignOut;

  // MOCK FLAG: Toggle this to true to see the Green Verified Badge
  final bool isVerified = false; 

  const ProfileScreen({
    Key? key,
    required this.onEditProfile,
    required this.onSettingsTap,
    required this.onSignOut,
  }) : super(key: key);

  void _showSignOutConfirmation(BuildContext context, ProfileViewModel viewModel) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Sign Out", style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text("Are you sure you want to sign out of your account?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext); 
                viewModel.signOut();          
                onSignOut();                  
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade50,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Yes, Sign Out", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, top: 24, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary, fontSize: 12, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildTrailingPill(String text, {Color color = AppColors.textSecondary, Color bgColor = Colors.transparent}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor == Colors.transparent ? Colors.grey.shade100 : bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ProfileViewModel>();
    final user = viewModel.currentUser;

    if (viewModel.isLoading || user == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. STREAMLINED HEADER WITH VERIFICATION BADGE
            Container(
              padding: const EdgeInsets.only(bottom: 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32), bottomRight: Radius.circular(32)),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(width: 48), 
                          const Text("PASSENGER PROFILE", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.white, size: 20),
                            onPressed: onEditProfile,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                      child: const CircleAvatar(radius: 40, backgroundColor: Colors.white, child: Icon(Icons.person, size: 40, color: Colors.blue)),
                    ),
                    const SizedBox(height: 12),
                    Text(user.fullName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    
                    // RATING AND VERIFICATION BADGE ROW
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Rating Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, color: Colors.amber, size: 14), 
                              const SizedBox(width: 4), 
                              Text(user.rating.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))
                            ]
                          ),
                        ),
                        const SizedBox(width: 8),
                        
                        // Smart Verification Badge
                        GestureDetector(
                          onTap: () {
                            if (!isVerified) {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => const PassengerVerificationScreen()));
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: isVerified ? AppColors.success.withOpacity(0.2) : Colors.redAccent.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(isVerified ? Icons.verified : Icons.gpp_maybe, color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  isVerified ? "Verified" : "Verify Identity", 
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 2. THE PERMANENT "BECOME A DRIVER" BANNER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InkWell(
                onTap: () {
                  if (isVerified) {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const DriverRegistrationScreen()));
                  } else {
                    // Intercept unverified users
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Please verify your identity before applying to drive."),
                        backgroundColor: Colors.redAccent,
                      )
                    );
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const PassengerVerificationScreen()));
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF2D2059), Color(0xFF4A3492)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                        child: const Icon(Icons.directions_car, color: Colors.white, size: 28),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Become a Carpool Driver", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            SizedBox(height: 4),
                            Text("Share fuel costs directly with commuters.", style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 3. ESSENTIAL SETTINGS ONLY (SaaS & P2P Aligned)
            _buildSectionHeader("ACCOUNT & BILLING"),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                children: [
                  SettingsTile(icon: Icons.card_membership, iconColor: Colors.deepPurple, title: "SaaS Subscription", trailing: _buildTrailingPill("Active - ₱150/mo", color: AppColors.success, bgColor: AppColors.success.withOpacity(0.1)), onTap: () => onSettingsTap("subscription")),
                  const Divider(height: 1, indent: 48),
                  SettingsTile(icon: Icons.account_balance_wallet, iconColor: Colors.blue, title: "P2P e-Wallets (GCash)", onTap: () => onSettingsTap("ewallet")),
                  const Divider(height: 1, indent: 48),
                  SettingsTile(icon: Icons.location_on_outlined, iconColor: AppColors.success, title: "Saved Nodes", onTap: () => onSettingsTap("nodes")),
                ],
              ),
            ),

            _buildSectionHeader("SUPPORT"),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                children: [
                  SettingsTile(icon: Icons.shield_outlined, iconColor: Colors.red, title: "Privacy & Security", onTap: () => onSettingsTap("privacy")),
                  const Divider(height: 1, indent: 48),
                  SettingsTile(icon: Icons.help_outline, iconColor: Colors.grey, title: "Help & Support", onTap: () => onSettingsTap("support")),
                  const Divider(height: 1, indent: 48),
                  SettingsTile(icon: Icons.logout, iconColor: Colors.red, title: "Sign Out", onTap: () => _showSignOutConfirmation(context, viewModel)),
                ],
              ),
            ),
            
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}