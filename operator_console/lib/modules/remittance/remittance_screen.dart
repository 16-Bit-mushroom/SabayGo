import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/fleet_repository.dart';
import '../../data/repositories/money_repository.dart';
import '../../viewmodels/auth_provider.dart';

/// Remittance (brief 9, replaces Fares & Cash): each van's statement for
/// the day -- income reserved in the app (Booked) and listed as walk-ups
/// (Walk-up), all of it cash; the terminal fees it owes (A2Z's 15 %, the
/// DCOTT ticket per trip, the day's parking); any share held from a trip
/// that left unpaid; what has been paid; what is disputed; and the
/// operator's share, owed and handed over.
///
/// The Cashier records the terminal fees the Dispatcher hands over with
/// the operator's share, a later difference in that share, and a
/// parking-only charge for a van with no trip. An operator's dispute on a
/// line may be recorded until its payment. Nothing here is estimated: the
/// lines are the passenger list.
class RemittanceScreen extends StatefulWidget {
  const RemittanceScreen({super.key});

  @override
  State<RemittanceScreen> createState() => _RemittanceScreenState();
}

class _RemittanceScreenState extends State<RemittanceScreen> {
  late final MoneyRepository _money = context.read<MoneyRepository>();
  DateTime _day = DateUtils.dateOnly(DateTime.now());
  List<Statement>? _statements;
  Set<String> _disputedLines = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final statements = await _money.statements(isoDay(_day));
      final open = await _money.disputes(status: 'open');
      if (!mounted) return;
      setState(() {
        _statements = statements;
        _disputedLines = {for (final d in open) if (d.lineId != null) d.lineId!};
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The day's ₱50 for a van parked at the terminal with no trip.
  Future<void> _parking() async {
    List<Van> vans;
    try {
      vans = await context.read<FleetRepository>().listVans();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    final charged = {for (final s in _statements ?? const <Statement>[]) s.vanId};
    final van = await showDialog<Van>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Parking-only charge'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('For a van parked at the terminal today with no trip. It opens a statement of '
                'its own with the day\'s parking, paid like any other.'),
          ),
          for (final v in vans)
            if (!charged.contains(v.vanId))
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, v), child: Text(v.plateNumber)),
        ],
      ),
    );
    if (van == null || !mounted) return;
    if (await runAction(context, () => _money.chargeParking(van.vanId),
        'Parking charged to ${van.plateNumber}.')) {
      _load();
    }
  }

  void _shift(int days) {
    setState(() => _day = _day.add(Duration(days: days)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _statements ?? const <Statement>[];
    double sum(double Function(Statement) f) => list.fold(0, (a, s) => a + f(s));
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Remittance',
            description: 'Each van\'s statement for the day: the terminal fees owed on its passenger lists '
                '(A2Z\'s 15 %, the DCOTT ticket per trip, the day\'s parking) and the operator\'s share. '
                'The Dispatcher hands them over and the Cashier records them here.',
            actions: [
              if (context.read<AuthProvider>().profile?.role.isCashier ?? false)
                OutlinedButton.icon(
                  onPressed: _parking,
                  icon: const Icon(Icons.local_parking_outlined, size: 18),
                  label: const Text('Parking-only charge'),
                ),
              DayPicker(day: _day, onShift: _shift),
              RefreshButton(onPressed: _load, busy: _loading),
            ],
          ),
          if (_statements != null && list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [
                SizedBox(width: 200, child: StatTile(
                    label: 'Terminal fees', value: peso.format(sum((s) => s.terminalFeesOwed + s.heldShare)),
                    icon: Icons.account_balance_outlined, caption: '15 % + DCOTT tickets + parking')),
                SizedBox(width: 200, child: StatTile(
                    label: 'Paid', value: peso.format(sum((s) => s.settledAmount)),
                    icon: Icons.paid_outlined, color: AppColors.success)),
                SizedBox(width: 200, child: StatTile(
                    label: 'Due now', value: peso.format(sum((s) => s.amountDue)),
                    icon: Icons.payments_outlined, color: AppColors.warning)),
                SizedBox(width: 200, child: StatTile(
                    label: 'Operator\'s share', value: peso.format(sum((s) => s.operatorShareOwed)),
                    icon: Icons.person_outline,
                    caption: 'Given ${peso.format(sum((s) => s.operatorShareGiven))}')),
                SizedBox(width: 200, child: StatTile(
                    label: 'Disputed', value: peso.format(sum((s) => s.disputed)),
                    icon: Icons.gavel_outlined, caption: 'Waits for the Terminal Manager')),
              ]),
            ),
          Expanded(
            child: _loading && _statements == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? LoadError(message: _error!, onRetry: _load)
                    : list.isEmpty
                        ? const EmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: 'No statements on this day',
                            hint: 'A van\'s statement opens with its first listed passenger.')
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.lg),
                            itemBuilder: (_, i) => _StatementPanel(
                              statement: list[i],
                              disputedLines: _disputedLines,
                              onChanged: _load,
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}

