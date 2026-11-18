import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/fleet_repository.dart';
import '../../data/repositories/money_repository.dart';
import 'fees_chart.dart';
import 'record_payment_dialog.dart';
import '../setup/step_frame.dart' show PlateTag;
import '../../viewmodels/auth_provider.dart';

/// Remittance (brief 9, replaces Fares & Cash): each van's statement for
/// the day -- income reserved in the app (Booked) and listed as walk-ins
/// (Walk-in), all of it cash; the terminal fees it owes (A2Z's 15 %, the
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
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Money',
            description: 'Each van\'s statement for the day: the terminal fees on its passenger lists '
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
          Expanded(
            child: _loading && _statements == null
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? LoadError(message: _error!, onRetry: _load)
                    // One scroll: the day's statements first -- recording a payment
                    // is the Cashier's job here -- then the history chart.
                    : ListView(children: [
                        if (list.isEmpty)
                          const SizedBox(
                            height: 220,
                            child: EmptyState(
                                icon: Icons.receipt_long_outlined,
                                title: 'No statements on this day',
                                hint: 'A van\'s statement opens with its first listed passenger.'),
                          )
                        else
                          _StatementSheet(statements: list, disputedLines: _disputedLines, onChanged: _load),
                        const SizedBox(height: AppSpacing.xl),
                        const SizedBox(height: AppSpacing.sm),
                        const FeesChart(),
                        const SizedBox(height: AppSpacing.lg),
                      ]),
          ),
        ],
      ),
    );
  }
}

class _StatementPanel extends StatelessWidget {
  const _StatementPanel(
      {required this.statement, required this.disputedLines, required this.onChanged, this.embedded = false});

  final Statement statement;
  final Set<String> disputedLines;
  final VoidCallback onChanged;

  /// Opened under its row in the statement sheet (11 Nov): no header (the
  /// row is it) and no Record payment (the row's own button).
  final bool embedded;

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
        ? StatusBadge('Balance ${peso.format(s.amountDue)}', tone: Tone.warning)
        : s.disputed > 0
            ? const StatusBadge('Disputed share waits', tone: Tone.warning)
            : const StatusBadge('Paid', tone: Tone.success);

    final byTrip = <DateTime, List<StatementLine>>{};
    for (final l in s.lines) {
      byTrip.putIfAbsent(l.tripDeparture, () => []).add(l);
    }

