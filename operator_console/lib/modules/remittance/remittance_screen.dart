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
/// the day -- income paid through the app (verified) and in cash to the
/// Dispatcher (declared), A2Z's share of it, any share held from a trip
/// that left unpaid, what has been paid, and what is disputed.
///
/// The Cashier records the payment the Dispatcher hands over, and may
/// record an operator's dispute on a line until that payment. Nothing here
/// is estimated: the lines are the passenger list.
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
            technicalNote: 'Remittances · Remittance_Lines',
            description: 'Each van\'s statement for the day: A2Z\'s share of the fares on its passenger '
                'lists. The Dispatcher hands the share over and the Cashier records it here.',
            actions: [
              DayPicker(day: _day, onShift: _shift),
              RefreshButton(onPressed: _load, busy: _loading),
            ],
          ),
          if (_statements != null && list.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [
                SizedBox(width: 200, child: StatTile(
                    label: 'A2Z\'s share', value: peso.format(sum((s) => s.remittanceOwed + s.heldShare)),
                    icon: Icons.account_balance_outlined)),
                SizedBox(width: 200, child: StatTile(
                    label: 'Paid', value: peso.format(sum((s) => s.settledAmount)),
                    icon: Icons.paid_outlined, color: AppColors.success)),
                SizedBox(width: 200, child: StatTile(
                    label: 'Due now', value: peso.format(sum((s) => s.amountDue)),
                    icon: Icons.payments_outlined, color: AppColors.warning)),
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
        ? StatusBadge('Owes ${peso.format(s.amountDue)}', tone: Tone.danger)
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
            _figure(context, 'Paid through the app (verified)', s.verifiedIncome),
            _figure(context, 'Paid in cash (declared)', s.declaredIncome),
            _figure(context, 'A2Z\'s share (${s.ratePct.toStringAsFixed(0)} %)', s.remittanceOwed),
            if (s.heldShare > 0) _figure(context, 'Held from a trip that left unpaid', s.heldShare),
            _figure(context, 'Paid', s.settledAmount),
            if (s.disputed > 0) _figure(context, 'Disputed', s.disputed),
          ]),
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
          if (cashier && s.amountDue > 0)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _pay(context),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: Text('Record payment of ${peso.format(s.amountDue)}'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _figure(BuildContext context, String label, double value) {
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: text.bodySmall),
      Text(peso.format(value),
          style: text.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
    ]);
  }

  Future<void> _pay(BuildContext context) async {
    final money = context.read<MoneyRepository>();
    final picked = await showDialog<(String, String, String?)>(
      context: context,
      builder: (_) => _PaymentDialog(statement: statement),
    );
    if (picked == null || !context.mounted) return;
    final ok = await runAction(
      context,
      () => money.pay(statement.remittanceId,
          amount: picked.$1, reference: picked.$2, handedOverBy: picked.$3),
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
        SizedBox(width: 40, child: StatusBadge(l.incomeGroup,
            tone: l.incomeGroup == 'V' ? Tone.info : Tone.neutral)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text('${l.count} × ${peso.format(l.fare)} to ${l.destination}'
              '${l.isTopUp ? '  · top-up' : ''}', style: text.bodyMedium),
        ),
        SizedBox(width: 110, child: Text(peso.format(l.gross), textAlign: TextAlign.right, style: text.bodySmall)),
        SizedBox(width: 110, child: Text(peso.format(l.share), textAlign: TextAlign.right,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
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
/// reference, and the Dispatcher who handed it over.
class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.statement});
  final Statement statement;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _amount = TextEditingController(text: widget.statement.amountDue.toStringAsFixed(2));
  final _reference = TextEditingController();
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
    super.dispose();
  }

  bool get _ok => (double.tryParse(_amount.text) ?? 0) > 0;

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
                  (double.parse(_amount.text).toStringAsFixed(2), _reference.text.trim(), _handedOverBy))
              : null,
          child: const Text('Record payment'),
        ),
      ],
    );
  }
}
