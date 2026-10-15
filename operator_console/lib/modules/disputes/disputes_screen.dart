import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/money_repository.dart';
import '../../viewmodels/auth_provider.dart';

/// Disputes (brief 9, Table 39): an operator contests a fare line or a
/// driving flag. The Cashier, the Dispatcher or the Terminal Manager
/// records it (from Remittance or Driving Flags here, or the Dispatcher's
/// app); only the Terminal Manager decides -- upheld, rejected or
/// adjusted -- with a note. A disputed share waits until then.
class DisputesScreen extends StatefulWidget {
  const DisputesScreen({super.key});

  @override
  State<DisputesScreen> createState() => _DisputesScreenState();
}

class _DisputesScreenState extends State<DisputesScreen> {
  late final MoneyRepository _money = context.read<MoneyRepository>();
  String _status = 'open';
  List<Dispute>? _list;
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
      final list = await _money.disputes(status: _status);
      if (mounted) setState(() => _list = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list ?? const <Dispute>[];
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Disputes',
            technicalNote: 'Disputes',
            description: 'An operator\'s contest of a fare line or a driving flag. Record one from '
                'Remittance or Driving Flags; the Terminal Manager decides each, with a note.',
            actions: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'open', label: Text('Open')),
                  ButtonSegment(value: 'resolved', label: Text('Decided')),
                  ButtonSegment(value: 'withdrawn', label: Text('Withdrawn')),
                ],
                selected: {_status},
                onSelectionChanged: (s) {
                  setState(() => _status = s.first);
                  _load();
                },
              ),
              RefreshButton(onPressed: _load, busy: _loading),
            ],
          ),
          Expanded(
            child: _loading && _list == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? LoadError(message: _error!, onRetry: _load)
                    : list.isEmpty
                        ? EmptyState(
                            icon: Icons.gavel_outlined,
                            title: _status == 'open' ? 'No open disputes' : 'Nothing here yet')
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                            itemBuilder: (_, i) => _DisputeCard(dispute: list[i], onChanged: _load),
                          ),
          ),
        ],
      ),
    );
  }
}

class _DisputeCard extends StatelessWidget {
  const _DisputeCard({required this.dispute, required this.onChanged});
  final Dispute dispute;
  final VoidCallback onChanged;

  static final _when = DateFormat('d MMM, h:mm a');