    // The statement read as the office works it out: the fares on the list,
    // what A2Z takes from them, and what is left for the operator. Who
    // recorded each hand-over sits under the group it belongs to.
    final groups = <Widget>[
            _group(context, Icons.groups_outlined, 'Fares on the passenger list', [
              _row(context, 'Booked (B)', s.bookedIncome),
              _row(context, 'Walk-in (W)', s.walkInIncome),
              _row(context, 'Total fares', s.bookedIncome + s.walkInIncome, total: true),
            ]),
            _group(context, Icons.account_balance_outlined, 'Terminal fees', [
              _row(context, 'A2Z\'s ${s.ratePct.toStringAsFixed(0)} %', s.remittanceOwed),
              _row(context, 'DCOTT tickets, ${_trips(s)} × ${peso.format(s.dcottTicketFee)}', s.dcottFees),
              _row(context, 'Parking', s.parkingFee),
              if (s.heldShare > 0) _row(context, 'Held from a trip that left unpaid', s.heldShare),
              _row(context, 'Total fees', s.terminalFeesOwed, total: true),
              _row(context, 'Total paid', s.settledAmount),
              _row(context, 'Balance', s.amountDue, strong: true),
              if (s.disputed > 0) _row(context, 'Disputed', s.disputed),
              if (s.settledAt != null) ...[
                const SizedBox(height: AppSpacing.sm),
                FactLine(Icons.how_to_reg_outlined,
                    'Recorded by ${s.recordedByName ?? 'the Cashier'} at ${_time.format(s.settledAt!)}'
                    '${s.handedOverByName != null ? ', handed over by ${s.handedOverByName}' : ''}'
                    '${s.settlementRef != null ? '. Ref. ${s.settlementRef}' : ''}'),
              ],
            ]),
            _group(context, Icons.person_outline, 'Operator\'s share', [
              _row(context, 'Total share', s.operatorShareOwed),
              _row(context, 'Paid to operator', s.operatorShareGiven),
              if (s.operatorShareReturned > 0) _row(context, 'Handed back', s.operatorShareReturned),
              // Held over the share owed (038), e.g. after a dispute was
              // upheld and its fares left the statement: said at once, in
              // words, with what to do. Not a "difference" to puzzle over.
              if (s.operatorShareOver > 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    StatusBadge('${peso.format(s.operatorShareOver)} to come back', tone: Tone.warning),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'The operator holds more than their share now comes to. The Cashier records it '
                      'when the operator hands it back.',
                      style: text.bodySmall,
                    ),
                  ]),
                ),
              // A warning only: the share is handed between the Dispatcher and
              // the operator, and a difference blocks nothing (T68).
              if (s.operatorShareDiffers && s.operatorShareOver == 0)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: StatusBadge(
                      'Differs by ${peso.format((s.operatorShareDifference ?? 0).abs())}',
                      tone: Tone.warning),
                ),
              if (s.operatorShareGivenAt != null) ...[
                const SizedBox(height: AppSpacing.sm),
                FactLine(Icons.how_to_reg_outlined,
                    'Recorded by ${s.operatorShareRecordedByName ?? 'the Cashier'} '
                    'at ${_time.format(s.operatorShareGivenAt!)}'),
              ],
              if (s.operatorShareReturnedAt != null)
                FactLine(Icons.undo,
                    'Handed back, recorded by ${s.operatorShareReturnedByName ?? 'the Cashier'} '
                    'at ${_time.format(s.operatorShareReturnedAt!)}'),
            ]),
    ];
    final lines = <Widget>[
          if (byTrip.isNotEmpty) ...[
            if (!embedded) const SizedBox(height: AppSpacing.xl),
            Text('Fare lines by trip, drop-off and group', style: text.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            _LineRow.head(context, s.ratePct),
            for (final entry in byTrip.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
                child: Text('${_time.format(entry.key)} trip',
                    style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              for (final l in entry.value)
                _LineRow(line: l, disputed: disputedLines.contains(l.lineId), canDispute: records,
                    onChanged: onChanged),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
    ];
    final Widget? buttons = !cashier
        ? null
        : Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: AppSpacing.sm, children: [
                // Only while some of it is still to give: the amounts add
                // up, so a second entry of a share already given would
                // count it twice (10 Nov).
                if (s.operatorShareOver > 0)
                  OutlinedButton.icon(
                    onPressed: () => _shareReturned(context),
                    icon: const Icon(Icons.undo, size: 18),
                    label: Text('Record ${peso.format(s.operatorShareOver)} handed back'),
                  ),
                if (s.operatorShareLeft > 0)
                  OutlinedButton.icon(
                  onPressed: () => _operatorShare(context),
                  icon: const Icon(Icons.person_outline, size: 18),
                  label: const Text('Record operator\'s share'),
                ),
                if (s.amountDue > 0 && !embedded)
                  FilledButton.icon(
                    onPressed: () => _pay(context),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Record payment'),
                  ),
              ]),
            );
    if (embedded) {
      // The reference's statement card: the fare lines on the left, the
      // fees worked out on the right with the hand-over buttons.
      final box = Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (i, g) in groups.indexed) ...[if (i > 0) const Divider(height: AppSpacing.xl), g],
          if (buttons != null) ...[const SizedBox(height: AppSpacing.lg), buttons],
        ]),
      );
      final Widget left = lines.isEmpty
          ? _NoFares(trips: _trips(s), owed: s.dcottFees + s.parkingFee)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: lines);
      // Side by side, the two halves are one height (12 Nov, the owner's
      // screenshot: a short empty-state box beside the tall fees box read
      // as lopsided): the shorter one stretches to the taller, and the
      // empty state centres its words in the space.
      return LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 900
            ? IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Equal halves as well as one height (12 Nov).
                  Expanded(child: left),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(child: box),
                ]),
              )
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [box, const SizedBox(height: AppSpacing.lg), left]),
      );
    }
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Columns(children: groups),
      ...lines,
      ?buttons,
    ]);
    return Panel(
      title: '${s.plateNumber} · ${s.operatorName}',
      icon: Icons.receipt_long_outlined,
      trailing: badge,
      child: body,
    );
  }

  static int _trips(Statement s) => s.dcottTicketFee > 0 ? (s.dcottFees / s.dcottTicketFee).round() : 0;

  Widget _group(BuildContext context, IconData icon, String title, List<Widget> rows) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(title, style: Theme.of(context).textTheme.labelLarge)),
        ]),
        const SizedBox(height: AppSpacing.sm),
        ...rows,
      ]);

  /// A ledger line: label left, amount right in tabular figures. A total
  /// takes a rule above it and the heavy weight; [strong] only the weight.
  Widget _row(BuildContext context, String label, double value, {bool total = false, bool strong = false}) {
    final text = Theme.of(context).textTheme;
    final heavy = total || strong;
    final line = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Expanded(
          child: Text(label,
              style: heavy ? text.bodyMedium?.copyWith(fontWeight: FontWeight.w700) : text.bodyMedium),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(peso.format(value),
            style: text.bodyMedium?.copyWith(
                fontWeight: heavy ? FontWeight.w700 : null,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
    return total
        ? Column(children: [const Divider(height: AppSpacing.sm), line])
        : line;
  }

  /// A difference in the operator's share, handed over after the payment.
  Future<void> _operatorShare(BuildContext context) async {
    final money = context.read<MoneyRepository>();
    final left = statement.operatorShareLeft;
    final amount = await askText(
      context,
      title: 'Record operator\'s share · ${statement.plateNumber}',
      intro: 'Total share ${peso.format(statement.operatorShareOwed)}, paid so far '
          '${peso.format(statement.operatorShareHeld)}'
          '${left > 0 ? ', balance ${peso.format(left)}' : ''}. Enter what the Dispatcher has just '
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
    if (value > left + 0.004) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('The operator\'s share has a balance of only ${peso.format(left)}. '
              'Amounts add up, so enter only what was handed over just now.')));
      return;
    }
    if (await runAction(context, () => money.recordOperatorShare(statement.remittanceId, value.toStringAsFixed(2)),
        'Operator\'s share recorded for ${statement.plateNumber}.')) {
      onChanged();
    }
  }

  Future<void> _shareReturned(BuildContext context) async {
    final money = context.read<MoneyRepository>();
    final over = statement.operatorShareOver;
    final amount = await askText(
      context,
      title: 'Record share handed back · ${statement.plateNumber}',
      intro: 'The operator holds ${peso.format(statement.operatorShareHeld)} of a share that now comes to '
          '${peso.format(statement.operatorShareOwed)}: ${peso.format(over)} more than is theirs, for '
          'example after a dispute was upheld. Enter what the operator has just handed back.',
      label: 'Amount handed back (₱)',
      initial: over.toStringAsFixed(2),
      confirmLabel: 'Record',
      maxLength: 12,
    );
    if (amount == null || !context.mounted) return;
    final value = double.tryParse(amount.trim());
    if (value == null || value <= 0 || value > over + 0.004) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Enter an amount above zero and no more than ${peso.format(over)}.')));
      return;
    }
    if (await runAction(context, () => money.recordShareReturned(statement.remittanceId, value.toStringAsFixed(2)),
        'Share handed back recorded for ${statement.plateNumber}.')) {
      onChanged();
    }
  }

  Future<void> _pay(BuildContext context) async {
    final money = context.read<MoneyRepository>();
    final s = statement;
    final entry = await askPayment(
        context,
        PaymentFacts(
          plate: s.plateNumber,
          amountDue: s.amountDue,
          disputed: s.disputed,
          operatorShareOwed: s.operatorShareOwed,
          operatorShareHeld: s.operatorShareHeld,
          operatorShareOver: s.operatorShareOver,
        ));
    if (entry == null || !context.mounted) return;
    final ok = await runAction(
      context,
      () => money.pay(s.remittanceId,
          amount: entry.amount, reference: entry.reference, handedOverBy: entry.handedOverBy,
          operatorShare: entry.operatorShare),
      'Payment recorded for ${s.plateNumber}.',
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

  static const _groupWidth = 92.0;

  static const _amountWidth = 110.0;
  static const _actionWidth = 150.0;
  static const _tabular = [FontFeature.tabularFigures()];

  /// The table's head: every column named once, on a light header row.
  static Widget head(BuildContext context, double ratePct) {
    final head = Theme.of(context).textTheme.labelMedium;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(children: [
        SizedBox(width: _groupWidth, child: Text('Group', style: head)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text('Passengers, fare and drop-off', style: head)),
        SizedBox(width: _amountWidth, child: Text('Fares', textAlign: TextAlign.right, style: head)),
        SizedBox(width: _amountWidth, child: Text('A2Z\'s ${ratePct.toStringAsFixed(0)} %',
            textAlign: TextAlign.right, style: head)),
        const SizedBox(width: _actionWidth),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = line;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
      child: Row(children: [
        SizedBox(width: _groupWidth, child: Align(alignment: Alignment.centerLeft,
            child: StatusBadge(l.incomeGroup == 'booked' ? 'Booked' : 'Walk-in',
                tone: l.incomeGroup == 'booked' ? Tone.info : Tone.neutral))),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text('${l.count} × ${peso.format(l.fare)} to ${l.destination}'
              '${l.isTopUp ? '  · top-up' : ''}', style: text.bodyMedium),
        ),
        SizedBox(width: _amountWidth, child: Text(peso.format(l.gross), textAlign: TextAlign.right,
            style: text.bodyMedium?.copyWith(fontFeatures: _tabular))),
        SizedBox(width: _amountWidth, child: Text(peso.format(l.share), textAlign: TextAlign.right,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontFeatures: _tabular))),
        SizedBox(
          width: _actionWidth,
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

/// Equal columns across the panel with a rule between them; stacked on a
/// narrow window.
class _Columns extends StatelessWidget {
  const _Columns({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 760) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, w) in children.indexed) ...[
              if (i > 0) const Divider(height: AppSpacing.xxl),
              w,
            ],
          ]);
        }
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, w) in children.indexed) ...[
              if (i > 0) const VerticalDivider(width: AppSpacing.xxxl),
              Expanded(child: w),
            ],
          ]),
        );
      });
}

