import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile/core/theme/app_colors.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../widgets/profile_kpi_card.dart';
import '../widgets/settings_tile.dart';
import 'driver_registration_screen.dart'; // INJECTED: Import the new screen

class ProfileScreen extends StatelessWidget {
  final VoidCallback onEditProfile;
  final Function(String) onSettingsTap;
  final VoidCallback onSignOut;

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
          content: const Text("Are you sure you want to sign out of your passenger account?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel", style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext); // Close the dialogue
                viewModel.signOut();          // Clear backend state
                onSignOut();                  // Trigger navigation back to login
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
            // Header Gradient Section
            Container(
              padding: const EdgeInsets.only(bottom: 32),
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
                          Text("${user.accountType.toUpperCase()} · PROFILE", style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.white, size: 20),
                            onPressed: onEditProfile,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                      child: const CircleAvatar(radius: 40, backgroundColor: Colors.white, child: Icon(Icons.person, size: 40, color: Colors.blue)),
                    ),
                    const SizedBox(height: 12),
                    Text(user.fullName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.circle, color: AppColors.success, size: 8),
                        const SizedBox(width: 6),
                        Text("${user.accountType} · ${user.subscriptionTier}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                          child: Row(children: [const Icon(Icons.star, color: Colors.amber, size: 14), const SizedBox(width: 4), Text(user.rating.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))]),
                        ),
                        const SizedBox(width: 12),
                        const Text("|", style: TextStyle(color: Colors.white54)),
                        const SizedBox(width: 12),
                        Text("Member since ${user.joinDate}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    )
                  ],
                ),
              ),
            ),

            // KPI Cards
            Transform.translate(
              offset: const Offset(0, -20),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  children: [
                    ProfileKpiCard(icon: Icons.directions_car, iconColor: Colors.red, value: user.totalTrips.toString(), label: "Total Trips"),
                    ProfileKpiCard(icon: Icons.eco, iconColor: AppColors.success, value: user.co2Saved, label: "CO₂ Saved"),
                    ProfileKpiCard(icon: Icons.star, iconColor: Colors.amber, value: "${user.rating}★", label: "Avg Rating"),
                    ProfileKpiCard(icon: Icons.confirmation_num, iconColor: Colors.deepOrange, value: user.availableVouchers.toString(), label: "Vouchers"),
                  ],
                ),
              ),
            ),

            // INJECTED: THE NEW "DRIVE WITH SABAYGO" BANNER
            // THE SMART ROLE BANNER
            if (user.accountType.toLowerCase() == 'passenger')
              // Show the Upgrade Banner for standard commuters
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const DriverRegistrationScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2D2059), Color(0xFF4A3492)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
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
                              Text("Share fuel costs and reduce your carbon footprint.", style: TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                      ],
                    ),
                  ),
                ),
              )
            else
              // Show the Management Banner for approved Drivers
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InkWell(
                  onTap: () {
                    // Later, this will route to a "Vehicle Settings" screen
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Opening Vehicle Settings...")));
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.success.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), shape: BoxShape.circle),
                          child: const Icon(Icons.verified_user, color: AppColors.success, size: 28),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Driver Status: Active", style: TextStyle(color: AppColors.success, fontSize: 16, fontWeight: FontWeight.bold)),
                              SizedBox(height: 4),
                              Text("Manage vehicle details and compliance documents.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        ),
                        const Icon(Icons.settings, color: Colors.grey, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),

            // Settings Sections
            _buildSectionHeader("ACCOUNT"),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                children: [
                  SettingsTile(icon: Icons.credit_card, iconColor: Colors.deepPurple, title: "Payment Methods", trailing: _buildTrailingPill("3 saved"), onTap: () => onSettingsTap("payments")),
                  const Divider(height: 1, indent: 48),
                  SettingsTile(icon: Icons.notifications_none, iconColor: Colors.orange, title: "Notifications", trailing: _buildTrailingPill("On"), showArrow: false, onTap: () => onSettingsTap("notifications")),
                  const Divider(height: 1, indent: 48),
                  SettingsTile(icon: Icons.shield_outlined, iconColor: Colors.red, title: "Privacy & Security", onTap: () => onSettingsTap("privacy")),
                  const Divider(height: 1, indent: 48),
                  SettingsTile(icon: Icons.location_on_outlined, iconColor: AppColors.success, title: "Saved Addresses", trailing: _buildTrailingPill("2 saved"), onTap: () => onSettingsTap("addresses")),
                ],
              ),
            ),

            _buildSectionHeader("COMMUTE+"),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                children: [
                  SettingsTile(icon: Icons.workspace_premium, iconColor: Colors.amber, title: "Upgrade to Premium", trailing: _buildTrailingPill("₱250/mo", color: Colors.amber.shade700, bgColor: Colors.amber.withOpacity(0.1)), onTap: () => onSettingsTap("premium")),
                  const Divider(height: 1, indent: 48),
                  SettingsTile(icon: Icons.energy_savings_leaf_outlined, iconColor: AppColors.success, title: "Eco Impact Report", onTap: () => onSettingsTap("eco_report")),
                ],
              ),
            ),

            _buildSectionHeader("SUPPORT"),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                children: [
                  SettingsTile(icon: Icons.help_outline, iconColor: Colors.grey, title: "Help & Support", onTap: () => onSettingsTap("support")),
                  const Divider(height: 1, indent: 48),
                  SettingsTile(
                    icon: Icons.logout, 
                    iconColor: Colors.red, 
                    title: "Sign Out", 
                    onTap: () => _showSignOutConfirmation(context, viewModel) // Connect the dialogue here
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}