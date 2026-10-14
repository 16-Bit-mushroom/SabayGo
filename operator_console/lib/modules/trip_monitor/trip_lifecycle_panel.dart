import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/fleet_repository.dart';
import '../../viewmodels/auth_provider.dart';

/// Assignment, start, departure and the Terminal Manager's changes for one
/// trip (rev 468, change brief 4.2).
///
/// The rules are the server's: this panel offers what the signed-in role
/// may do at this point in the trip and says why a button is off, so a
/// refusal is rare and, when it comes, is the server's own sentence. The
/// office assigns, starts and departs; only the Terminal Manager reviews
/// an automatic start, changes a started trip's van or voids a trip.
class TripLifecyclePanel extends StatelessWidget {
  const TripLifecyclePanel({super.key, required this.trip, required this.onChanged});

  final TripBoardEntry trip;
  final VoidCallback onChanged;

  static final _time = DateFormat.jm();

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final manager = context.read<AuthProvider>().profile?.role.isManager ?? false;
    final text = Theme.of(context).textTheme;
    final scheduled = t.status == 'scheduled';
    final started = const {'boarding', 'departed', 'completed'}.contains(t.status);
    final windowOpen = !DateTime.now().isBefore(t.startOpensAt);

    final facts = <(IconData, String, Color?)>[
      if (t.assignedByName != null)
        (Icons.how_to_reg_outlined, 'Van and Dispatcher assigned by ${t.assignedByName}', null)
      else if (scheduled)
        (Icons.hourglass_empty, 'Not assigned yet. Assign the van and the Dispatcher at the van\'s turn.',
            AppColors.warning),
      if (t.startMode == 'manual')
        (Icons.play_circle_outline,
            'Started by ${t.startedByName ?? 'the office'} at ${_time.format(t.startedAt!)}', null)
      else if (t.startMode != null)
        (Icons.smart_toy_outlined,
            'Started by the system at ${_time.format(t.startedAt!)}: nobody started it in time'
                '${t.dispatcherId == null ? ' · No Dispatcher' : ''}',
            t.awaitsReview ? AppColors.warning : null),
      if (t.awaitsReview)
        (Icons.rule, 'Waiting for the Terminal Manager\'s review. Left off the daily statement until then.',
            AppColors.warning)
      else if (t.startReviewStatus == 'reviewed')
        (Icons.task_alt, 'Automatic start reviewed', null),
      if (t.auditStatus == 'unaudited')
        (Icons.videocam_off_outlined, 'Unaudited: ${_unaudited(t.unauditedReason)}. The camera cannot '
            'check this trip; only QR tickets and logged fares count.', AppColors.danger),
      if (t.departureSource == 'detected')
        (Icons.gps_fixed, 'Departure detected: the van\'s GPS left the terminal', null)
      else if (t.departureSource == 'confirmed')
        (Icons.logout, 'Departure confirmed by the office', null),
      if (t.changeNote != null) (Icons.edit_note, t.changeNote!, null),
    ];

    final actions = <Widget>[
      if (scheduled) ...[
        OutlinedButton.icon(
          onPressed: () => _assign(context),
          icon: const Icon(Icons.assignment_ind_outlined, size: 18),
          label: Text(t.isAssigned ? 'Change assignment' : 'Assign van and Dispatcher'),
        ),
        Tooltip(
          message: !t.isAssigned
              ? 'Assign a van and a Dispatcher first'
              : windowOpen
                  ? 'Start the trip with ${t.plateNumber}'
                  : 'Start opens at ${_time.format(t.startOpensAt)}',
          child: FilledButton.icon(
            onPressed: t.isAssigned && windowOpen ? () => _start(context) : null,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Start trip'),
          ),
        ),
      ],
      if (t.status == 'boarding')
        FilledButton.icon(
          onPressed: () => _depart(context),
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Depart'),
        ),
      if (manager && t.awaitsReview)
        FilledButton.tonalIcon(
          onPressed: () => _review(context),
          icon: const Icon(Icons.rule, size: 18),
          label: const Text('Review start'),
        ),
      if (manager && started)
        OutlinedButton.icon(
          onPressed: () => _changeVan(context),
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: const Text('Change van'),
        ),
      if (manager && (scheduled || t.status == 'boarding'))
        OutlinedButton.icon(
          onPressed: () => _void(context),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          icon: const Icon(Icons.block, size: 18),
          label: const Text('Void trip'),
        ),
    ];