// ------------------------------------------------------ statement sheet
// Column widths; the next-step column takes the rest.
const double _cVan = 140, _cOp = 190, _cFares = 150, _cFees = 150, _cDue = 124, _cShare = 176;
const double _sheetMin = 1120;
final _whole = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 0);
const _tabular = [FontFeature.tabularFigures()];

/// The day's van statements as one sheet (11 Nov), like the paper trip
/// ticket: a row a van with its fares, terminal fees, what is due now and
/// the operator's share, all added up from the trips; the Cashier records
/// only the cash, with the row's **Record payment**. A click on a row
/// opens its statement underneath: the fees line by line, the fare lines
/// (disputes start there) and the operator's-share buttons. "Money due"
/// narrows the sheet to the vans the counter still waits for.
class _StatementSheet extends StatefulWidget {
  const _StatementSheet({required this.statements, required this.disputedLines, required this.onChanged});
  final List<Statement> statements;
  final Set<String> disputedLines;
  final VoidCallback onChanged;

  @override
  State<_StatementSheet> createState() => _StatementSheetState();
}

class _StatementSheetState extends State<_StatementSheet> {
  String _query = '';
  bool _dueOnly = false;

  /// The van whose statement is in the card above the ledger.
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final role = context.read<AuthProvider>().profile?.role;
    final cashier = role?.isCashier ?? false;
    final all = widget.statements;
    final dueCount = all.where((s) => s.amountDue > 0).length;
    final q = _query.trim().toLowerCase();
    final rows = all
        .where((s) => !_dueOnly || s.amountDue > 0)
        .where((s) => q.isEmpty || s.plateNumber.toLowerCase().contains(q) || s.operatorName.toLowerCase().contains(q))
        .toList();
    // The statement shown above: the one clicked, else the first that owes,
    // else the first.
    final selected = rows.where((s) => s.remittanceId == _selected).firstOrNull ??
        rows.where((s) => s.amountDue > 0).firstOrNull ??
        rows.firstOrNull;
    final head = text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.2);
    Widget auto(String label, double w) => SizedBox(
          width: w,
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text(label, style: head),
            const SizedBox(width: 4),
            Tooltip(
                message: 'Adds itself up from the trips',
                child: Text('ƒx', style: head?.copyWith(color: AppColors.primary, fontStyle: FontStyle.italic))),
          ]),
        );

    final table = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider), bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(children: [
          SizedBox(width: _cVan, child: Text('Van', style: head)),
          SizedBox(width: _cOp, child: Text('Operator', style: head)),
          auto('Fares', _cFares),
          auto('Terminal fees', _cFees),
          SizedBox(width: _cDue, child: Text('Balance', style: head, textAlign: TextAlign.right)),
          SizedBox(width: _cShare, child: Text('Operator\'s share', style: head, textAlign: TextAlign.right)),
          Expanded(child: Text('Next step', style: head, textAlign: TextAlign.right)),
          const SizedBox(width: 40),
        ]),
      ),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(
              _dueOnly && q.isEmpty ? 'No van has a balance now.' : 'No van matches "$_query".',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
        ),
      for (final s in rows)
        _VanRow(
          statement: s,
          open: s.remittanceId == selected?.remittanceId,
          cashier: cashier,
          onToggle: () => setState(() => _selected = s.remittanceId),
          onPay: () => _StatementPanel(statement: s, disputedLines: widget.disputedLines, onChanged: widget.onChanged)
              ._pay(context),
        ),
      if (rows.isNotEmpty) _SheetTotal(rows: rows),
    ]);

    final ledger = Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Daily van statements', style: text.titleMedium),
                const SizedBox(width: AppSpacing.lg),
                ChoiceChip(
                  label: Text('All vans (${all.length})'),
                  selected: !_dueOnly,
                  onSelected: (_) => setState(() => _dueOnly = false),
                ),
                const SizedBox(width: AppSpacing.sm),
                ChoiceChip(
                  label: Text('Money due ($dueCount)'),
                  selected: _dueOnly,
                  onSelected: (_) => setState(() => _dueOnly = true),
                ),
              ]),
              SizedBox(
                width: 280,
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                      isDense: true, hintText: 'Search plate or operator', prefixIcon: Icon(Icons.search, size: 18)),
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= _sheetMin
              ? table
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal, child: SizedBox(width: _sheetMin, child: table)),
        ),
      ]),
    );
    final st = selected;
    if (st == null) return ledger;
    // Its trips are counted from the DCOTT tickets, not the fare lines: a
    // trip with nobody listed yet still owes its ticket, and is not
    // "parking only".
    final listed = st.lines.map((l) => l.tripId).toSet().length;
    final ticketed = _StatementPanel._trips(st);
    final trips = listed > ticketed ? listed : ticketed;
    // The selected van's statement, as the reference shows it: what it is,
    // then the fare lines beside the fees worked out.
    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.edge, width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(6)),
                child: Text('STATEMENT · ${st.plateNumber}',
                    style: text.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 0.6, fontSize: 11)),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('${st.operatorName}, ${trips == 0 ? 'parking only' : '$trips trip${trips == 1 ? '' : 's'} today'}',
                  style: text.titleLarge),
            ]),
            Wrap(spacing: AppSpacing.sm, children: [
              if (st.disputed > 0)
                StatusBadge('${peso.format(st.disputed)} disputed, waiting', tone: Tone.warning),
              st.amountDue > 0
                  ? StatusBadge('Balance ${peso.format(st.amountDue)}', tone: Tone.warning)
                  : StatusBadge('Total paid ${peso.format(st.settledAmount)}', tone: Tone.success),
            ]),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const Divider(),
        const SizedBox(height: AppSpacing.md),
        _StatementPanel(
            statement: st, disputedLines: widget.disputedLines, onChanged: widget.onChanged, embedded: true),
      ]),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      card,
      const SizedBox(height: AppSpacing.xl),
      ledger,
    ]);
  }
}

