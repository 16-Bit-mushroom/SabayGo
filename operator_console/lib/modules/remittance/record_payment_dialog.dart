import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../data/repositories/fleet_repository.dart';

/// The one **Record payment** dialog (10 Nov: one place per job, one name
/// per action). Money opens it for a van's statement, Trips for the trip
/// about to leave; both record the terminal fees the Dispatcher handed
/// over and, in the same step, the operator's share, on the van's
/// statement for the day. Before this the two pages had a dialog each,
/// with different names, fields and rules.
///
/// The operator's share given adds up on the server, so the dialog asks
/// for no more than is still to give, and asks nothing once it is all
/// given (findings 34 and 35).
class PaymentFacts {
  const PaymentFacts({
    required this.plate,
    required this.amountDue,
    required this.disputed,
    required this.operatorShareOwed,
    required this.operatorShareHeld,
    required this.operatorShareOver,
    this.intro,
    this.lines = const [],
  });

  final String plate;
  final double amountDue;
  final double disputed;
  final double operatorShareOwed;
  final double operatorShareHeld;
  final double operatorShareOver;

  /// One sentence on what recording does here, when it differs by page.
  final String? intro;

  /// A trip's fare lines with A2Z's 15 % of each, when opened for a trip.
  final List<(String, double)> lines;

  double get operatorShareLeft {
    final left = operatorShareOwed - operatorShareHeld;
    return left > 0.004 ? left : 0;
  }
}

/// What the Cashier entered. [operatorShare] is null when none was given
/// now; [handedOverBy] null means the trip's Dispatcher.
typedef PaymentEntry = ({String amount, String? reference, String? handedOverBy, String? operatorShare});

Future<PaymentEntry?> askPayment(BuildContext context, PaymentFacts facts) =>
    showDialog<PaymentEntry>(context: context, builder: (_) => _RecordPaymentDialog(facts: facts));

class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({required this.facts});
  final PaymentFacts facts;

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  PaymentFacts get f => widget.facts;
  late final _amount = TextEditingController(text: f.amountDue.toStringAsFixed(2));
  late final _share =
      TextEditingController(text: f.operatorShareLeft > 0 ? f.operatorShareLeft.toStringAsFixed(2) : '');
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
    _share.dispose();
    _reference.dispose();
    super.dispose();
  }

  double? get _amountValue => double.tryParse(_amount.text.trim());
  bool get _amountTooMuch => (_amountValue ?? 0) > f.amountDue + 0.004;
  double? get _shareValue => _share.text.trim().isEmpty ? null : double.tryParse(_share.text.trim());
  bool get _shareTooMuch => (_shareValue ?? 0) > f.operatorShareLeft + 0.004;

  bool get _ok {
    final a = _amountValue;
    if (a == null || a <= 0 || _amountTooMuch) return false;
    if (_share.text.trim().isEmpty) return true;
    final s = _shareValue;
    return s != null && s >= 0 && !_shareTooMuch;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final figures = text.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return AlertDialog(
      title: Text('Record payment · ${f.plate}'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (f.intro != null) ...[
              Text(f.intro!, style: text.bodySmall),
              const SizedBox(height: AppSpacing.md),
            ],
            for (final (label, share) in f.lines)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(children: [
                  Expanded(child: Text(label, style: text.bodySmall)),
                  Text(peso.format(share), style: text.bodySmall),
                ]),
              ),
            if (f.lines.isNotEmpty) const Divider(),
            Row(children: [
              Expanded(child: Text('Balance', style: text.titleSmall)),
              Text(peso.format(f.amountDue), style: figures),
            ]),
            if (f.disputed > 0)
              Text('${peso.format(f.disputed)} on this van\'s statement today is under dispute and not due.',
                  style: text.bodySmall?.copyWith(color: AppColors.warning)),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amount,
              onChanged: (_) => setState(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount received',
                prefixText: '₱ ',
                errorText: _amountTooMuch ? 'Only ${peso.format(f.amountDue)} is due.' : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (f.operatorShareLeft > 0)
              TextField(
                controller: _share,
                onChanged: (_) => setState(() {}),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Operator\'s share handed to the operator',
                  prefixText: '₱ ',
                  helperMaxLines: 2,
                  errorMaxLines: 2,
                  helperText: f.operatorShareHeld > 0
                      ? 'Balance ${peso.format(f.operatorShareLeft)} of ${peso.format(f.operatorShareOwed)} '
                          'due today. Leave empty if not yet paid.'
                      : 'Total share ${peso.format(f.operatorShareOwed)}. Leave empty if not yet paid.',
                  errorText: _shareTooMuch
                      ? 'The balance is only ${peso.format(f.operatorShareLeft)}. Enter what was handed over '
                          'just now.'
                      : null,
                ),
              )
            else
              // Given in full, or more: said, not asked again.
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(f.operatorShareOver > 0 ? Icons.info_outline : Icons.check_circle_outline,
                    size: 18, color: f.operatorShareOver > 0 ? AppColors.warning : AppColors.success),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    f.operatorShareOver > 0
                        ? 'Operator\'s share: ${peso.format(f.operatorShareOver)} to come back from the operator. '
                            'Record it on Money when it is handed back.'
                        : 'Operator\'s share: ${peso.format(f.operatorShareHeld)} of '
                            '${peso.format(f.operatorShareOwed)} already paid.',
                    style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                  ),
                ),
              ]),
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
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _ok
              ? () => Navigator.pop<PaymentEntry>(context, (
                    amount: _amountValue!.toStringAsFixed(2),
                    reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
                    handedOverBy: _handedOverBy,
                    operatorShare: _shareValue?.toStringAsFixed(2),
                  ))
              : null,
          child: const Text('Record payment'),
        ),
      ],
    );
  }
}