    return Panel(
      title: 'Start and departure',
      icon: Icons.flag_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scheduled && t.isAssigned && !windowOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text('Start opens at ${_time.format(t.startOpensAt)}. The Dispatcher can scan '
                  'tickets and log fares before then.', style: text.bodySmall),
            ),
          for (final (icon, line, colour) in facts)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 16, color: colour ?? AppColors.textMuted),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(line, style: text.bodySmall?.copyWith(color: colour))),
                ],
              ),
            ),
          if (facts.isEmpty && actions.isEmpty)
            Text('Nothing to do on this trip.', style: text.bodySmall),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: actions),
          ],
        ],
      ),
    );
  }

  static String _unaudited(String? reason) => switch (reason) {
        'no_phone' => 'no phone was out with the van',
        'silent_at_start' => 'the phone was silent at the start',
        'lost_en_route' => 'the phone went silent on the road',
        'lens_blocked' => 'the camera was covered',
        _ => 'no camera evidence',
      };

  // ------------------------------------------------------------ actions
  /// Runs one call, reports the result through the app-wide messenger and
  /// refreshes the board. A refusal is shown in the server's own words.
  Future<bool> _run(BuildContext context, Future<void> Function() call, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await call();
      messenger.showSnackBar(SnackBar(content: Text(done), behavior: SnackBarBehavior.floating));
      onChanged();
      return true;
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
      ));
      return false;
    }
  }

  Future<void> _assign(BuildContext context) async {
    final dispatch = context.read<DispatchRepository>();
    final picked = await showDialog<(String?, String?)>(
      context: context,
      builder: (_) => _AssignDialog(vanId: trip.vanId, dispatcherId: trip.dispatcherId),
    );
    if (picked == null || !context.mounted) return;
    await _run(context, () => dispatch.assign(trip.tripId, vanId: picked.$1, dispatcherId: picked.$2),
        'Assignment saved.');
  }

  Future<void> _start(BuildContext context) async {
    final dispatch = context.read<DispatchRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start this trip?'),
        content: Text(
          '${trip.plateNumber}, driven by ${trip.operatorName ?? 'its operator'}, with '
          '${trip.dispatcherName ?? 'the assigned Dispatcher'}. Starting copies the operator\'s '
          'name and licence and the plate onto the trip. Check the plate against the van.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start trip')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    var warnings = const <String>[];
    final started = await _run(context, () async {
      warnings = await dispatch.start(trip.tripId);
    }, 'Trip started.');
    if (!started || warnings.isEmpty || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: AppColors.warning),
        title: const Text('Started, with warnings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final w in warnings) Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text('• $w'),
          )],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _depart(BuildContext context) async {
    final dispatch = context.read<DispatchRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Depart now?'),
        content: const Text('Boarding closes. Paid passengers who were not scanned aboard become '
            'no-shows and their space is released. No refund is issued.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Depart')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, () => dispatch.depart(trip.tripId), 'Trip departed.');
  }

  Future<void> _review(BuildContext context) async {
    final dispatch = context.read<DispatchRepository>();
    final picked = await showDialog<(String?, String)>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: 'Review the automatic start',
        intro: 'The system started this trip because nobody did. Confirm its van, or pick the '
            'van that really ran it. A changed van needs a reason.',
        confirmLabel: 'Mark reviewed',
        vanId: trip.vanId,
        reasonRequiredIfVanChanges: true,
      ),
    );
    if (picked == null || !context.mounted) return;
    final changed = picked.$1 != trip.vanId;
    await _run(
      context,
      () => dispatch.reviewStart(trip.tripId,
          vanId: changed ? picked.$1 : null, note: changed ? picked.$2 : null),
      'Start reviewed.',
    );
  }

  Future<void> _changeVan(BuildContext context) async {
    final dispatch = context.read<DispatchRepository>();
    final picked = await showDialog<(String?, String)>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: 'Change the van',
        intro: 'The earlier van and operator are kept in the trip\'s record with your reason.',
        confirmLabel: 'Change van',
        vanId: trip.vanId,
        reasonRequired: true,
      ),
    );
    if (picked == null || picked.$1 == null || !context.mounted) return;
    await _run(context, () => dispatch.changeVan(trip.tripId, vanId: picked.$1!, reason: picked.$2),
        'Van changed.');
  }

  Future<void> _void(BuildContext context) async {
    final dispatch = context.read<DispatchRepository>();
    final picked = await showDialog<(String?, String)>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Void this trip?',
        intro: 'The trip is cancelled and kept on record with your reason. Passengers holding '
            'tickets are told to see the terminal office. This cannot be undone.',
        confirmLabel: 'Void trip',
        reasonRequired: true,
        danger: true,
      ),
    );
    if (picked == null || !context.mounted) return;
    await _run(context, () => dispatch.voidTrip(trip.tripId, reason: picked.$2), 'Trip voided.');
  }
}

