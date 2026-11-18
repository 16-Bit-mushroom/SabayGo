import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/layout/console_router.dart';
import '../../core/layout/review_counts.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/money_repository.dart';
import '../../viewmodels/auth_provider.dart';

/// Today at a glance, above the Overview map (10 Nov, from the owner's
/// reference dashboard, mapped onto what SabayGo actually records):
///
///   * **Today's trips** -- a donut of the day's trips by status, from the
///     trip board. Counts, not estimates.
///   * **Needs you today** -- what waits on a decision, from the same
///     review counts the menu shows, each row opening its page. A count
///     that did not load says so; it is never shown as zero.
///   * **Terminal fees today** -- total paid of the total fees on today's
///     statements.
///
/// 12 Nov: the three cards are one size -- equal widths, one fixed height,
/// [_cardHeight] -- and compact, so the map below gets the page (the owner:
/// "too big ... lots of white space"). The fee breakdown moved behind the
/// (i) on its card.
///
/// Nothing here is a score, a growth rate or a forecast: the system holds
/// none, and a number it does not have would be invented.
class TodayPanel extends StatefulWidget {
  const TodayPanel({super.key});

  @override
  State<TodayPanel> createState() => _TodayPanelState();
}

/// One height for all three cards on a wide page.
const double _cardHeight = 172;

class _TodayPanelState extends State<TodayPanel> {
  static const _refreshEvery = Duration(seconds: 30);
  List<TripBoardEntry>? _trips;
  List<Statement>? _statements;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refreshEvery, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final dispatch = context.read<DispatchRepository>();
    final money = context.read<MoneyRepository>();
    Future<T?> attempt<T>(Future<T> f) => f.then<T?>((v) => v).catchError((_) => null);
    final r = await Future.wait([
      attempt(dispatch.tripBoard(DateTime.now())),
      attempt(money.statements(isoDay(DateTime.now()))),
    ]);
    if (!mounted) return;
    setState(() {
      _trips = r[0] as List<TripBoardEntry>?;
      _statements = r[1] as List<Statement>?;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _statements;
    final owed = s?.fold<double>(0, (a, x) => a + x.terminalFeesOwed + x.heldShare);
    final due = s?.fold<double>(0, (a, x) => a + x.amountDue);
    final go = context.read<ConsoleLocation>().go;
    return LayoutBuilder(builder: (context, c) {
      final trips = ClickableCard(
        onTap: () => go('/trips/trips'),
        label: 'Today\'s trips: ${_trips?.length ?? 'not loaded'}. Opens Trips.',
        child: _TripsDonut(trips: _trips),
      );
      final needs = _NeedsYou(due: due);
      final fees = ClickableCard(
        onTap: () => go('/money'),
        label: 'Terminal fees today: ${owed == null ? 'not loaded' : peso.format(owed)}. Opens Money.',
        child: _FeesToday(statements: s),
      );
      if (c.maxWidth < 900) {
        // Stacked, still one height each: the cards lay out against it.
        Widget sized(Widget w) => SizedBox(height: _cardHeight, child: w);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          sized(trips),
          const SizedBox(height: AppSpacing.md),
          sized(needs),
          const SizedBox(height: AppSpacing.md),
          sized(fees),
        ]);
      }
      return SizedBox(
        height: _cardHeight,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: trips),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: needs),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: fees),
        ]),
      );
    });
  }
}

// ---------------------------------------------------------------- donut
class _TripsDonut extends StatelessWidget {
  const _TripsDonut({required this.trips});
  final List<TripBoardEntry>? trips;

