import 'package:flutter/material.dart';
import 'edit_dispatcher_profile_screen.dart';
import 'operator_revenue_dashboard.dart'; // Ensure this matches your file path
import '../auth/login_screen.dart';

class DispatcherProfileScreen extends StatelessWidget {
  const DispatcherProfileScreen({super.key});

  void _showSignOutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('Are you sure you want to end your shift and sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD9534F), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const String staffName = 'Adonis T. Zuma';
    const String role = 'Terminal Dispatcher';
    const String coopName = 'Davao UV Express Cooperative';
    const String assignedTerminal = 'Ecoland Terminal';

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 1. Dynamic Header & Profile Card ---
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Top colored background block
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2D2059),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
                  ),
                  child: const SafeArea(
                    child: Padding(
                      padding: EdgeInsets.only(top: 16, left: 24),
                      child: Text(
                        'Profile Management',
                        style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                ),
                // Overlapping Profile Card
                Padding(
                  padding: const EdgeInsets.only(top: 110, left: 20, right: 20),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 8))],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: const Color(0xFF2D2059).withOpacity(0.1),
                              child: const Icon(Icons.badge_outlined, size: 32, color: Color(0xFF2D2059)),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(staffName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87)),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2D2059),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(role, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_square, color: Color(0xFF2D2059), size: 24),
                              onPressed: () {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => const EditDispatcherProfileScreen()));
                              },
                            ),
                          ],
                        ),
                        const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(height: 1)),
                        
                        // Shift Quick Stats
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildQuickStat('Shift Status', 'Active', Colors.green),
                            Container(width: 1, height: 30, color: Colors.grey.shade300),
                            _buildQuickStat('Manifests', '12', Colors.black87),
                            Container(width: 1, height: 30, color: Colors.grey.shade300),
                            _buildQuickStat('Terminal', assignedTerminal, Colors.black87),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('OPERATIONS & LOGS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                  const SizedBox(height: 12),

                  // --- 2. Operational Settings Group ---
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: Column(
                      children: [
                        // Moved to the top, renamed, and wired up!
                        _buildSettingsTile(
                          icon: Icons.account_balance_wallet_outlined,
                          title: 'Revenue & Seat Reconciliation',
                          subtitle: 'Track digital fares and flag leakage',
                          iconColor: const Color(0xFF00A859), // Green to denote revenue
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const OperatorRevenueDashboard()),
                            );
                          },
                        ),
                        const Divider(height: 1, indent: 64),
                        _buildSettingsTile(
                          icon: Icons.history,
                          title: 'Shift History & Audit Logs',
                          subtitle: 'View past manifests and manual logs',
                          iconColor: const Color(0xFF2D2059),
                          onTap: () {},
                        ),
                        const Divider(height: 1, indent: 64),
                        _buildSettingsTile(
                          icon: Icons.settings_outlined,
                          title: 'System Settings',
                          subtitle: 'Theme, sync preferences, and cache',
                          iconColor: const Color(0xFF2D2059),
                          onTap: () {},
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // --- 3. Danger Zone (Sign Out) ---
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _showSignOutConfirmation(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFFD9534F), 
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFD9534F), width: 1.5),
                        ),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.logout, size: 20),
                      label: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 40), // Extra bottom padding for scroll space
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildQuickStat(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: valueColor, fontSize: 14, fontWeight: FontWeight.w900)),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon, 
    required String title, 
    required String subtitle, 
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 22, color: iconColor),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      ),
      trailing: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
      ),
      onTap: onTap,
    );
  }
}