class _VanRow extends StatefulWidget {
  const _VanRow(
      {required this.statement, required this.open, required this.cashier, required this.onToggle, required this.onPay});
  final Statement statement;
  final bool open;
  final bool cashier;
  final VoidCallback onToggle;
  final VoidCallback onPay;

  @override
  State<_VanRow> createState() => _VanRowState();
}

class _VanRowState extends State<_VanRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.statement;
    final text = Theme.of(context).textTheme;
    final fig = text.bodyMedium?.copyWith(fontFeatures: _tabular);
    final small = text.bodySmall?.copyWith(fontFeatures: _tabular);
    // As on the statement card: a trip with nobody listed yet still has
    // its DCOTT ticket, so it counts (12 Nov UI run: "Parking only" here).
    final listed = s.lines.map((l) => l.tripId).toSet().length;
    final ticketed = _StatementPanel._trips(s);
    final trips = listed > ticketed ? listed : ticketed;
    Widget two(String top, String? under, {TextStyle? topStyle, TextStyle? underStyle, bool right = true}) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(top, style: topStyle ?? fig, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (under != null) Text(under, style: underStyle ?? small, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        );

    final Widget next;
    if (s.amountDue > 0) {
      next = widget.cashier
          ? FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 16)),
              onPressed: widget.onPay,
              child: const Text('Record payment'))
          : Text('Waiting for the Cashier', style: text.bodySmall);
    } else if (s.disputed > 0) {
      next = Text('Disputed share waits', style: text.bodySmall?.copyWith(color: AppColors.warning));
    } else {
      next = Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle, size: 15, color: AppColors.success),
        const SizedBox(width: 6),
        Text('Paid in full', style: text.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600)),
      ]);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: widget.open ? AppColors.primaryContainer : AppColors.surfaceRaised,
        child: InkWell(
          onTap: widget.onToggle,
          hoverColor: widget.open ? AppColors.pressWash : AppColors.hoverWash,
          // The record rows' hover: the wash and the emerald bar at the
          // left; the van shown above keeps the bar and the soft tint.
          child: AnimatedContainer(
            duration: AppDuration.quick,
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.surfaceSunken))),
            foregroundDecoration: BoxDecoration(
                border: Border(left: _hover || widget.open ? const BorderSide(color: AppColors.accent, width: 3) : BorderSide.none)),
            child: Row(children: [
              SizedBox(width: _cVan, child: Align(alignment: Alignment.centerLeft, child: PlateTag(s.plateNumber))),
              SizedBox(
                width: _cOp,
                child: two(s.operatorName, trips == 0 ? 'Parking only' : '$trips trip${trips == 1 ? '' : 's'}',
                    right: false),
              ),
              SizedBox(
                width: _cFares,
                child: two(peso.format(s.bookedIncome + s.walkInIncome),
                    'B ${_whole.format(s.bookedIncome)}   W ${_whole.format(s.walkInIncome)}'),
              ),
              SizedBox(
                width: _cFees,
                child: two(peso.format(s.terminalFeesOwed + s.heldShare), 'paid ${peso.format(s.settledAmount)}'),
              ),
              SizedBox(
                width: _cDue,
                child: two(
                  peso.format(s.amountDue),
                  s.disputed > 0 ? '${_whole.format(s.disputed)} disputed' : null,
                  topStyle: fig?.copyWith(
                      fontWeight: s.amountDue > 0 ? FontWeight.w700 : FontWeight.w400,
                      color: s.amountDue > 0 ? AppColors.warning : AppColors.textMuted),
                  underStyle: small?.copyWith(color: AppColors.warning),
                ),
              ),
              SizedBox(
                width: _cShare,
                child: two(
                  peso.format(s.operatorShareHeld),
                  s.operatorShareOver > 0
                      ? '${peso.format(s.operatorShareOver)} to come back'
                      : 'of ${peso.format(s.operatorShareOwed)} paid',
                  underStyle: s.operatorShareOver > 0 ? small?.copyWith(color: AppColors.warning) : small,
                ),
              ),
              Expanded(child: Align(alignment: Alignment.centerRight, child: next)),
              SizedBox(
                width: 40,
                child: Icon(widget.open ? Icons.expand_less : Icons.expand_more,
                    size: 20, color: _hover || widget.open ? AppColors.textPrimary : AppColors.disabled),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SheetTotal extends StatelessWidget {
  const _SheetTotal({required this.rows});
  final List<Statement> rows;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: _tabular);
    double sum(double Function(Statement) f) => rows.fold(0, (n, x) => n + f(x));
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      color: AppColors.surface,
      child: Row(children: [
        SizedBox(width: _cVan + _cOp, child: Text('Total, ${rows.length} van${rows.length == 1 ? '' : 's'}', style: s)),
        SizedBox(
            width: _cFares,
            child: Text(peso.format(sum((x) => x.bookedIncome + x.walkInIncome)), style: s, textAlign: TextAlign.right)),
        SizedBox(
            width: _cFees,
            child: Text(peso.format(sum((x) => x.terminalFeesOwed + x.heldShare)), style: s, textAlign: TextAlign.right)),
        SizedBox(width: _cDue, child: Text(peso.format(sum((x) => x.amountDue)), style: s, textAlign: TextAlign.right)),
        SizedBox(
            width: _cShare,
            child: Text(peso.format(sum((x) => x.operatorShareHeld)), style: s, textAlign: TextAlign.right)),
        const Spacer(),
      ]),
    );
  }
}

/// The statement's left side when no fare is listed: what is owed anyway,
/// in words, so the empty space says something (11 Nov).
class _NoFares extends StatelessWidget {
  const _NoFares({required this.trips, required this.owed});
  final int trips;
  final double owed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
    final (title, line) = trips == 0
        ? ('No trip today: a parking-only charge',
            'The van stood at the terminal, so the day\'s parking is due: ${peso.format(owed)}.')
        : ('No passengers listed yet',
            '${trips == 1 ? 'Its trip' : 'Its $trips trips'} ${trips == 1 ? 'has' : 'have'} the DCOTT '
                'ticket${trips == 1 ? '' : 's'} and the day\'s parking to pay: ${peso.format(owed)}. The fares appear here '
                'as the Dispatcher lists passengers.');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xxxl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle),
          child: Icon(trips == 0 ? Icons.local_parking_outlined : Icons.groups_outlined, color: AppColors.primary),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(title, style: text.titleSmall, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.xs),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(line, style: text.bodySmall, textAlign: TextAlign.center),
        ),
      ]),
    );
  }
}