  /// Status, its words, and its shade: light for what has not left yet,
  /// darker as the day's work is done; cancelled is grey.
  static const _states = [
    ('scheduled', 'Scheduled', AppRamp.n200),
    ('boarding', 'Boarding', AppColors.edge),
    ('departed', 'On the road', AppColors.accent),
    ('completed', 'Arrived', AppColors.primary),
    ('cancelled', 'Cancelled', AppColors.disabled),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = trips;
    final counts = [for (final s in _states) t?.where((x) => x.status == s.$1).length ?? 0];
    final total = t?.length;
    return Panel(
      title: 'Today\'s trips',
      icon: Icons.donut_large_outlined,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
      trailing: const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
      child: t == null
          ? Text('The trips did not load. They come back on the next refresh.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted))
          : Row(children: [
              Semantics(
                label: '$total trips today: '
                    '${[for (var i = 0; i < _states.length; i++) if (counts[i] > 0) '${counts[i]} ${_states[i].$2.toLowerCase()}'].join(', ')}',
                child: ExcludeSemantics(
                  child: SizedBox(
                    width: 104,
                    height: 104,
                    child: CustomPaint(
                      painter: _DonutPainter([for (var i = 0; i < _states.length; i++) (counts[i], _states[i].$3)]),
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('$total',
                              style: const TextStyle(
                                  fontFamily: 'PlusJakartaSans', fontSize: 24, fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          Text(total == 1 ? 'trip' : 'trips', style: text.bodySmall),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < _states.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1),
                      child: Row(children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _states[i].$3,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: AppColors.border.withValues(alpha: 0.4)),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(_states[i].$2, style: text.bodySmall?.copyWith(color: AppColors.textPrimary))),
                        Text('${counts[i]}',
                            style: text.bodySmall?.copyWith(color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()])),
                      ]),
                    ),
                ]),
              ),
            ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.parts);
  final List<(int, Color)> parts;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 13.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final total = parts.fold<int>(0, (a, p) => a + p.$1);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.surfaceSunken;
    canvas.drawArc(arc, 0, 2 * math.pi, false, track);
    if (total == 0) return;
    // A hairline gap between segments, so two neighbouring shades still read
    // as two.
    const gap = 0.03;
    var start = -math.pi / 2;
    for (final (n, colour) in parts) {
      if (n == 0) continue;
      final sweep = 2 * math.pi * n / total;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = colour;
      canvas.drawArc(arc, start + (sweep > gap * 2 ? gap / 2 : 0), sweep > gap * 2 ? sweep - gap : sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.parts != parts;
}

// ---------------------------------------------------------- needs you
class _NeedsYou extends StatelessWidget {
  const _NeedsYou({required this.due});

  /// Terminal fees still due on today's statements; null when not loaded.
  final double? due;

  @override
  Widget build(BuildContext context) {
    final r = context.watch<ReviewCounts>();
    final manager = context.read<AuthProvider>().profile?.role.isManager ?? false;
    final go = context.read<ConsoleLocation>().go;
    final cells = <Widget>[
      if (manager) ...[
        _Need(Icons.play_circle_outline, 'Review Starts', r.starts, () => go('/reviews/review-starts')),
        _Need(Icons.fact_check_outlined, 'Boarding Audit', r.boardings, () => go('/reviews/boarding-audit')),
      ],
      _Need(Icons.speed_outlined, 'Driving Flags', r.flags, () => go('/reviews/driving-flags')),
      _Need(Icons.gavel_outlined, 'Disputes', r.disputes, () => go('/reviews/disputes')),
      _Need(Icons.chat_bubble_outline, 'Messages', r.messages, () => go('/messages'), noun: 'unread'),
      _Need(Icons.payments_outlined, 'Balance', due == null ? null : (due! > 0 ? 1 : 0), () => go('/money'),
          waiting: due != null && due! > 0 ? peso.format(due) : null),
    ];
    // Two columns: six things in three short rows, so the card is as tall
    // as its neighbours and every row is still a whole-width target.
    final rows = <Widget>[
      for (var k = 0; k < cells.length; k += 2)
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: cells[k]),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: k + 1 < cells.length ? cells[k + 1] : const SizedBox.shrink()),
          ]),
        ),
    ];
    return Panel(
      title: 'Needs you today',
      icon: Icons.checklist_outlined,
      info: 'What waits on a decision. A green check means nothing is waiting; a number in ochre is '
          'how many wait. Click one to open its page.',
      fill: true,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }
}