// ---------------------------------------------------------------- pickers
/// Only validated, active vans and Dispatchers can be picked (brief 4.2
/// rule 6); the server checks again, including the operator's record.
Future<(List<Van>, List<StaffMember>)> _roster(FleetRepository fleet) async {
  final results = await Future.wait([fleet.listVans(), fleet.listCrew(role: 'dispatcher')]);
  final vans = (results[0] as List<Van>)
      .where((v) => v.validationStatus == 'validated' && v.operationalStatus == 'active')
      .toList();
  final crew = (results[1] as List<StaffMember>)
      .where((s) => s.validationStatus == 'validated' && s.employmentStatus == 'active')
      .toList();
  return (vans, crew);
}

String _vanLabel(Van v) => v.operatorName == null ? v.plateNumber : '${v.plateNumber} · ${v.operatorName}';

class _AssignDialog extends StatefulWidget {
  const _AssignDialog({this.vanId, this.dispatcherId});
  final String? vanId;
  final String? dispatcherId;

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  late final Future<(List<Van>, List<StaffMember>)> _load = _roster(context.read<FleetRepository>());
  late String? _vanId = widget.vanId;
  late String? _dispatcherId = widget.dispatcherId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Assign van and Dispatcher'),
      content: SizedBox(
        width: 420,
        child: FutureBuilder(
          future: _load,
          builder: (context, snap) {
            if (snap.hasError) return Text('${snap.error}', style: TextStyle(color: AppColors.danger));
            if (!snap.hasData) return const LinearProgressIndicator();
            final (vans, crew) = snap.data!;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Validated vans and Dispatchers only. The Dispatcher can scan and log fares '
                    'from now on.', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Van'),
                  isExpanded: true,
                  initialValue: vans.any((v) => v.vanId == _vanId) ? _vanId : null,
                  items: [for (final v in vans) DropdownMenuItem(value: v.vanId, child: Text(_vanLabel(v)))],
                  onChanged: (v) => setState(() => _vanId = v),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Dispatcher'),
                  isExpanded: true,
                  initialValue: crew.any((s) => s.userId == _dispatcherId) ? _dispatcherId : null,
                  items: [for (final s in crew) DropdownMenuItem(value: s.userId, child: Text(s.fullName))],
                  onChanged: (v) => setState(() => _dispatcherId = v),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _vanId == null && _dispatcherId == null
              ? null
              : () => Navigator.pop(context, (_vanId, _dispatcherId)),
          child: const Text('Assign'),
        ),
      ],
    );
  }
}

/// A reason, and optionally a van: void, change van, review. Pops
/// (vanId, reason).
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.intro,
    required this.confirmLabel,
    this.vanId,
    this.reasonRequired = false,
    this.reasonRequiredIfVanChanges = false,
    this.danger = false,
  });

  final String title;
  final String intro;
  final String confirmLabel;
  /// The trip's van. When set, the dialog offers a van picker.
  final String? vanId;
  final bool reasonRequired;
  final bool reasonRequiredIfVanChanges;
  final bool danger;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late final Future<(List<Van>, List<StaffMember>)>? _load =
      widget.vanId == null ? null : _roster(context.read<FleetRepository>());
  late String? _vanId = widget.vanId;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _needsReason =>
      widget.reasonRequired || (widget.reasonRequiredIfVanChanges && _vanId != widget.vanId);

  @override
  Widget build(BuildContext context) {
    final ready = !_needsReason || _reason.text.trim().length >= 3;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.intro, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.md),
            if (_load != null)
              FutureBuilder(
                future: _load,
                builder: (context, snap) {
                  if (snap.hasError) return Text('${snap.error}', style: TextStyle(color: AppColors.danger));
                  if (!snap.hasData) return const LinearProgressIndicator();
                  final vans = snap.data!.$1;
                  return DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Van'),
                    isExpanded: true,
                    initialValue: vans.any((v) => v.vanId == _vanId) ? _vanId : null,
                    items: [for (final v in vans) DropdownMenuItem(value: v.vanId, child: Text(_vanLabel(v)))],
                    onChanged: (v) => setState(() => _vanId = v),
                  );
                },
              ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _reason,
              maxLength: 200,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _needsReason ? 'Reason' : 'Reason (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          style: widget.danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: ready ? () => Navigator.pop(context, (_vanId, _reason.text.trim())) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