  @override
  Widget build(BuildContext context) {
    final d = dispute;
    final role = context.read<AuthProvider>().profile?.role;
    final manager = role?.isManager ?? false;
    final text = Theme.of(context).textTheme;
    final isLine = d.subject == 'fare_line';
    final badge = switch ((d.status, d.outcome)) {
      ('open', _) => const StatusBadge('Waiting for a decision', tone: Tone.warning),
      ('withdrawn', _) => const StatusBadge('Withdrawn'),
      (_, 'upheld') => const StatusBadge('Upheld', tone: Tone.success),
      (_, 'adjusted') => const StatusBadge('Adjusted', tone: Tone.info),
      (_, _) => const StatusBadge('Rejected', tone: Tone.danger),
    };
    return Panel(
      title: '${isLine ? 'Fare line' : 'Driving flag'}: ${d.item}',
      icon: isLine ? Icons.receipt_long_outlined : Icons.speed,
      trailing: badge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FactLine(Icons.directions_bus_outlined, d.tripLabel),
          FactLine(Icons.format_quote, '"${d.operatorStatement}"'),
          FactLine(Icons.person_outline, 'Recorded by ${d.raisedByName}, ${_when.format(d.raisedAt)}'),
          if (isLine) FactLine(Icons.account_balance_outlined, 'Share withheld: ${peso.format(d.amountDisputed)}'),
          if (d.decidedAt != null)
            FactLine(Icons.gavel_outlined,
                '${d.status == 'withdrawn' ? 'Withdrawn' : 'Decided'} by ${d.decidedByName ?? '—'}, '
                '${_when.format(d.decidedAt!)}'
                '${d.adjustedAmount != null ? ' · share due ${peso.format(d.adjustedAmount!)}' : ''}'
                '${d.decisionNote != null ? ': ${d.decisionNote}' : ''}'),
          if (d.status == 'open') ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(spacing: AppSpacing.sm, children: [
              if (manager)
                FilledButton.icon(
                  onPressed: () => _decide(context),
                  icon: const Icon(Icons.gavel, size: 18),
                  label: const Text('Decide'),
                ),
              OutlinedButton(onPressed: () => _withdraw(context), child: const Text('Withdraw')),
            ]),
            if (!manager)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text('Only the Terminal Manager decides a dispute.', style: text.bodySmall),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _withdraw(BuildContext context) async {
    final money = context.read<MoneyRepository>();
    final note = await askText(context,
        title: 'Withdraw the dispute?',
        intro: 'The operator drops it. A withheld share is due again.',
        label: 'Note',
        confirmLabel: 'Withdraw',
        required: false);
    if (note == null || !context.mounted) return;
    if (await runAction(context, () => money.withdraw(dispute.disputeId, note), 'Dispute withdrawn.')) {
      onChanged();
    }
  }

  Future<void> _decide(BuildContext context) async {
    final money = context.read<MoneyRepository>();
    final picked = await showDialog<(String, String, String?)>(
      context: context,
      builder: (_) => _DecideDialog(dispute: dispute),
    );
    if (picked == null || !context.mounted) return;
    if (await runAction(
        context,
        () => money.decide(dispute.disputeId, outcome: picked.$1, note: picked.$2, adjustedAmount: picked.$3),
        'Dispute decided.')) {
      onChanged();
    }
  }
}

class _DecideDialog extends StatefulWidget {
  const _DecideDialog({required this.dispute});
  final Dispute dispute;

  @override
  State<_DecideDialog> createState() => _DecideDialogState();
}

class _DecideDialogState extends State<_DecideDialog> {
  String _outcome = 'rejected';
  final _note = TextEditingController();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    _amount.dispose();
    super.dispose();
  }

  bool get _isLine => widget.dispute.subject == 'fare_line';

  bool get _ok {
    if (_note.text.trim().length < 3) return false;
    if (_outcome != 'adjusted') return true;
    final v = double.tryParse(_amount.text);
    return v != null && v >= 0 && v <= widget.dispute.amountDisputed;
  }

  @override
  Widget build(BuildContext context) {
    final line = _isLine;
    return AlertDialog(
      title: const Text('Decide the dispute'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.dispute.item),
            const SizedBox(height: AppSpacing.md),
            RadioGroup<String>(
              groupValue: _outcome,
              onChanged: (v) => setState(() => _outcome = v!),
              child: Column(children: [
                RadioListTile(value: 'upheld', title: const Text('Upheld'), subtitle: Text(line
                    ? 'The operator is right: the line is taken out of what is owed.'
                    : 'The flag is dismissed.')),
                RadioListTile(value: 'rejected', title: const Text('Rejected'), subtitle: Text(line
                    ? 'The share is due again.'
                    : 'The flag stands, reviewed.')),
                if (line)
                  const RadioListTile(value: 'adjusted', title: Text('Adjusted'),
                      subtitle: Text('Part of the share is due: set the amount.')),
              ]),
            ),
            if (_outcome == 'adjusted')
              TextField(
                controller: _amount,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Share due',
                  prefixText: '₱ ',
                  helperText: 'Between ₱0.00 and ${peso.format(widget.dispute.amountDisputed)}',
                ),
              ),
            TextField(
              controller: _note,
              onChanged: (_) => setState(() {}),
              maxLength: 255,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Reason for the decision'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _ok
              ? () => Navigator.pop(context, (
                    _outcome,
                    _note.text.trim(),
                    _outcome == 'adjusted' ? double.parse(_amount.text).toStringAsFixed(2) : null,
                  ))
              : null,
          child: const Text('Decide'),
        ),
      ],
    );
  }
}
