import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../data/repositories/profile_repository.dart';
import '../../models/passenger_moderl.dart';
import '../../viewmodels/auth_provider.dart';
import '../../viewmodels/profile_viewmodel.dart';
import 'edit_profile_screen.dart';
import 'manage_destinations_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = ProfileViewModel(ProfileRepository(context.read<ApiClient>()));
    _viewModel.addListener(_onStateChanged);
    _viewModel.load();
  }

  void _onStateChanged() => setState(() {});

  @override
  void dispose() {
    _viewModel.removeListener(_onStateChanged);
    _viewModel.dispose();
    super.dispose();
  }

  void _showSignOutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to sign out of your SabayGo account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // The root router watches AuthProvider.status and swaps to
              // the welcome screen on its own -- no manual navigation here.
              context.read<AuthProvider>().signOut();
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD9534F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    final passwordCtrl = TextEditingController();
    String? dialogError;
    bool busy = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This closes your SabayGo account. Your booking history is '
                'kept for the cooperative\'s records, but you will no longer '
                'be able to sign in. Enter your password to confirm.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  errorText: dialogError,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (passwordCtrl.text.isEmpty) return;
                      setDialogState(() {
                        busy = true;
                        dialogError = null;
                      });
                      final message = await _viewModel.closeAccount(passwordCtrl.text);
                      if (message != null) {
                        setDialogState(() {
                          busy = false;
                          dialogError = message;
                        });
                        return;
                      }
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      if (!context.mounted) return;
                      context.read<AuthProvider>().signOut();
                    },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD9534F),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_viewModel.isLoading && _viewModel.currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final user = _viewModel.currentUser;
    if (user == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_viewModel.error ?? 'Could not load your profile.'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _viewModel.load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _viewModel.load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Profile',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF2D2059)),
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildAvatar(user, radius: 32),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              if (user.trustRating != null)
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
                          onPressed: () async {
                            final updated = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(builder: (_) => ChangeNotifierProvider.value(
                                value: _viewModel,
                                child: const EditProfileScreen(),
                              )),
                            );
                            if (updated == true) setState(() {});
                          },
                          icon: const Icon(Icons.edit_square, color: Color(0xFF00A859), size: 24),
                        )
                      ],
                    ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1)),
                    _buildQuickInfo(Icons.phone_outlined, user.phoneNumber ?? 'No phone number'),
                    const SizedBox(height: 10),
                    _buildQuickInfo(Icons.email_outlined, user.email),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Text('ACCOUNT', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
              const SizedBox(height: 12),

              _buildSettingsGroup([
                _buildSettingsTile(Icons.home_work_outlined, 'Home Address', subtitle: user.address ?? 'Not set'),
                _buildSettingsTile(Icons.person_outline, 'Gender', subtitle: user.gender ?? 'Not set'),
                _buildSettingsTile(
                  Icons.health_and_safety_outlined,
                  'Emergency Contact',
                  subtitle: user.emergencyContactName == null
                      ? 'Not set'
                      : '${user.emergencyContactName}${user.emergencyContactRelation != null ? ' (${user.emergencyContactRelation})' : ''}\n${user.emergencyContactPhone ?? ''}',
                  iconColor: Colors.red.shade400,
                ),
              ]),

              const SizedBox(height: 24),
              const Text('PREFERENCES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
              const SizedBox(height: 12),

              _buildSettingsGroup([
                _buildSettingsTile(Icons.bookmark_outline, 'Saved Destinations', onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeNotifierProvider.value(
                    value: _viewModel,
                    child: const ManageDestinationsScreen(),
                  )));
                }),
                _buildSettingsTile(Icons.notifications_none, 'Notification Settings', onTap: () => _showNotificationSettingsSheet(context)),
              ]),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: () => _showSignOutConfirmation(context),
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
                  onPressed: () => _showDeleteAccountDialog(context),
                  icon: const Icon(Icons.person_remove_outlined, size: 20, color: Colors.red),
                  label: const Text('Delete Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(PassengerModel user, {required double radius}) {
    final url = user.avatarUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(url));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF2D2059),
      child: Text(
        user.initials,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: radius * 0.6),
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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
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

  Widget _buildSettingsTile(IconData icon, String title, {String? subtitle, Color? iconColor, VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: (iconColor ?? const Color(0xFF2D2059)).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 20, color: iconColor ?? const Color(0xFF2D2059)),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)) : null,
      trailing: onTap != null ? const Icon(Icons.chevron_right, size: 20, color: Colors.grey) : null,
    );
  }

  void _showNotificationSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
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
                      onChanged: (val) async {
                        await _viewModel.toggleAllNotifications(val);
                        setSheetState(() {});
                      },
                    ),
                    const Divider(height: 16),
                    SwitchListTile(
                      title: const Text('Tailored Trip Schedules', style: TextStyle(fontSize: 14)),
                      subtitle: const Text('Get notified when a van matches your saved destinations.', style: TextStyle(fontSize: 12)),
                      activeColor: const Color(0xFF00A859),
                      contentPadding: EdgeInsets.zero,
                      value: _viewModel.tailoredSchedules,
                      onChanged: (val) async {
                        await _viewModel.toggleSpecificNotification('tailored', val);
                        setSheetState(() {});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Trip Updates & Cancellations', style: TextStyle(fontSize: 14)),
                      activeColor: const Color(0xFF00A859),
                      contentPadding: EdgeInsets.zero,
                      value: _viewModel.tripUpdates,
                      onChanged: (val) async {
                        await _viewModel.toggleSpecificNotification('updates', val);
                        setSheetState(() {});
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
