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
///
/// Said in A2Z's words (UI redesign v3): each setting's title, what it
/// does and what "not set" means come from [_plain]; the stored name and
/// the database's own description stay with the code and the manuscript.
/// A yes/no setting is a switch. Settings only the development team tunes
/// sit folded under Advanced. Each row still saves on its own, and its
/// Save appears once its value has changed.
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
  bool _advanced = false;

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
    if (!_changed(policy)) return;

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
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            compact: true,
            title: 'Rules & Settings',
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
    );
  }

  bool _changed(Policy p) => _controllers[p.policyKey]!.text.trim() != p.policyValue;

  Widget _buildList() {
    final policies = _list ?? [];
    // Grouped by what the office is deciding, in the order it comes up. A
    // setting the console has no words for goes under Advanced.
    final groups = <String, List<Policy>>{};
    for (final p in policies) {
      groups.putIfAbsent(_plain[p.policyKey]?.group ?? _advancedGroup, () => []).add(p);
    }
    final order = [for (final g in _groupOrder) if (groups.containsKey(g)) g];
    final advanced = groups[_advancedGroup] ?? const <Policy>[];
    final manager = context.read<AuthProvider>().profile?.role.isManager ?? false;
    final text = Theme.of(context).textTheme;
    Widget rows(List<Policy> list) => Column(children: [
          for (final (j, policy) in list.indexed) ...[
            if (j > 0) const Divider(),
            _policyRow(policy),
          ],
        ]);
    return ListView(
      children: [
        for (final g in order) ...[
          Panel(title: g, child: rows(groups[g]!)),
          const SizedBox(height: AppSpacing.lg),
        ],
        SpeedLimitsPanel(canEdit: manager),
        if (advanced.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Panel(
            title: _advancedGroup,
            trailing: TextButton(
              onPressed: () => setState(() => _advanced = !_advanced),
              child: Text(_advanced ? 'Hide' : 'Show ${advanced.length}'),
            ),
            child: _advanced
                ? rows(advanced)
                : Text('How often the system works through its own jobs. The development team sets '
                    'these; A2Z does not need to change them.', style: text.bodySmall),
          ),
        ],
      ],
    );
  }

  Widget _policyRow(Policy policy) {
    final text = Theme.of(context).textTheme;
    final controller = _controllers[policy.policyKey]!;
    final saving = _saving.contains(policy.policyKey);
    final words = _plain[policy.policyKey];
    final title = words?.title ?? _humanise(policy.policyKey);
    final yesNo = policy.dataType == 'bool';
    // A list of phone numbers needs the room a number does not.
    final wide = policy.dataType == 'string';
    final Widget field = yesNo
        ? Align(
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(
                value: controller.text.trim().toLowerCase() == 'true',
                onChanged: (on) => setState(() => controller.text = on ? 'true' : 'false'),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(controller.text.trim().toLowerCase() == 'true' ? 'Yes' : 'No', style: text.bodyMedium),
            ]),
          )
        : TextField(
            controller: controller,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(policy),
            minLines: 1,
            maxLines: wide ? 3 : 1,
            // Named by the row's Semantics (its title), not a label in the
            // box: an empty box says "Not set".
            decoration: InputDecoration(
              hintText: 'Not set',
              suffixText: _unit(policy.policyKey),
            ),
          );
    return Semantics(
      container: true,
      label: title,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(words?.says ?? policy.description, style: text.bodySmall),
                  if (policy.policyValue.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Not set: ${words?.unset ?? 'this is off until A2Z decides a value.'}',
                          style: text.bodySmall!.copyWith(color: AppColors.warning)),
                    ),
                  // Who set the value in force (every decision is
                  // attributable).
                  if (policy.updatedBy != null)
                    Text('Set by ${policy.updatedBy}', style: text.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            SizedBox(width: wide ? 300 : 180, child: field),
            IconButton(
              tooltip: 'Earlier values of "$title"',
              onPressed: () => _history(policy),
              icon: Icon(Icons.history, color: AppColors.textMuted),
            ),
            // The slot is kept, so the fields stay in one column; Save shows
            // only once the value differs from the one in force.
            SizedBox(
              width: 88,
              child: saving
                  ? const Center(
                      child: SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : _changed(policy)
                      ? OutlinedButton(onPressed: () => _save(policy), child: const Text('Save'))
                      : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _history(Policy policy) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_plain[policy.policyKey]?.title ?? _humanise(policy.policyKey)),
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
                      title: Text(p.policyValue.isEmpty
                          ? 'Not set'
                          : p.dataType == 'bool'
                              ? (p.policyValue.trim().toLowerCase() == 'true' ? 'Yes' : 'No')
                              : '${p.policyValue} ${_unit(p.policyKey) ?? ''}'),
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

  static const _advancedGroup = 'Advanced';

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
  ];

  /// Per stored key: the title, its group, what it does and what "not set"
  /// means, in the office's words. A key not listed here still shows, under
  /// Advanced, with its name made readable.
  static const _plain = <String, _Words>{
    'advance_booking_open_days': _Words('How far ahead passengers can book', 'Booking and changes',
        'How many days ahead the app lets a passenger book a space.'),
    'advance_booking_seat_cap': _Words('Spaces that can be booked ahead', 'Booking and changes',
        'How many of a van\'s spaces the app may sell in advance. Set it to the van\'s spaces to open them all.'),
    'unpaid_cutoff_min': _Words('Release unpaid reservations before departure', 'Booking and changes',
        'A reservation the Dispatcher has not marked Paid this long before departure is cancelled and its '
            'space freed. The passenger is reminded one cutoff-length earlier.'),
    'checkin_window_minutes': _Words('When check-in opens', 'At the terminal',
        'How long before departure a passenger at the terminal can check in from the app.'),
    'default_geofence_radius_m': _Words('Size of a terminal area', 'At the terminal',
        'How far from a terminal\'s position still counts as at the terminal, unless the terminal sets its own.'),
    'walkin_info_required': _Words('Walk-in passengers must give details', 'At the terminal',
        'No: the Dispatcher may leave a walk-in passenger\'s name out. The details are only for the receipt.'),
    'default_seat_capacity': _Words('Spaces in a new van', 'Vans and tracking',
        'The spaces a van is given when it is added. A2Z\'s rule is 14.'),
    'tracking_ping_interval_seconds': _Words('How often a van sends its position', _advancedGroup,
        'How often the phone in the van should report where it is.'),
    'tracking_stale_after_seconds': _Words('Show "No signal" after', 'Vans and tracking',
        'A van with no new position for this long shows "No signal", at its last known place.'),
    'licence_expiry_warning_days': _Words('Warn before an operator\'s licence expires', 'Vans and tracking',
        'How many days before an operator\'s licence expires the office is told.'),
    'sos_contact_numbers': _Words('Numbers texted on an emergency (SOS)', 'Safety',
        'Mobile numbers texted when crew or a passenger presses SOS. Separate them with commas, starting '
            'with +63, e.g. +639171234567.',
        unset: 'an SOS is recorded on Emergencies, but nobody is texted.'),
    'start_opens_minutes': _Words('When Start opens', 'Trips and payment',
        'How long before departure the Start button appears on a trip.'),
    'remittance_rate_pct': _Words('A2Z\'s share of the fares', 'Trips and payment',
        'The part of the fares on each trip\'s passenger list that is handed to the Cashier before Start.'),
    'dcott_ticket_fee': _Words('DCOTT ticket per trip', 'Trips and payment',
        'Owed for every trip once it has a van, even with nobody on the list. Part of the terminal fees '
            'Start waits for.'),
    'parking_fee': _Words('Parking per van per day', 'Trips and payment',
        'Charged once a day on each van\'s statement, including a van with no trip. Part of the terminal '
            'fees Start waits for.'),
    'depart_zone_radius_m': _Words('Terminal zone for a GPS departure', 'Departure and home pickup',
        'The area around the terminal that holds the queue and loading bay. A van that leaves it has departed.',
        unset: 'a departure is tapped by the Dispatcher or the office, never read from GPS.'),
    'depart_readings': _Words('Readings that make a GPS departure', 'Departure and home pickup',
        'How many position readings in a row, outside the terminal zone and moving, count as a departure.',
        unset: 'a departure is tapped by the Dispatcher or the office, never read from GPS.'),
    'home_pickup_wait_minutes': _Words('How long the van waits at a home pickup', 'Departure and home pickup',
        'The longest the van waits at a home-pickup pin.'),
    'home_pickup_max_route_m': _Words('Farthest a home pickup may be from the route', 'Departure and home pickup',
        'How far from the route a home-pickup pin may be.',
        unset: 'home pickup is not offered.'),
    'heartbeat_gap_seconds': _Words('A phone is silent after', 'Phones and camera',
        'A phone in a van that sends no report for this long is silent, and its trip may go Unaudited.'),
    'overspeed_seconds': _Words('Above the limit this long is overspeed', 'Driving flags',
        'How long a van must stay above a stretch\'s speed limit before it is flagged.'),
    'stop_seconds': _Words('An unscheduled stop is longer than', 'Driving flags',
        'A van standing still away from every stop for longer than this is flagged. A shorter stop is '
            'recorded, not flagged.'),
    'slow_tolerance_pct': _Words('A slow stretch is over its expected time by', 'Driving flags',
        'A stretch that takes this much longer than expected, less any home-pickup wait, is flagged as slow.'),
    'expected_speed_kmh': _Words('Speed behind each stretch\'s expected time', 'Driving flags',
        'The average speed that gives a stretch its expected time when the stretch is saved.'),
    'standstill_kmh': _Words('Standing still is at or below', _advancedGroup,
        'At or below this speed the van counts as standing still.'),
    'special_trip_speed_kmh': _Words('Speed limit on a special trip', 'Driving flags',
        'A special trip has no route of its own, so this limit applies to it.',
        unset: 'special trips are not flagged for overspeed.'),
    'retention_days': _Words('Days blurred stills and GPS logs are kept', 'Evidence and privacy',
        'After this many days the blurred stills and GPS readings are deleted, except those still under '
            'review or in a dispute.',
        unset: 'everything is kept.'),
    'chat_image_max_kb': _Words('Largest chat picture accepted', _advancedGroup,
        'The largest picture a passenger may send in a chat message.'),
    'chat_image_retention_days': _Words('Days chat pictures are kept', 'Evidence and privacy',
        'Pictures sent in chat are deleted after this many days.'),
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
      ('_min', 'minutes'),
      ('_fee', 'pesos'),
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

/// A setting in the office's words.
class _Words {
  const _Words(this.title, this.group, this.says, {this.unset});
  final String title;
  final String group;

  /// What it does, in one sentence.
  final String says;

  /// What "not set" means, when it means something particular.
  final String? unset;
}
