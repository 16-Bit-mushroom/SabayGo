import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/util/download.dart';
import '../../../data/repositories/revenue_repository.dart';
import '../../../core/design/tokens.dart';

/// Per-trip revenue reconciliation.
///
/// `cashInHand` (fare a conductor is holding but hasn't remitted yet) is
/// shown separately from `unreconciledAmount` (fare nobody can account
/// for) -- collapsing the two would make every honest conductor look
/// like they were skimming until the moment they physically hand the
/// cash over.
class RevenueScreen extends StatefulWidget {
  const RevenueScreen({super.key});

  @override
  State<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends State<RevenueScreen> {
  late final RevenueRepository _revenue = context.read<RevenueRepository>();

  RevenueSummary? _summary;
  List<TripRevenue>? _trips;
  bool _loading = true;
  bool _exporting = false;

  /// Shared by the trip list and its scrollbar, which is always visible so
  /// the office can see at once that there are more rows below.
  final _rowsScroll = ScrollController();

  @override
  void dispose() {
    _rowsScroll.dispose();
    super.dispose();
  }
  String? _error;

  late DateTime _dateFrom = DateTime.now().subtract(const Duration(days: 6));
  late DateTime _dateTo = DateTime.now();

  final _currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

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
      final results = await Future.wait([
        _revenue.summary(dateFrom: _dateFrom, dateTo: _dateTo),
        _revenue.trips(dateFrom: _dateFrom, dateTo: _dateTo, limit: 200),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as RevenueSummary;
        _trips = results[1] as List<TripRevenue>;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// G.1: the same date range the screen shows, as a file the office can
  /// open in Excel or Sheets. Bytes come back through the authenticated
  /// client -- a plain link would carry no JWT.
  Future<void> _export(String format) async {
    setState(() => _exporting = true);
    final span =
        '${DateFormat('yyyy-MM-dd').format(_dateFrom)}_to_${DateFormat('yyyy-MM-dd').format(_dateTo)}';
    try {
      final bytes = await _revenue.export(format: format, dateFrom: _dateFrom, dateTo: _dateTo);
      downloadBytes(
        bytes,
        filename: 'sabaygo_revenue_$span.$format',
        mimeType: format == 'csv'
            ? 'text/csv'
            : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: ${e.message}')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _dateFrom, end: _dateTo),
    );
    if (picked != null) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
      });
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Revenue Reconciliation',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _pickRange,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                ),
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(
                    '${DateFormat.MMMd().format(_dateFrom)} – ${DateFormat.MMMd().format(_dateTo)}'),
              ),
              const SizedBox(width: 12),
              PopupMenuButton<String>(
                enabled: !_loading && !_exporting,
                tooltip: 'Export',
                onSelected: _export,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'xlsx', child: Text('Excel workbook (.xlsx)')),
                  PopupMenuItem(value: 'csv', child: Text('CSV (.csv)')),
                ],
                child: OutlinedButton.icon(
                  onPressed: null,
                  style: OutlinedButton.styleFrom(
                    disabledForegroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                  ),
                  icon: _exporting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download, size: 18),
                  label: Text(_exporting ? 'Exporting…' : 'Export'),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, color: AppColors.textPrimary),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 24),
          // The totals stay pinned and only the trip rows scroll. They used
          // to share one scroll view, so the figures a reconciliation is
          // checked against left the screen as soon as the office scrolled
          // down to the trip that did not add up.
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(child: _buildError(_error!))
          else ...[
            _buildSummaryCards(),
            const SizedBox(height: 16),
            Expanded(child: _buildTripsTable()),
          ],
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 40),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final s = _summary;
    if (s == null) return const SizedBox.shrink();
    final cards = [
      _StatCard(label: 'Trips', value: '${s.trips}', icon: Icons.route_outlined, color: AppColors.primary),
      _StatCard(
          label: 'Total Bookings',
          value: '${s.totalBookings}',
          sub: '${s.appBookings} app · ${s.walkinBookings} walk-in',
          icon: Icons.confirmation_number_outlined,
          color: AppColors.primary),
      _StatCard(
          label: 'Collected Fare',
          value: _currency.format(s.collectedFare),
          icon: Icons.payments_outlined,
          color: AppColors.success),
      _StatCard(
          label: 'Cash In Hand',
          value: _currency.format(s.cashInHand),
          sub: 'Held by crew, not yet remitted',
          icon: Icons.account_balance_wallet_outlined,
          color: AppColors.warning),
      _StatCard(
          label: 'Unreconciled',
          value: _currency.format(s.unreconciledAmount),
          sub: s.unreconciledAmount > 0 ? 'Fare unaccounted for' : 'Fully accounted',
          icon: Icons.warning_amber_outlined,
          color: s.unreconciledAmount > 0 ? AppColors.danger : AppColors.success),
      _StatCard(
          label: 'Pending Audits',
          value: '${s.pendingAudits}',
          icon: Icons.policy_outlined,
          color: s.pendingAudits > 0 ? AppColors.danger : AppColors.success),
    ];

    // One row, always. A wrapped second row of cards would take its height
    // from the table beneath it, on exactly the narrow screen that has the
    // least to spare. Wide: the six share the width. Narrow: the row
    // scrolls sideways at a fixed card width instead of wrapping.
    const gap = 12.0;
    const minCard = 180.0;
    return LayoutBuilder(builder: (context, c) {
      final fits = c.maxWidth >= cards.length * minCard + (cards.length - 1) * gap;
      // IntrinsicHeight + stretch: every card takes the height of the
      // tallest, so a card with a two-line caption and one with none still
      // line up -- without a fixed height that a wrapped caption overflows.
      if (fits) {
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              Expanded(child: cards[i]),
            ],
          ]),
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              SizedBox(width: minCard, child: cards[i]),
            ],
          ]),
        ),
      );
    });
  }

  /// Per-trip rows: full width, headings pinned, rows scrolling beneath.
  ///
  /// Not a [DataTable]. A DataTable is exactly as wide as its content, so
  /// inside a full-width card it left a blank band on the right, and its
  /// heading row scrolls away with the data. Here each column is a flex
  /// share of the card, so the table always fills it, and the heading row
  /// sits outside the scrolling list. Below [_minTableWidth] the whole table
  /// scrolls sideways rather than squeezing a route name onto three lines.
  Widget _buildTripsTable() {
    final trips = _trips ?? [];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                const Text('Per-Trip Reconciliation',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(width: AppSpacing.sm),
                if (trips.isNotEmpty)
                  Text(trips.length == 1 ? '1 trip' : '${trips.length} trips',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            child: trips.isEmpty
                ? const Center(
                    child: Text('No trips in this range. Pick another date range above.',
                        style: TextStyle(color: AppColors.textMuted)))
                : LayoutBuilder(builder: (context, c) {
                    final width = c.maxWidth < _minTableWidth ? _minTableWidth : c.maxWidth;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: width,
                        height: c.maxHeight,
                        child: Column(
                          children: [
                            _headingRow(),
                            const Divider(),
                            Expanded(
                              child: Scrollbar(
                                controller: _rowsScroll,
                                thumbVisibility: true,
                                child: ListView.separated(
                                  controller: _rowsScroll,
                                  itemCount: trips.length,
                                  separatorBuilder: (_, _) => const Divider(),
                                  itemBuilder: (_, i) => _tripRow(trips[i]),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
          ),
        ],
      ),
    );
  }

  static const double _minTableWidth = 900;

  /// Label, flex share, and whether the column holds a figure. Figures are
  /// right-aligned so pesos line up digit under digit and a column can be
  /// scanned for the odd one out, which is the whole job of this table.
  static const _columns = <(String, int, bool)>[
    ('Departed', 14, false),
    ('Route', 20, false),
    ('Van', 10, false),
    ('Bookings', 9, true),
    ('Collected', 11, true),
    ('Cash in hand', 11, true),
    ('Unreconciled', 11, true),
    ('Audits', 8, false),
  ];

  Widget _cell(int column, Widget child) {
    final (_, flex, numeric) = _columns[column];
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Align(
          alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }

  Widget _headingRow() => Container(
        height: 44,
        color: AppColors.surfaceSunken,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(children: [
          for (var i = 0; i < _columns.length; i++)
            _cell(
              i,
              Text(_columns[i].$1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
            ),
        ]),
      );

  static const _figures = TextStyle(
    color: AppColors.textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  Widget _tripRow(TripRevenue t) {
    final unreconciled = t.unreconciledAmount > 0;
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Row(children: [
          _cell(0, Text(DateFormat.MMMd().add_jm().format(t.departureDatetime), style: _figures)),
          _cell(1, Text(t.routeName, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textPrimary))),
          _cell(2, Text(t.plateNumber ?? '—', style: const TextStyle(color: AppColors.textPrimary))),
          _cell(3, Text('${t.totalBookings}/${t.seatCapacity}', style: _figures)),
          _cell(4, Text(_currency.format(t.collectedFare), style: _figures)),
          // Ochre only when there is cash out with the crew. On a ₱0.00 row
          // the colour flagged nothing and taught the eye to skip the column.
          _cell(5, Text(_currency.format(t.cashInHand),
              style: _figures.copyWith(
                  color: t.cashInHand > 0 ? AppColors.warning : AppColors.textPrimary))),
          _cell(6, Text(_currency.format(t.unreconciledAmount),
              style: _figures.copyWith(
                color: unreconciled ? AppColors.danger : AppColors.textPrimary,
                fontWeight: unreconciled ? FontWeight.bold : FontWeight.normal,
              ))),
          _cell(
            7,
            t.pendingAudits > 0
                ? Tooltip(
                    message: '${t.pendingAudits} pending audit${t.pendingAudits == 1 ? '' : 's'}',
                    child: const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 18))
                : const Tooltip(
                    message: 'No pending audits',
                    child: Icon(Icons.check_circle_outline, color: AppColors.success, size: 18)),
          ),
        ]),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, required this.color, this.sub});

  final String label;
  final String value;
  final String? sub;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      // No fixed height. It used to be 112, which held a one-line caption;
      // once the cards shared the row's width, "Held by crew, not yet
      // remitted" wrapped to two lines and overflowed. The summary row
      // stretches every card to the tallest one instead (IntrinsicHeight),
      // so they still line up whether or not they have a caption.
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // A large total (₱1,234,567.00) shrinks to the card rather than
          // spilling past its edge.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                )),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35)),
          ],
        ],
      ),
    );
  }
}
