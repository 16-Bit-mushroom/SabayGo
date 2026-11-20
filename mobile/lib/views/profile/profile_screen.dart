import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/dialog_buttons.dart';
import '../../core/design/components/section_header.dart';
import '../../core/design/components/status_chip.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/util/when.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/special_trip_repository.dart';
import '../../models/passenger_moderl.dart';
import '../../viewmodels/auth_provider.dart';
import '../../viewmodels/profile_viewmodel.dart';
import '../special_trips/special_trips_screen.dart';
import 'edit_profile_screen.dart';
import 'manage_destinations_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileViewModel _viewModel;
  late final SpecialTripRepository _rentalsRepo;

  /// The passenger's van rentals, shown on Profile so they are seen without
  /// first opening Rent a van (20 Nov, the owner). Null while loading.
  List<SpecialTripRequest>? _rentals;
  bool _rentalsFailed = false;

  @override
  void initState() {
    super.initState();
    _viewModel = ProfileViewModel(ProfileRepository(context.read<ApiClient>()));
    _rentalsRepo = SpecialTripRepository(context.read<ApiClient>());
    _viewModel.addListener(_onStateChanged);
    _viewModel.load();
    _loadRentals();
  }

  Future<void> _loadRentals() async {
    try {
      final list = await _rentalsRepo.mine();
      if (mounted) {
        setState(() {
          _rentals = list;
          _rentalsFailed = false;
        });
      }
    } on ApiException {
      if (mounted) setState(() => _rentalsFailed = true);
    }
  }

  Future<void> _refresh() => Future.wait([_viewModel.load(), _loadRentals()]);

  Future<void> _openRentals() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SpecialTripsScreen()));
    _loadRentals();
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
          DialogButtons(
            action: 'Sign out',
            onAction: () {
              Navigator.pop(dialogContext);
              // The root router watches AuthProvider.status and swaps to
              // the welcome screen on its own -- no manual navigation here.
              context.read<AuthProvider>().signOut();
            },
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
            DialogButtons(
              action: 'Delete account',
              danger: true,
              busy: busy,
              onAction: () async {
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
        onRefresh: _refresh,
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
                      ],
                    ),
                    const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.lg), child: Divider(height: 1)),
                    _buildQuickInfo(Icons.phone_outlined, user.phoneNumber ?? 'No phone number'),
                    const SizedBox(height: AppSpacing.sm),
                    _buildQuickInfo(Icons.email_outlined, user.email),
                    const SizedBox(height: AppSpacing.lg),
                    // A labelled button, not a pencil icon (20 Nov redesign):
                    // the way to change the details is said in words.
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
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
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit profile'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xxl),
              const AppSectionHeader('Rented vans'),
              const SizedBox(height: AppSpacing.md),
              _rentalsGroup(),

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
                _buildSettingsTile(Icons.bookmark_outline, 'Saved destinations',
                    subtitle: 'Hear when a van runs to a place you saved.', onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ChangeNotifierProvider.value(
                    value: _viewModel,
                    child: const ManageDestinationsScreen(),
                  )));
                }),
              ]),

              const SizedBox(height: AppSpacing.xxl),
              const AppSectionHeader('Notifications'),
              const SizedBox(height: AppSpacing.md),
              // On the page, not behind a "Notification settings" row that
              // opened a sheet (20 Nov redesign): a switch is found where it
              // is seen.
              _buildSettingsGroup([
                _switch('Allow notifications', null, _viewModel.pushEnabled,
                    (v) => _viewModel.toggleAllNotifications(v)),
                _switch('Departures to my saved destinations', 'A message when a van runs to a destination you saved.',
                    _viewModel.tailoredSchedules, (v) => _viewModel.toggleSpecificNotification('tailored', v)),
                _switch('Changes to my trips', null, _viewModel.tripUpdates,
                    (v) => _viewModel.toggleSpecificNotification('updates', v)),
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

  /// The latest three rentals with their state, then the way in. With none
  /// yet, one row that says what renting a van is.
  Widget _rentalsGroup() {
    final text = Theme.of(context).textTheme;
    final list = _rentals;
    if (list == null) {
      return _buildSettingsGroup([
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 2),
          leading: _rentalsFailed
              ? const Icon(Icons.cloud_off, color: AppColors.textMuted)
              : const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          title: Text(
            _rentalsFailed ? 'Could not load your van rentals. Pull down to try again.' : 'Loading your van rentals…',
            style: text.bodyMedium,
          ),
        ),
      ]);
    }
    if (list.isEmpty) {
      return _buildSettingsGroup([
        _buildSettingsTile(Icons.airport_shuttle_outlined, 'Rent a van',
            subtitle: 'A van and driver for your group, up to 14 people.', onTap: _openRentals),
      ]);
    }
    final latest = [...list]..sort((a, b) => b.pickupAt.compareTo(a.pickupAt));
    return _buildSettingsGroup([
      for (final r in latest.take(3)) _rentalTile(r),
      _buildSettingsTile(Icons.add, list.length > 3 ? 'See all ${list.length} and request a van' : 'Request another van',
          onTap: _openRentals),
    ]);
  }

  Widget _rentalTile(SpecialTripRequest r) {
    final text = Theme.of(context).textTheme;
    final (label, tone) = rentalStatus(r);
    return ListTile(
      onTap: _openRentals,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      leading: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: const Icon(Icons.airport_shuttle_outlined, size: 20, color: AppColors.primary),
      ),
      title: Text('${r.pickupAddress} → ${r.destinationAddress}',
          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusChip(label, tone: tone),
            Text(dayAndTime(r.pickupAt), style: text.bodySmall),
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
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

  /// A Material, not a decorated box: list tiles draw their ink on it
  /// (ListTile asserts one is there).
  Widget _buildSettingsGroup(List<Widget> children) {
    return Material(
      color: AppColors.surfaceRaised,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.edge),
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

  Widget _switch(String title, String? subtitle, bool value, Future<void> Function(bool) onChanged) {
    final text = Theme.of(context).textTheme;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 2),
      title: Text(title, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle, style: text.bodySmall),
      value: value,
      onChanged: (v) async {
        await onChanged(v);
        if (mounted) setState(() {});
      },
    );
  }
}
