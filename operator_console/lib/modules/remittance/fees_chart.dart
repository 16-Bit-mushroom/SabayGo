import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../data/repositories/money_repository.dart';

/// Terminal fees recorded over the last 7 days, 30 days or year, from
/// `GET /statements/history` (10 Nov, the owner's reference chart mapped
/// onto Money): bars for the terminal fees owed, a line for what was paid.
/// Hovering or tapping a period shows its figures in the strip above.
///
/// Recorded sums only. There is no trend line, no forecast and no growth
/// percentage: the system records what was owed and paid, nothing more,
/// and a projected number would be an invented one.
class FeesChart extends StatefulWidget {
  const FeesChart({super.key});

  @override
  State<FeesChart> createState() => _FeesChartState();
}

enum _Range {
  week(7, false, '7D', 'last 7 days'),
  month(30, false, '30D', 'last 30 days'),
  year(365, true, '1Y', 'last 12 months');

  const _Range(this.days, this.byMonth, this.label, this.words);
  final int days;
  final bool byMonth;
  final String label;
  final String words;
}

class _FeesChartState extends State<FeesChart> {
  _Range _range = _Range.week;
  List<FeePeriod>? _periods;
  String? _error;
  int? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await context.read<MoneyRepository>().history(days: _range.days, byMonth: _range.byMonth);
      if (!mounted) return;
      setState(() {
        _periods = p;
        _selected = p.isEmpty ? null : p.length - 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'The history did not load. Refresh to try again.');
    }
  }

  String _name(DateTime d) => _range.byMonth ? DateFormat.yMMMM().format(d) : DateFormat.yMMMEd().format(d);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = _periods;
    final sel = (p != null && _selected != null && _selected! < p.length) ? p[_selected!] : null;
    return Panel(
      title: 'Terminal fees recorded',
      icon: Icons.bar_chart_rounded,
      trailing: SegmentedButton<_Range>(
        showSelectedIcon: false,
        segments: [for (final r in _Range.values) ButtonSegment(value: r, label: Text(r.label), tooltip: r.words)],
        selected: {_range},
        onSelectionChanged: (s) {
          setState(() {
            _range = s.first;
            _periods = null;
          });
          _load();
        },
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: AppSpacing.lg, runSpacing: AppSpacing.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('The ${_range.words}. Hover or tap a ${_range.byMonth ? 'month' : 'day'} to see its figures.',
              style: text.bodySmall),
          const _Key(bar: true, label: 'Total fees'),
          const _Key(bar: false, label: 'Paid'),
        ]),
        const SizedBox(height: AppSpacing.md),
        if (sel != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: _name(sel.period), style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: '   Total fees ${peso.format(sel.terminalFees)}   Total paid ${peso.format(sel.paid)}   '
                      'Fares on the lists ${peso.format(sel.fares)}'),
                ]), style: text.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              ),
              if (sel.terminalFees > 0)
                StatusBadge('${(math.min(sel.paid / sel.terminalFees, 1) * 100).round()} % paid',
                    tone: sel.paid >= sel.terminalFees ? Tone.success : Tone.warning),
            ]),
          ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 230,
          child: _error != null
              ? Center(child: Text(_error!, style: text.bodyMedium?.copyWith(color: AppColors.danger)))
              : p == null
                  ? const Center(child: CircularProgressIndicator())
                  : _plot(context, p),
        ),
      ]),
    );
  }

  Widget _plot(BuildContext context, List<FeePeriod> p) {
    final top = p.fold<double>(0, (a, x) => math.max(a, math.max(x.terminalFees, x.paid)));
    final total = p.fold<double>(0, (a, x) => a + x.terminalFees);
    final paid = p.fold<double>(0, (a, x) => a + x.paid);
    final painter = _ChartPainter(
      periods: p,
      selected: _selected,
      byMonth: _range.byMonth,
    );
    return Semantics(
      label: 'Terminal fees recorded over the ${_range.words}: ${peso.format(total)} in total fees, ${peso.format(paid)} paid.',
      child: Stack(children: [
        Positioned.fill(
          child: LayoutBuilder(builder: (context, c) {
            int? at(Offset o) {
              final i = painter.indexAt(o, c.biggest);
              return i;
            }

            return MouseRegion(
              onHover: (e) {
                final i = at(e.localPosition);
                if (i != null && i != _selected) setState(() => _selected = i);
              },
              child: GestureDetector(
                onTapDown: (e) {
                  final i = at(e.localPosition);
                  if (i != null) setState(() => _selected = i);
                },
                child: CustomPaint(painter: painter, size: c.biggest),
              ),
            );
          }),
        ),
        if (top == 0)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceRaised,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.divider),
              ),
              child: Text('No terminal fees were recorded in the ${_range.words}.',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
      ]),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.bar, required this.label});
  final bool bar;
  final String label;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        bar
            ? Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [AppColors.accent, AppColors.edge]),
                  borderRadius: BorderRadius.circular(3),
                ),
              )
            : Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 2.5),
                ),
              ),
        const SizedBox(width: AppSpacing.xs + 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600,
            color: AppColors.textPrimary)),
      ]);
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({required this.periods, required this.selected, required this.byMonth});
  final List<FeePeriod> periods;
  final int? selected;
  final bool byMonth;

  static const _left = 56.0;
  static const _bottom = 24.0;
  static const _topPad = 10.0;

  /// A round ceiling for the axis: 1, 2 or 5 times a power of ten.
  static double _nice(double v) {
    if (v <= 0) return 100;
    final p = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in [1.0, 2.0, 5.0, 10.0]) {
      if (v <= m * p) return m * p;
    }
    return 10 * p;
  }

  static String _money(double v) => v >= 1000
      ? '₱${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k'
      : '₱${v.toStringAsFixed(0)}';

  Rect _plot(Size s) => Rect.fromLTRB(_left, _topPad, s.width - 8, s.height - _bottom);

  int? indexAt(Offset o, Size s) {
    final r = _plot(s);
    if (periods.isEmpty || o.dx < r.left || o.dx > r.right) return null;
    final slot = r.width / periods.length;
    return ((o.dx - r.left) / slot).floor().clamp(0, periods.length - 1);
  }

  void _label(Canvas canvas, String t, Offset at, {TextAlign align = TextAlign.left, bool strong = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: t,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 11,
          fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
          color: strong ? AppColors.textPrimary : AppColors.textMuted,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - tp.width,
      TextAlign.center => at.dx - tp.width / 2,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final r = _plot(size);
    final top = periods.fold<double>(0, (a, x) => math.max(a, math.max(x.terminalFees, x.paid)));
    final ceil = _nice(top);
    double y(double v) => r.bottom - (v / ceil) * r.height;

    // Grid and its money labels.
    final grid = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final v = ceil * i / 4;
      final gy = y(v);
      canvas.drawLine(Offset(r.left, gy), Offset(r.right, gy), grid);
      _label(canvas, _money(v), Offset(r.left - 8, gy), align: TextAlign.right);
    }
    if (periods.isEmpty) return;

    final n = periods.length;
    final slot = r.width / n;
    final barW = math.min(slot * 0.62, 34.0);
    final every = (n / 8).ceil();
    final fmt = byMonth ? DateFormat.MMM() : (n > 7 ? DateFormat.MMMd() : DateFormat.E());

    // Bars: terminal fees owed. The selected period is solid emerald.
    for (var i = 0; i < n; i++) {
      final cx = r.left + slot * (i + 0.5);
      final v = periods[i].terminalFees;
      final on = i == selected;
      if (v > 0) {
        final bar = RRect.fromRectAndCorners(
          Rect.fromLTRB(cx - barW / 2, y(v), cx + barW / 2, r.bottom),
          topLeft: const Radius.circular(5),
          topRight: const Radius.circular(5),
        );
        canvas.drawRRect(
          bar,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: on
                  ? const [AppColors.accent, AppColors.progressStart]
                  : const [AppColors.edge, AppColors.primaryContainer],
            ).createShader(bar.outerRect),
        );
      }
      if (i % every == 0 || i == n - 1 || on) {
        _label(canvas, fmt.format(periods[i].period), Offset(cx, r.bottom + _bottom / 2 + 2),
            align: TextAlign.center, strong: on);
      }
    }

    // Line: paid, with a soft fill under it and a node per period.
    final pts = [
      for (var i = 0; i < n; i++) Offset(r.left + slot * (i + 0.5), y(periods[i].paid)),
    ];
    final area = Path()..moveTo(pts.first.dx, r.bottom);
    for (final p in pts) {
      area.lineTo(p.dx, p.dy);
    }
    area
      ..lineTo(pts.last.dx, r.bottom)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary.withValues(alpha: 0.12), AppColors.primary.withValues(alpha: 0)],
        ).createShader(r),
    );
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.primary,
    );
    for (var i = 0; i < n; i++) {
      final on = i == selected;
      if (n > 31 && !on) continue;
      canvas.drawCircle(pts[i], on ? 6 : 4, Paint()..color = on ? AppColors.primary : AppColors.surfaceRaised);
      canvas.drawCircle(
        pts[i],
        on ? 6 : 4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.primary,
      );
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.periods != periods || old.selected != selected || old.byMonth != byMonth;
}