/// One thing that may wait on a decision: done (a green check), waiting
/// (an ochre count), or not loaded (a grey ?, and said in its tooltip).
class _Need extends StatefulWidget {
  const _Need(this.icon, this.label, this.count, this.onOpen, {this.noun = 'waiting', this.waiting});
  final IconData icon;
  final String label;
  final int? count;
  final VoidCallback onOpen;
  final String noun;

  /// Overrides the count when it is an amount.
  final String? waiting;

  @override
  State<_Need> createState() => _NeedState();
}

class _NeedState extends State<_Need> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final n = widget.count;
    final String status = n == null
        ? 'not loaded'
        : n == 0
            ? 'nothing waiting'
            : widget.waiting ?? '$n ${widget.noun}';
    final Widget mark = n == null
        ? const Icon(Icons.help_outline, size: 18, color: AppColors.textMuted)
        : n == 0
            ? const Icon(Icons.check_circle, size: 18, color: AppColors.primary)
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                    color: AppColors.warningContainer, borderRadius: BorderRadius.circular(AppRadius.full)),
                child: Text(widget.waiting ?? '$n',
                    style: text.labelMedium?.copyWith(color: AppColors.warning, fontWeight: FontWeight.w800)),
              );
    return Tooltip(
      message: '${widget.label}: $status',
      excludeFromSemantics: true, // the Semantics label below says it once
      waitDuration: const Duration(milliseconds: 400),
      child: Semantics(
        button: true,
        label: '${widget.label}: $status',
        excludeSemantics: true,
        child: FocusRing(
          child: Material(
            color: _hover ? AppColors.hoverWash : AppColors.surfaceSunken.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: widget.onOpen,
              onHover: (h) => setState(() => _hover = h),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(children: [
                  Icon(widget.icon, size: 16, color: n != null && n > 0 ? AppColors.warning : AppColors.textMuted),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  mark,
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Terminal fees today, as the reference's tinted card: the day's total,
/// what is still to hand over (and what waits on a dispute), the three
/// fees it is made of, and the share paid so far. From today's van
/// statements; "Not loaded" when they did not load, never a zero.
class _FeesToday extends StatelessWidget {
  const _FeesToday({required this.statements});
  final List<Statement>? statements;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = statements;
    double sum(double Function(Statement) f) => s == null ? 0 : s.fold<double>(0, (a, x) => a + f(x));
    final owed = sum((x) => x.terminalFeesOwed + x.heldShare);
    final paid = sum((x) => x.settledAmount);
    final due = sum((x) => x.amountDue);
    final disputed = sum((x) => x.disputed);
    final share = sum((x) => x.remittanceOwed + x.heldShare);
    final dcott = sum((x) => x.dcottFees);
    final parking = sum((x) => x.parkingFee);
    final pct = owed > 0 ? (paid / owed).clamp(0.0, 1.0) : 0.0;
    final fig = const [FontFeature.tabularFigures()];
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryContainer, Color(0xFFCFF7DD)],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.edge),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.account_balance_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: Text('Terminal fees today', style: text.titleSmall)),
          const SizedBox(width: AppSpacing.xs),
          if (s != null)
            InfoTip(
                'Made of: A2Z\'s 15 % of the fares ${peso.format(share)}, DCOTT tickets (₱75 a trip) '
                '${peso.format(dcott)}, parking (₱50 a van a day) ${peso.format(parking)}.',
                size: 16),
          const Spacer(),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
        ]),
        const Spacer(),
        Text(s == null ? 'Not loaded' : peso.format(owed),
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, fontFeatures: fig)),
        if (s != null)
          Text(
            '${due > 0 ? 'Balance ${peso.format(due)}' : 'No balance now'}'
            '${disputed > 0 ? ' · ${peso.format(disputed)} disputed' : ''}',
            style: text.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
          ),
        const Spacer(),
        if (s != null) ...[
          Row(children: [
            Expanded(
                child: Text('Total paid ${peso.format(paid)}',
                    style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
            Text('${(pct * 100).round()} %',
                style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: AppColors.surfaceRaised,
              color: AppColors.accent,
              semanticsLabel: 'Terminal fees paid',
              semanticsValue: '${(pct * 100).round()} percent',
            ),
          ),
        ],
      ]),
    );
  }
}