class _StatementPanel extends StatelessWidget {
  const _StatementPanel({required this.statement, required this.disputedLines, required this.onChanged});

  final Statement statement;
  final Set<String> disputedLines;
  final VoidCallback onChanged;

  static final _time = DateFormat.jm();

  @override
  Widget build(BuildContext context) {
    final s = statement;
    final role = context.read<AuthProvider>().profile?.role;
    final cashier = role?.isCashier ?? false;
    final records = cashier || (role?.isManager ?? false);
    final text = Theme.of(context).textTheme;
    final badge = s.amountDue > 0
        // Ochre, not red: owing the day's share is routine until it is paid,
        // and red would read as wrongdoing (cash in hand is not missing).
        ? StatusBadge('Owes ${peso.format(s.amountDue)}', tone: Tone.warning)
        : s.disputed > 0
            ? const StatusBadge('Disputed share waits', tone: Tone.warning)
            : const StatusBadge('Paid', tone: Tone.success);

    final byTrip = <DateTime, List<StatementLine>>{};
    for (final l in s.lines) {
      byTrip.putIfAbsent(l.tripDeparture, () => []).add(l);
    }

    return Panel(
      title: '${s.plateNumber} · ${s.operatorName}',
      icon: Icons.receipt_long_outlined,
      trailing: badge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: AppSpacing.xl, runSpacing: AppSpacing.sm, children: [
            _figure(context, 'Booked (B)', s.bookedIncome),
            _figure(context, 'Walk-up (W)', s.walkUpIncome),
            _figure(context, 'A2Z\'s ${s.ratePct.toStringAsFixed(0)} %', s.remittanceOwed),
            _figure(context, 'DCOTT tickets (${_trips(s)} × ${peso.format(s.dcottTicketFee)})', s.dcottFees),
            _figure(context, 'Parking', s.parkingFee),
            _figure(context, 'Terminal fees owed', s.terminalFeesOwed, strong: true),
            if (s.heldShare > 0) _figure(context, 'Held from a trip that left unpaid', s.heldShare),
            _figure(context, 'Paid', s.settledAmount),
            _figure(context, 'Due now', s.amountDue, strong: true),
            if (s.disputed > 0) _figure(context, 'Disputed', s.disputed),
          ]),
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: AppSpacing.xl, runSpacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.center,
              children: [
            _figure(context, 'Operator\'s share owed', s.operatorShareOwed),
            _figure(context, 'Operator\'s share given', s.operatorShareGiven),
            // A warning only: the share is handed between the Dispatcher and
            // the operator, and a difference blocks nothing (T68).
            if (s.operatorShareDiffers)
              StatusBadge(
                  'Operator share differs by ${peso.format((s.operatorShareDifference ?? 0).abs())}',
                  tone: Tone.warning),
          ]),
          if (s.operatorShareGivenAt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            FactLine(Icons.person_outline,
                'Operator\'s share recorded by ${s.operatorShareRecordedByName ?? 'the Cashier'} '
                'at ${_time.format(s.operatorShareGivenAt!)}'),
          ],
          if (s.settledAt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            FactLine(Icons.how_to_reg_outlined,
                'Last payment recorded by ${s.recordedByName ?? 'the Cashier'} at ${_time.format(s.settledAt!)}'
                '${s.handedOverByName != null ? ', handed over by ${s.handedOverByName}' : ''}'
                '${s.settlementRef != null ? ' · Ref. ${s.settlementRef}' : ''}'),
          ],
          const Divider(height: AppSpacing.xl),
          for (final entry in byTrip.entries) ...[
            Text('${_time.format(entry.key)} trip', style: text.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            for (final l in entry.value)
              _LineRow(line: l, disputed: disputedLines.contains(l.lineId), canDispute: records,
                  onChanged: onChanged),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (cashier)
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: AppSpacing.sm, children: [
                OutlinedButton.icon(
                  onPressed: () => _operatorShare(context),
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: const Text('Record operator\'s share'),
                ),
                if (s.amountDue > 0)
                  FilledButton.icon(
                    onPressed: () => _pay(context),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: Text('Record payment of ${peso.format(s.amountDue)}'),
                  ),
              ]),
            ),
        ],
      ),
    );
  }

  static int _trips(Statement s) => s.dcottTicketFee > 0 ? (s.dcottFees / s.dcottTicketFee).round() : 0;

  Widget _figure(BuildContext context, String label, double value, {bool strong = false}) {
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: text.bodySmall),
      Text(peso.format(value),
          style: text.titleMedium?.copyWith(
              fontWeight: strong ? FontWeight.w700 : null,
              fontFeatures: const [FontFeature.tabularFigures()])),
    ]);
  }

  /// A difference in the operator's share, handed over after the payment.
  Future<void> _operatorShare(BuildContext context) async {
    final money = context.read<MoneyRepository>();
    final left = statement.operatorShareOwed - statement.operatorShareGiven;
    final amount = await askText(
      context,
      title: 'Record operator\'s share · ${statement.plateNumber}',
      intro: 'Owed ${peso.format(statement.operatorShareOwed)}, recorded so far '
          '${peso.format(statement.operatorShareGiven)}'
          '${left > 0 ? ', ${peso.format(left)} still to give' : ''}. Enter what the Dispatcher has just '
          'handed the operator.',
      label: 'Amount handed to the operator (₱)',
      confirmLabel: 'Record',
      maxLength: 12,
    );
    if (amount == null || !context.mounted) return;
    final value = double.tryParse(amount.trim());
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter an amount above zero.')));
      return;
    }
    if (await runAction(context, () => money.recordOperatorShare(statement.remittanceId, value.toStringAsFixed(2)),
        'Operator\'s share recorded for ${statement.plateNumber}.')) {
      onChanged();
    }
  }

  Future<void> _pay(BuildContext context) async {
    final money = context.read<MoneyRepository>();
    final picked = await showDialog<(String, String, String?, String?)>(
      context: context,
      builder: (_) => _PaymentDialog(statement: statement),
    );
    if (picked == null || !context.mounted) return;
    final ok = await runAction(
      context,
      () => money.pay(statement.remittanceId,
          amount: picked.$1, reference: picked.$2, handedOverBy: picked.$3, operatorShare: picked.$4),
      'Payment recorded for ${statement.plateNumber}.',
    );
    if (ok) onChanged();
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.disputed, required this.canDispute, required this.onChanged});
  final StatementLine line;
  final bool disputed;
  final bool canDispute;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = line;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: 40, child: StatusBadge(l.incomeGroup == 'booked' ? 'B' : 'W',
            tone: l.incomeGroup == 'booked' ? Tone.info : Tone.neutral)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text('${l.count} × ${peso.format(l.fare)} to ${l.destination}'
              '${l.isTopUp ? '  · top-up' : ''}', style: text.bodyMedium),
        ),
        SizedBox(width: 110, child: Text(peso.format(l.gross), textAlign: TextAlign.right, style: text.bodySmall)),
        SizedBox(width: 110, child: Text(peso.format(l.share), textAlign: TextAlign.right,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
        SizedBox(
          width: 150,
          child: Align(
            alignment: Alignment.centerRight,
            child: disputed
                ? const StatusBadge('Disputed', tone: Tone.warning)
                : canDispute
                    ? TextButton(onPressed: () => _dispute(context), child: const Text('Record dispute'))
                    : null,
          ),
        ),
      ]),
    );
  }

  Future<void> _dispute(BuildContext context) async {
    final money = context.read<MoneyRepository>();
    final words = await askText(
      context,
      title: 'Record the operator\'s dispute',
      intro: '${line.count} × ${peso.format(line.fare)} to ${line.destination}: A2Z\'s share of '
          '${peso.format(line.share)} waits until the Terminal Manager decides. A line can be '
          'disputed only until its payment is recorded.',
      label: 'The operator\'s words',
      confirmLabel: 'Record dispute',
      maxLength: 500,
    );
    if (words == null || !context.mounted) return;
    if (await runAction(context, () => money.disputeLine(line.lineId, words), 'Dispute recorded.')) {
      onChanged();
    }
  }
}

