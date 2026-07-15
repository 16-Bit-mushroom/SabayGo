import 'package:flutter/material.dart';
import 'edit_dispatcher_profile_screen.dart';
import '../auth/login_screen.dart';

class DispatcherProfileScreen extends StatelessWidget {
  const DispatcherProfileScreen({super.key});

  // --- Sign Out Confirmation Dialog ---
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
              onPressed: () => Navigator.pop(context), // Close Dialog
              child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            FilledButton(
              onPressed: () {
                // 1. Close dialog
                Navigator.pop(context);
                
                // 2. TODO: Clear local session/JWT tokens via AuthService
                
                // 3. Route to Login and clear stack entirely
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD9534F), // Destructive Red
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
    // Mock Data for the Terminal Staff
    const String staffName = 'Rodrigo M. Duterte';
    const String role = 'Terminal Dispatcher';
    const String coopName = 'Davao UV Express Cooperative';
    const String assignedTerminal = 'Ecoland Terminal';

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Profile Management', style: TextStyle(fontSize: 18, color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- 1. Main Profile Card ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
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
                              const SizedBox(height: 4),
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
                        // --- Edit Profile Button ---
                        IconButton(
                          icon: const Icon(Icons.edit_square, color: Color(0xFF2D2059), size: 24),
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const EditDispatcherProfileScreen()));
                          },
                        ),
                      ],
                    ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
                    _buildInfoRow(Icons.business_outlined, 'Cooperative / Franchise', coopName),
                    const SizedBox(height: 12),
                    _buildInfoRow(Icons.location_on_outlined, 'Assigned Terminal', assignedTerminal),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              const Text('OPERATIONS & LOGS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
              const SizedBox(height: 12),

              // --- 2. Operational Settings Group ---
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Column(
                  children: [
                    _buildSettingsTile(Icons.history, 'Shift History & Audit Logs'),
                    const Divider(height: 1, indent: 52),
                    _buildSettingsTile(Icons.analytics_outlined, 'Terminal Analytics'),
                    const Divider(height: 1, indent: 52),
                    _buildSettingsTile(Icons.settings_outlined, 'System Settings'),
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
                  label: const Text('End Shift & Sign Out', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade500),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  Widget _buildSettingsTile(IconData icon, String title) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2059).withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: const Color(0xFF2D2059)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87)),
      trailing: const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
      onTap: () {
        // Feature placeholders
      },
    );
  }
}