import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/section_header.dart';
import '../../core/design/tokens.dart';
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
        title: const Text('Sign out?'),
        content: const Text('You can sign in again at any time with your email and password.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              // The root router watches AuthProvider.status and swaps to
              // the welcome screen on its own -- no manual navigation here.
              context.read<AuthProvider>().signOut();
            },
            child: const Text('Sign out'),
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
          title: const Text('Delete your account?'),
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
                  errorText: dialogError,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
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
                  backgroundColor: AppColors.danger, foregroundColor: AppColors.onFill),
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surfaceRaised),
                    )
                  : const Text('Delete account'),
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

    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _viewModel.load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The app bar already says Profile; the screen opens on the person.
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: AppColors.edge),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildAvatar(user, radius: 32),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(child: Text(user.fullName, style: text.titleLarge)),
                        IconButton(
                          tooltip: 'Edit profile',
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
                          icon: const Icon(Icons.edit_outlined, color: AppColors.primary),
                        )
                      ],
                    ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.lg), child: Divider(height: 1)),
                    _buildQuickInfo(Icons.phone_outlined, user.phoneNumber ?? 'No phone number'),
                    const SizedBox(height: AppSpacing.sm),
                    _buildQuickInfo(Icons.email_outlined, user.email),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),
              const AppSectionHeader('Account'),
              const SizedBox(height: AppSpacing.md),

              _buildSettingsGroup([
                _buildSettingsTile(Icons.home_work_outlined, 'Home address', subtitle: user.address ?? 'Not set'),
                _buildSettingsTile(Icons.person_outline, 'Gender', subtitle: _sentence(user.gender) ?? 'Not set'),
                _buildSettingsTile(
                  Icons.health_and_safety_outlined,
                  'Emergency contact',
                  subtitle: user.emergencyContactName == null
                      ? 'Not set'
                      : '${user.emergencyContactName}${user.emergencyContactRelation != null ? ' (${user.emergencyContactRelation})' : ''}\n${user.emergencyContactPhone ?? ''}',
                ),
              ]),

              const SizedBox(height: AppSpacing.xxl),
              const AppSectionHeader('Preferences'),
              const SizedBox(height: AppSpacing.md),

              _buildSettingsGroup([
                _buildSettingsTile(Icons.bookmark_outline, 'Saved destinations', onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeNotifierProvider.value(
                    value: _viewModel,
                    child: const ManageDestinationsScreen(),
                  )));
                }),
                _buildSettingsTile(Icons.notifications_none, 'Notification settings', onTap: () => _showNotificationSettingsSheet(context)),
              ]),

              const SizedBox(height: AppSpacing.xxxl),

              SizedBox(
                width: double.infinity,
                height: AppSizing.primaryActionHeight,
                child: OutlinedButton.icon(
                  onPressed: () => _showSignOutConfirmation(context),
                  icon: const Icon(Icons.logout, size: 20),
                  label: const Text('Sign out'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                height: AppSizing.primaryActionHeight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () => _showDeleteAccountDialog(context),
                  icon: const Icon(Icons.person_remove_outlined, size: 20),
                  label: const Text('Delete account'),
                ),
              ),
              const SizedBox(height: AppSpacing.xxxl),
            ],
          ),
        ),
      ),
    );
  }

  /// Stored values are lower case ('female'); the screen says them as words.
  static String? _sentence(String? v) =>
      v == null || v.isEmpty ? null : v[0].toUpperCase() + v.substring(1);

  Widget _buildAvatar(PassengerModel user, {required double radius}) {
    final url = user.avatarUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(url));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primaryContainer,
      child: Text(
        user.initials,
        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: radius * 0.6),
      ),
    );
  }

  Widget _buildQuickInfo(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textMuted),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
        ),
      ],
    );
  }

  Widget _buildSettingsGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.edge),
      ),
      child: Column(
        children: [
          for (final (i, child) in children.indexed) ...[
            child,
            if (i != children.length - 1) const Divider(height: 1, indent: 64),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsTile(IconData icon, String title, {String? subtitle, VoidCallback? onTap}) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Icon(icon, size: 20, color: AppColors.primary),
      ),
      title: Text(title, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: subtitle != null ? Text(subtitle, style: text.bodySmall) : null,
      trailing: onTap != null ? const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted) : null,
    );
  }

  void _showNotificationSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceRaised,
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
                      child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 16), decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2))),
                    ),
                    Text('Notification settings', style: Theme.of(sheetContext).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      title: const Text('Allow notifications'),
                      contentPadding: EdgeInsets.zero,
                      value: _viewModel.pushEnabled,
                      onChanged: (val) async {
                        await _viewModel.toggleAllNotifications(val);
                        setSheetState(() {});
                      },
                    ),
                    const Divider(height: 16),
                    SwitchListTile(
                      title: const Text('Departures to my saved destinations'),
                      subtitle: const Text('A message when a van runs to a destination you saved.'),
                      contentPadding: EdgeInsets.zero,
                      value: _viewModel.tailoredSchedules,
                      onChanged: (val) async {
                        await _viewModel.toggleSpecificNotification('tailored', val);
                        setSheetState(() {});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Changes to my trips'),
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
