import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/policy_repository.dart';
import '../../../core/design/components/components.dart';
import '../../../core/design/tokens.dart';
import '../../../viewmodels/auth_provider.dart';
import '../speed_limits_panel.dart';

/// Cooperative-wide settings, as data rather than a redeploy.
///
/// A value edited here governs trips generated from now on -- it never
/// rewrites a trip already booked under the old value, since policy
/// values are snapshotted onto each trip at generation time.
class PolicyEditorScreen extends StatefulWidget {
  const PolicyEditorScreen({super.key});

  @override
  State<PolicyEditorScreen> createState() => _PolicyEditorScreenState();
}

class _PolicyEditorScreenState extends State<PolicyEditorScreen> {
  late final PolicyRepository _policies = context.read<PolicyRepository>();

  List<Policy>? _list;
  bool _loading = true;
  String? _error;
  final Map<String, TextEditingController> _controllers = {};
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _policies.list();
      if (!mounted) return;
      setState(() {
        _list = list;
        for (final p in list) {
          _controllers.putIfAbsent(p.policyKey, () => TextEditingController()).text = p.policyValue;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(Policy policy) async {
    final controller = _controllers[policy.policyKey]!;
    if (controller.text.trim() == policy.policyValue) return;

    setState(() => _saving.add(policy.policyKey));
    try {
      await _policies.update(policy.policyKey, controller.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Saved. New trips use this value; trips already booked keep their terms.'),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(policy.policyKey));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Rules & Settings',
            technicalNote: 'Cooperative policies',
            description: 'A2Z\'s rules for booking, trips, payment, the phones and evidence. A change '
                'is kept with who made it; trips already booked keep the terms they were sold under.',
            actions: [RefreshButton(onPressed: _load, busy: _loading)],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? LoadError(message: _error!, onRetry: _load)
                    : _buildList(),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final policies = _list ?? [];
    // Grouped by what the office is deciding, in the order it comes up.
    final groups = <String, List<Policy>>{};
    for (final p in policies) {
      groups.putIfAbsent(_plain[p.policyKey]?.$2 ?? 'Other', () => []).add(p);
    }
    final order = [..._groupOrder.where(groups.containsKey), ...groups.keys.where((g) => !_groupOrder.contains(g))];
    final manager = context.read<AuthProvider>().profile?.role.isManager ?? false;
    return ListView.separated(
      itemCount: order.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
      itemBuilder: (context, i) => i == order.length
          ? SpeedLimitsPanel(canEdit: manager)
          : Panel(
        title: order[i],
        child: Column(
          children: [
            for (final (j, policy) in groups[order[i]]!.indexed) ...[
              if (j > 0) const Divider(),
              _policyRow(policy),
            ],
          ],
        ),
      ),
    );
  }

  Widget _policyRow(Policy policy) {
    final text = Theme.of(context).textTheme;
    final controller = _controllers[policy.policyKey]!;
    final saving = _saving.contains(policy.policyKey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_plain[policy.policyKey]?.$1 ?? _humanise(policy.policyKey),
                    style: text.titleSmall),
                const SizedBox(height: 2),
                Text(policy.description, style: text.bodySmall),
                const SizedBox(height: 2),
                // The stored name, for whoever maintains the system, and who
                // set the value in force.
                Text(
                    '${policy.policyKey}${policy.updatedBy != null ? ' · set by ${policy.updatedBy}' : ''}',
                    style: text.bodySmall!.copyWith(fontSize: 11, color: AppColors.textMuted)),
                if (policy.policyValue.isEmpty)
                  Text('Not set: this is off until A2Z decides a value.',
                      style: text.bodySmall!.copyWith(color: AppColors.warning)),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          SizedBox(
            width: 180,
            child: TextField(
              controller: controller,
              onSubmitted: (_) => _save(policy),
              decoration: InputDecoration(
                hintText: 'Not set',
                suffixText: _unit(policy.policyKey),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Earlier values',
            onPressed: () => _history(policy),
            icon: Icon(Icons.history, color: AppColors.textMuted),
          ),
          SizedBox(
            width: 88,
            child: saving
                ? const Center(
                    child: SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : OutlinedButton(onPressed: () => _save(policy), child: const Text('Save')),
          ),
        ],
      ),
    );
  }

  Future<void> _history(Policy policy) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_plain[policy.policyKey]?.$1 ?? _humanise(policy.policyKey)),
          content: SizedBox(
            width: 460,
            height: 320,
            child: FutureBuilder(
              future: _policies.history(policy.policyKey),
              builder: (_, snap) {
                if (snap.hasError) {
                  final e = snap.error;
                  return Text(e is ApiException ? e.message : '$e');
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final when = DateFormat('d MMM yyyy, h:mm a');
                return ListView(children: [
                  for (final (i, p) in snap.data!.indexed)
                    ListTile(
                      dense: true,
                      title: Text(p.policyValue.isEmpty ? 'Not set' : '${p.policyValue} ${_unit(p.policyKey) ?? ''}'),
                      subtitle: Text('${i == 0 ? 'In force since' : 'From'} '
                          '${when.format(p.effectiveFrom ?? p.updatedAt)} · ${p.updatedBy ?? 'set at installation'}'),
                    ),
                ]);
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );

  static const _groupOrder = [
    'Booking and changes',
    'At the terminal',
    'Trips and payment',
    'Departure and home pickup',
    'Phones and camera',
    'Driving flags',
    'Evidence and privacy',
    'Vans and tracking',
    'Safety',
    'Other',
  ];

  /// Plain title and group per stored key. A key not listed here still
  /// shows, under "Other", with its name made readable.
  static const _plain = <String, (String, String)>{
    'advance_booking_open_days': ('How far ahead passengers can book', 'Booking and changes'),
    'advance_booking_seat_cap': ('Seats that can be booked in advance', 'Booking and changes'),
    'seat_hold_ttl_seconds': ('How long an unpaid seat is held', 'Booking and changes'),
    'hold_sweep_interval_seconds': ('How often unpaid holds are released', 'Booking and changes'),
    'cancel_cutoff_hours': ('Cancellation deadline before departure', 'Booking and changes'),
    'reschedule_cutoff_hours': ('Trip-change deadline before departure', 'Booking and changes'),
    'max_reschedules_per_booking': ('Times a passenger may change trips', 'Booking and changes'),
    'refund_enabled': ('Refunds allowed', 'Booking and changes'),
    'checkin_window_minutes': ('When check-in opens', 'At the terminal'),
    'default_geofence_radius_m': ('Size of a terminal area (radius)', 'At the terminal'),
    'walkin_info_required': ('Walk-in passengers must give details', 'At the terminal'),
    'default_seat_capacity': ('Seats in a new van', 'Vans and tracking'),
    'tracking_ping_interval_seconds': ('How often a van sends its location', 'Vans and tracking'),
    'tracking_stale_after_seconds': ('Show "No signal" after', 'Vans and tracking'),
    'licence_expiry_warning_days': ('Warn before an operator\'s licence expires', 'Vans and tracking'),
    'variance_alert_threshold': ('Alert when the camera count is off by', 'Other'),
    'sos_contact_numbers': ('Numbers texted on an emergency (SOS)', 'Safety'),
    'start_opens_minutes': ('When Start opens before departure', 'Trips and payment'),
    'remittance_rate_pct': ('A2Z\'s share of each van\'s fares', 'Trips and payment'),
    'depart_zone_radius_m': ('Terminal zone for a GPS departure (radius)', 'Departure and home pickup'),
    'depart_readings': ('Readings outside the zone that make a departure', 'Departure and home pickup'),
    'home_pickup_wait_minutes': ('How long the van waits at a home pickup', 'Departure and home pickup'),
    'home_pickup_max_route_m': ('Farthest a home pickup may be from the route', 'Departure and home pickup'),
    'heartbeat_gap_seconds': ('A phone is silent after', 'Phones and camera'),
    'match_window_seconds': ('A boarding matches a scan or cash entry within', 'Phones and camera'),
    'overspeed_seconds': ('Above the limit this long is overspeed', 'Driving flags'),
    'stop_seconds': ('Standing still longer than this is an unscheduled stop', 'Driving flags'),
    'slow_tolerance_pct': ('A stretch is slow beyond its expected time by', 'Driving flags'),
    'expected_speed_kmh': ('Average speed behind each stretch\'s expected time', 'Driving flags'),
    'standstill_kmh': ('At or below this speed the van is standing still', 'Driving flags'),
    'retention_days': ('Days blurred stills and GPS logs are kept', 'Evidence and privacy'),
    'chat_image_max_kb': ('Largest payment screenshot accepted', 'Evidence and privacy'),
    'chat_image_retention_days': ('Days payment screenshots are kept', 'Evidence and privacy'),
  };

  /// The unit is part of the stored name (`_hours`, `_days`...), so it is
  /// read from there rather than guessed per key.
  static String? _unit(String key) {
    for (final (suffix, unit) in const [
      ('_pct', '%'),
      ('_kmh', 'km/h'),
      ('_kb', 'KB'),
      ('_readings', 'readings'),
      ('_days', 'days'),
      ('_hours', 'hours'),
      ('_minutes', 'minutes'),
      ('_seconds', 'seconds'),
      ('_m', 'metres'),
    ]) {
      if (key.endsWith(suffix)) return unit;
    }
    return null;
  }

  static String _humanise(String key) {
    final words = key.replaceAll('_', ' ');
    return words.isEmpty ? key : words[0].toUpperCase() + words.substring(1);
  }
}
