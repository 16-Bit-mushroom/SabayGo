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
            description: 'An operator\'s contest of a fare line or a driving flag. Record one from '
                'Money or Driving Flags; the Terminal Manager decides each, with a note.',
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
                            title: _status == 'open' ? 'No open disputes' : 'Nothing here yet',
                            hint: _status == 'open'
                                ? 'A dispute is recorded from a fare line on Money or from a flag on Driving Flags.'
                                : null)
                        // Cards two to a row on a wide screen (the owner's
                        // reference), one on a narrow one.
                        : LayoutBuilder(builder: (context, c) {
                            final two = c.maxWidth >= 1000;
                            final w = two ? (c.maxWidth - AppSpacing.lg) / 2 : c.maxWidth;
                            return SingleChildScrollView(
                              child: Wrap(spacing: AppSpacing.lg, runSpacing: AppSpacing.lg, children: [
                                for (final d in list)
                                  SizedBox(width: w, child: _DisputeCard(dispute: d, onChanged: _load)),
                              ]),
                            );
                          }),
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
    final open = d.status == 'open';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(6)),
            child: Text(d.plateNumber ?? 'No van',
                style: const TextStyle(color: AppColors.onFill, fontWeight: FontWeight.w700, fontSize: 12.5, letterSpacing: 0.4)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(d.tripLabel, style: text.bodySmall, overflow: TextOverflow.ellipsis)),
          badge,
        ]),
        const SizedBox(height: AppSpacing.md),
        Text(isLine ? 'Fare line dispute' : 'Driving flag dispute', style: text.titleMedium),
        Text('Contested: ${d.item}', style: text.bodySmall?.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.md),
        // The operator's own words, as recorded at the counter.
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.warningContainer,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('“${d.operatorStatement}”',
                style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic, color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.xs),
            Text('Recorded by ${d.raisedByName}, ${_when.format(d.raisedAt)}', style: text.bodySmall),
          ]),
        ),
        if (d.decidedAt != null) ...[
          const SizedBox(height: AppSpacing.md),
          FactLine(Icons.gavel_outlined,
              '${d.status == 'withdrawn' ? 'Withdrawn' : 'Decided'} by ${d.decidedByName ?? '—'}, '
              '${_when.format(d.decidedAt!)}'
              '${d.adjustedAmount != null ? ', share due ${peso.format(d.adjustedAmount!)}' : ''}'
              '${d.decisionNote != null ? ': ${d.decisionNote}' : ''}'),
        ],
        const SizedBox(height: AppSpacing.md),
        const Divider(),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            Text(isLine ? 'Share withheld: ${peso.format(d.amountDisputed)}' : 'A flag withholds nothing',
                style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
            if (open)
              Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
                if (manager) ...[
                  FilledButton(onPressed: () => _decide(context, 'upheld'), child: const Text('Uphold')),
                  if (isLine)
                    FilledButton.tonal(onPressed: () => _decide(context, 'adjusted'), child: const Text('Adjust')),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
                    onPressed: () => _decide(context, 'rejected'),
                    child: const Text('Reject'),
                  ),
                ],
                TextButton(onPressed: () => _withdraw(context), child: const Text('Withdraw')),
              ]),
          ],
        ),
        if (open && !manager)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text('Only the Terminal Manager decides a dispute.', style: text.bodySmall),
          ),
      ]),
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

  Future<void> _decide(BuildContext context, String outcome) async {
    final money = context.read<MoneyRepository>();
    final picked = await showDialog<(String, String, String?)>(
      context: context,
      builder: (_) => _DecideDialog(dispute: dispute, initial: outcome),
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
  const _DecideDialog({required this.dispute, this.initial = 'rejected'});
  final Dispute dispute;

  /// The outcome chosen on the card (Uphold, Adjust or Reject).
  final String initial;

  @override
  State<_DecideDialog> createState() => _DecideDialogState();
}

class _DecideDialogState extends State<_DecideDialog> {
  late String _outcome = widget.initial;
  final _note = TextEditingController();
  final _amount = TextEditingController();

  // What the chosen decision would do to the van's statement, worked out
  // by the server from the real decision and rolled back (finding 35), so
  // a share already handed to the operator is never a surprise.
  DecisionPreview? _preview;
  String? _previewError;
  int _asked = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!_isLine) return;
    String? amount;
    if (_outcome == 'adjusted') {
      final v = double.tryParse(_amount.text);
      if (v == null || v < 0 || v > widget.dispute.amountDisputed) {
        setState(() {
          _preview = null;
          _previewError = null;
        });
        return;
      }
      amount = v.toStringAsFixed(2);
    }
    final money = context.read<MoneyRepository>();
    final asked = ++_asked;
    try {
      final p = await money.preview(widget.dispute.disputeId, outcome: _outcome, adjustedAmount: amount);
      if (mounted && asked == _asked) {
        setState(() {
          _preview = p;
          _previewError = null;
        });
      }
    } catch (e) {
      if (mounted && asked == _asked) {
        setState(() {
          _preview = null;
          _previewError = e is ApiException ? e.message : 'What this changes could not be worked out.';
        });
      }
    }
  }

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
              onChanged: (v) {
                setState(() => _outcome = v!);
                _refresh();
              },
              child: Column(children: [
                RadioListTile(value: 'upheld', title: const Text('Upheld'), subtitle: Text(line
                    ? 'The operator is right: the line is taken off the balance.'
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
                onChanged: (_) {
                  setState(() {});
                  _refresh();
                },
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Share due',
                  prefixText: '₱ ',
                  helperText: 'Between ₱0.00 and ${peso.format(widget.dispute.amountDisputed)}',
                ),
              ),
            if (line && _preview != null) ...[
              const SizedBox(height: AppSpacing.md),
              _Effect(_preview!, plate: widget.dispute.plateNumber),
            ] else if (line && _previewError != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(_previewError!, style: TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: AppSpacing.md),
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

/// What a decision changes on the van's statement: the fees, what is due
/// now, the operator's share -- and, when the operator already holds more
/// of the share than would then be owed, that excess said in words with
/// what happens next.
class _Effect extends StatelessWidget {
  const _Effect(this.preview, {required this.plate});

  final DecisionPreview preview;
  final String? plate;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = preview.before, a = preview.after;
    Widget row(String label, double from, double to) {
      final changed = (from - to).abs() > 0.004;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label, style: text.bodySmall)),
          Text(
            changed ? '${peso.format(from)}  →  ${peso.format(to)}' : '${peso.format(to)}  unchanged',
            style: text.bodySmall?.copyWith(
              color: changed ? AppColors.textPrimary : AppColors.textMuted,
              fontWeight: changed ? FontWeight.w600 : FontWeight.w400,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('What this changes on ${plate ?? 'the van'}\'s statement', style: text.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        row('Terminal fees', b.terminalFeesOwed, a.terminalFeesOwed),
        row('Balance', b.amountDue, a.amountDue),
        row('Operator\'s share', b.operatorShareOwed, a.operatorShareOwed),
        if (a.operatorShareOver > 0.004) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'The operator has already been paid ${peso.format(a.operatorShareHeld)}: '
                '${peso.format(a.operatorShareOver)} more than the share would be. The Cashier is told, '
                'and records it on Money when the operator hands it back.',
                style: text.bodySmall?.copyWith(color: AppColors.textPrimary),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