/// The amount handed over (the amount due by default), the receipt
/// reference, the Dispatcher who handed it over, and the operator's share
/// handed to the operator in the same step.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.statement});
  final Statement statement;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _amount = TextEditingController(text: widget.statement.amountDue.toStringAsFixed(2));
  final _reference = TextEditingController();
  late final _share = TextEditingController(text: () {
    final left = widget.statement.operatorShareOwed - widget.statement.operatorShareGiven;
    return left > 0 ? left.toStringAsFixed(2) : '';
  }());
  List<StaffMember>? _dispatchers;
  String? _handedOverBy;

  @override
  void initState() {
    super.initState();
    context.read<FleetRepository>().listCrew(role: 'dispatcher').then((list) {
      if (mounted) setState(() => _dispatchers = list);
    }, onError: (_) {
      if (mounted) setState(() => _dispatchers = const []);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _share.dispose();
    super.dispose();
  }

  bool get _ok =>
      (double.tryParse(_amount.text) ?? 0) > 0 &&
      (_share.text.trim().isEmpty || (double.tryParse(_share.text.trim()) ?? -1) >= 0);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Record payment · ${widget.statement.plateNumber}'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _amount,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount received', prefixText: '₱ '),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _share,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: 'Operator\'s share handed to the operator',
                prefixText: '₱ ',
                helperText: 'Owed ${peso.format(widget.statement.operatorShareOwed)}. Leave empty if not yet given.'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _reference,
            maxLength: 64,
            decoration: const InputDecoration(labelText: 'Receipt number (optional)'),
          ),
          DropdownButtonFormField<String?>(
            initialValue: _handedOverBy,
            decoration: const InputDecoration(labelText: 'Handed over by'),
            items: [
              const DropdownMenuItem(value: null, child: Text('The trip\'s Dispatcher')),
              for (final d in _dispatchers ?? const <StaffMember>[])
                DropdownMenuItem(value: d.userId, child: Text(d.fullName)),
            ],
            onChanged: (v) => setState(() => _handedOverBy = v),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _ok
              ? () => Navigator.pop(context,
                  (double.parse(_amount.text).toStringAsFixed(2), _reference.text.trim(), _handedOverBy,
                      _share.text.trim().isEmpty ? null : double.parse(_share.text.trim()).toStringAsFixed(2)))
              : null,
          child: const Text('Record payment'),
        ),
      ],
    );
  }
}
