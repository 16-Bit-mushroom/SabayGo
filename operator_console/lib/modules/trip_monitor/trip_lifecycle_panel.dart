import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/fleet_repository.dart';
import '../../viewmodels/auth_provider.dart';

/// Assignment, A2Z's share, start, departure and the Terminal Manager's
/// changes for one trip (change brief 2.1, 4.2).
///
/// The rules are the server's: this panel offers what the signed-in role
/// may do at this point in the trip and says why a button is off, so a
/// refusal is rare and, when it comes, is the server's own sentence. The
/// office assigns, starts and departs; Start waits for the Cashier to
/// record the 15 % the Dispatcher hands over. Only the Terminal Manager
/// lifts that block, reviews an automatic start, changes a started trip's
/// van or voids a trip, and records no payment.
class TripLifecyclePanel extends StatelessWidget {
  const TripLifecyclePanel({super.key, required this.trip, required this.onChanged});

  final TripBoardEntry trip;
  final VoidCallback onChanged;

  static final _time = DateFormat.jm();

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final role = context.read<AuthProvider>().profile?.role;
    final manager = role?.isManager ?? false;
    final cashier = role?.isCashier ?? false;
    final text = Theme.of(context).textTheme;
    final scheduled = t.status == 'scheduled';
    final started = const {'boarding', 'departed', 'completed'}.contains(t.status);
    final windowOpen = !DateTime.now().isBefore(t.startOpensAt);
    final beforeDeparture = scheduled || t.status == 'boarding';
    // Before departure the share is the trip's; after, a trip that left
    // unpaid is still owed on the van's statement.
    final shareOwed = t.vanId != null &&
        ((beforeDeparture && t.paymentStatus == 'unpaid') || t.paymentStatus == 'left_unpaid');

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
      if (t.departureSource == 'gps')
        (Icons.gps_fixed, 'Departure detected: the van\'s GPS left the terminal', null)
      else if (t.departureSource == 'staff')
        (Icons.logout, 'Departed: tapped by the office', null)
      else if (t.departureSource == 'dispatcher')
        (Icons.logout, 'Departed: tapped by the Dispatcher', null),
      if (t.paymentStatus == 'left_unpaid')
        (Icons.money_off, 'Left before A2Z\'s 15 % was recorded. It is owed on the van\'s statement, '
            'and the van\'s next assignment waits, until the Cashier records it.', AppColors.danger)
      else if (t.paymentStatus == 'overridden')
        (Icons.lock_open, 'Payment block lifted by the Terminal Manager', AppColors.warning)
      else if (t.paymentStatus == 'paid')
        (Icons.paid_outlined, 'A2Z\'s 15 % recorded. The passenger list is locked: a cash passenger '
            'added now is a top-up.', null)
      else if (beforeDeparture && t.vanId != null)
        (Icons.payments_outlined, 'A2Z\'s 15 % not recorded yet. Start waits for it once passengers '
            'are listed.', AppColors.warning),
      if (t.phoneSilent == true && t.status != 'completed')
        (Icons.wifi_off, t.phoneLastReportAt == null
            ? 'The phone out with the van has not reported yet.'
            : 'The phone is silent: last report at ${_time.format(t.phoneLastReportAt!)}.', AppColors.danger)
      else if (t.phoneSilent == false)
        (Icons.phone_android, 'Phone reporting: last at ${_time.format(t.phoneLastReportAt!)}'
            '${t.phoneBatteryPct != null ? ', battery ${t.phoneBatteryPct} %' : ''}', null),
      if (t.changeNote != null) (Icons.edit_note, t.changeNote!, null),
    ];

    final actions = <Widget>[
      if (cashier && shareOwed)
        FilledButton.tonalIcon(
          onPressed: () => _recordShare(context),
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: const Text('Record A2Z\'s share'),
        ),
      if (manager && beforeDeparture && t.paymentStatus == 'unpaid')
        OutlinedButton.icon(
          onPressed: () => _override(context),
          icon: const Icon(Icons.lock_open, size: 18),
          label: const Text('Lift payment block'),
        ),
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
    final ok = await runAction(context, call, done);
    if (ok) onChanged();
    return ok;
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

  Future<void> _recordShare(BuildContext context) async {
    final dispatch = context.read<DispatchRepository>();
    final picked = await showDialog<(TripShare, String, String)>(
      context: context,
      builder: (_) => _ShareDialog(trip: trip),
    );
    if (picked == null || !context.mounted) return;
    final (share, amount, reference) = picked;
    await _run(context, () => dispatch.recordPayment(share, amount: amount, reference: reference),
        share.beforeDeparture ? 'Share recorded. Start is open.' : 'Payment recorded on the van\'s statement.');
  }

  Future<void> _override(BuildContext context) async {
    final dispatch = context.read<DispatchRepository>();
    final picked = await showDialog<(String?, String)>(
      context: context,
      builder: (_) => const _ReasonDialog(
        title: 'Lift the payment block?',
        intro: 'This trip may then be assigned and started before A2Z\'s share is recorded. The '
            'share stays owed on the van\'s statement. Your reason is kept with the trip and the '
            'Cashier is told.',
        confirmLabel: 'Lift block',
        reasonRequired: true,
      ),
    );
    if (picked == null || !context.mounted) return;
    await _run(context, () => dispatch.overridePayment(trip.tripId, note: picked.$2),
        'Payment block lifted for this trip.');
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

// ------------------------------------------------------------ A2Z's share
/// What the Cashier should receive now, line by line, and the amount and
/// receipt number to record. Pops (share, amount, reference).
class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.trip});
  final TripBoardEntry trip;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  static final _peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  late final Future<TripShare> _load = context
      .read<DispatchRepository>()
      .share(widget.trip.tripId, tripStatus: widget.trip.status)
      .then((s) {
    _amount.text = s.amountDue.toStringAsFixed(2);
    return s;
  });
  final _amount = TextEditingController();
  final _reference = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return FutureBuilder<TripShare>(
      future: _load,
      builder: (context, snap) {
        final share = snap.data;
        final amount = double.tryParse(_amount.text.trim());
        final valid = share != null && amount != null && amount > 0 && amount <= share.amountDue + 0.001;
        return AlertDialog(
          title: const Text('Record A2Z\'s 15 %'),
          content: SizedBox(
            width: 460,
            child: snap.hasError
                ? Text(snap.error is ApiException ? (snap.error as ApiException).message : '${snap.error}',
                    style: TextStyle(color: AppColors.danger))
                : share == null
                    ? const LinearProgressIndicator()
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            share.beforeDeparture
                                ? 'The share ${widget.trip.dispatcherName ?? 'the Dispatcher'} hands over '
                                    'for ${widget.trip.plateNumber}. Recording it locks the passenger list '
                                    'and opens Start.'
                                : 'This trip left without its share recorded. The payment goes on '
                                    '${widget.trip.plateNumber}\'s statement for the day.',
                            style: text.bodySmall,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          for (final l in share.lines)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                              child: Row(children: [
                                Expanded(
                                  child: Text(
                                    '${l.passengerCount} × ${_peso.format(l.farePerPassenger)} to '
                                    '${l.destination}${l.isTopUp ? ' · top-up' : ''}',
                                    style: text.bodySmall,
                                  ),
                                ),
                                Text(_peso.format(l.shareAmount), style: text.bodySmall),
                              ]),
                            ),
                          if (share.lines.isEmpty)
                            Text('No fare lines on this trip.', style: text.bodySmall),
                          const Divider(),
                          Row(children: [
                            Expanded(child: Text('Due now', style: text.titleSmall)),
                            Text(_peso.format(share.amountDue), style: text.titleSmall),
                          ]),
                          Text('Includes anything else the van still owes today.',
                              style: text.bodySmall?.copyWith(color: AppColors.textMuted)),
                          if (share.disputed > 0)
                            Text('${_peso.format(share.disputed)} is under dispute and not due.',
                                style: text.bodySmall?.copyWith(color: AppColors.warning)),
                          if (share.amountDue <= 0) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                                share.beforeDeparture
                                    ? 'Nothing is due. Start does not wait for a payment.'
                                    : 'Nothing is due: the van\'s statement is settled.',
                                style: text.bodySmall),
                          ] else ...[
                            const SizedBox(height: AppSpacing.md),
                            TextField(
                              controller: _amount,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(labelText: 'Amount received', prefixText: '₱ '),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextField(
                              controller: _reference,
                              maxLength: 64,
                              decoration: const InputDecoration(labelText: 'Receipt number (optional)'),
                            ),
                          ],
                        ],
                      ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: valid
                  ? () => Navigator.pop<(TripShare, String, String)>(context, (share, amount.toStringAsFixed(2), _reference.text.trim()))
                  : null,
              child: const Text('Record payment'),
            ),
          ],
        );
      },
    );
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
