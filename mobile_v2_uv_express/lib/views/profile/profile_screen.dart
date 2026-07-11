import 'package:flutter/material.dart';
import '../../viewmodels/profile_viewmodel.dart';
import 'edit_profile_screen.dart';
import 'manage_destinations_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileViewModel _viewModel = ProfileViewModel();

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onStateChanged);
  }

  void _onStateChanged() => setState(() {});

  @override
  void dispose() {
    _viewModel.removeListener(_onStateChanged);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _viewModel.currentUser;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // FIXED: Consistent Header Size
            const Text(
              'Profile',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2D2059)),
            ),
            const SizedBox(height: 16),

            // --- 1. Profile Header Card ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundImage: NetworkImage(user.avatarUrl),
                        backgroundColor: Colors.grey.shade200,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star, color: Colors.orange, size: 14),
                                  const SizedBox(width: 4),
                                  Text('${user.trustRating} Trust Rating', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfileScreen(user: user)));
                        },
                        icon: const Icon(Icons.edit_square, color: Color(0xFF00A859), size: 24),
                      )
                    ],
                  ),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
                  _buildQuickInfo(Icons.phone_outlined, user.phoneNumber),
                  const SizedBox(height: 10),
                  _buildQuickInfo(Icons.email_outlined, user.email),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text('ACCOUNT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
            const SizedBox(height: 12),

            // --- 2. General Settings Group ---
            _buildSettingsGroup([
              _buildSettingsTile(Icons.home_work_outlined, 'Home Address', subtitle: user.address),
              _buildSettingsTile(Icons.person_outline, 'Gender', subtitle: user.gender),
              _buildSettingsTile(Icons.health_and_safety_outlined, 'Emergency Contact', subtitle: '${user.emergencyContactName}\n${user.emergencyContactPhone}', iconColor: Colors.red.shade400),
            ]),

            const SizedBox(height: 24),
            const Text('PREFERENCES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
            const SizedBox(height: 12),

            // --- 3. App Settings Group ---
            _buildSettingsGroup([
              _buildSettingsTile(Icons.bookmark_outline, 'Saved Destinations', onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => ManageDestinationsScreen(destinations: _viewModel.savedDestinations)));
              }),
              _buildSettingsTile(Icons.notifications_none, 'Notification Settings', onTap: () => _showNotificationSettingsSheet(context)),
              _buildSettingsTile(Icons.privacy_tip_outlined, 'Privacy & Policy', onTap: () {}),
            ]),

            const SizedBox(height: 32),

            // --- 4. Danger Zone Buttons (FIXED: Added Icons) ---
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () => _viewModel.signOut(),
                icon: const Icon(Icons.logout, size: 20, color: Colors.black87),
                label: const Text('Sign Out', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: TextButton.icon(
                onPressed: () {}, 
                icon: const Icon(Icons.person_remove_outlined, size: 20, color: Colors.red),
                label: const Text('Delete Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickInfo(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade500),
        const SizedBox(width: 12),
        Text(text, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w500, fontSize: 13)),
      ],
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: children.asMap().entries.map((entry) {
          int idx = entry.key;
          Widget child = entry.value;
          return Column(
            children: [
              child,
              if (idx != children.length - 1) const Divider(height: 1, indent: 52),
            ],
          );
        }).toList(),
      ),
    );
  }

  // FIXED: Standardized icon sizes to 20
  Widget _buildSettingsTile(IconData icon, String title, {String? subtitle, Color? iconColor, VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: (iconColor ?? const Color(0xFF2D2059)).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 20, color: iconColor ?? const Color(0xFF2D2059)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)) : null,
      trailing: onTap != null ? const Icon(Icons.chevron_right, size: 20, color: Colors.grey) : null,
    );
  }

  // FIXED: Added SafeArea, minimized text sizes and paddings
  void _showNotificationSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                    ),
                    const Text('Notification Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    
                    SwitchListTile(
                      title: const Text('Allow All Notifications', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      activeColor: const Color(0xFF00A859),
                      contentPadding: EdgeInsets.zero,
                      value: _viewModel.pushEnabled,
                      onChanged: (val) {
                        _viewModel.toggleAllNotifications(val);
                        setSheetState(() {});
                        setState(() {});
                      },
                    ),
                    const Divider(height: 16),
                    SwitchListTile(
                      title: const Text('Tailored Trip Schedules', style: TextStyle(fontSize: 14)),
                      subtitle: const Text('Get notified when a van matches your saved destinations.', style: TextStyle(fontSize: 12)),
                      activeColor: const Color(0xFF00A859),
                      contentPadding: EdgeInsets.zero,
                      value: _viewModel.tailoredSchedules,
                      onChanged: (val) {
                        _viewModel.toggleSpecificNotification('tailored', val);
                        setSheetState(() {});
                        setState(() {});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Trip Updates & Cancellations', style: TextStyle(fontSize: 14)),
                      activeColor: const Color(0xFF00A859),
                      contentPadding: EdgeInsets.zero,
                      value: _viewModel.tripUpdates,
                      onChanged: (val) {
                        _viewModel.toggleSpecificNotification('updates', val);
                        setSheetState(() {});
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}