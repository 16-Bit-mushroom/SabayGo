import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/util/download.dart';
import '../../../data/repositories/revenue_repository.dart';

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
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _pickRange,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
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
                    disabledForegroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
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
                icon: const Icon(Icons.refresh, color: Colors.white70),
                tooltip: 'Refresh',
              ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError(_error!)
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSummaryCards(),
                            const SizedBox(height: 24),
                            _buildTripsTable(),
                          ],
                        ),
                      ),
          ),
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
          Text(message, style: const TextStyle(color: Colors.white70)),
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
      _StatCard(label: 'Trips', value: '${s.trips}', icon: Icons.route_outlined, color: const Color(0xFF88C0D0)),
      _StatCard(
          label: 'Total Bookings',
          value: '${s.totalBookings}',
          sub: '${s.appBookings} app · ${s.walkinBookings} walk-in',
          icon: Icons.confirmation_number_outlined,
          color: const Color(0xFF8FBCBB)),
      _StatCard(
          label: 'Collected Fare',
          value: _currency.format(s.collectedFare),
          icon: Icons.payments_outlined,
          color: const Color(0xFFA3BE8C)),
      _StatCard(
          label: 'Cash In Hand',
          value: _currency.format(s.cashInHand),
          sub: 'Held by crew, not yet remitted',
          icon: Icons.account_balance_wallet_outlined,
          color: const Color(0xFFEBCB8B)),
      _StatCard(
          label: 'Unreconciled',
          value: _currency.format(s.unreconciledAmount),
          sub: s.unreconciledAmount > 0 ? 'Fare unaccounted for' : 'Fully accounted',
          icon: Icons.warning_amber_outlined,
          color: s.unreconciledAmount > 0 ? const Color(0xFFBF616A) : const Color(0xFFA3BE8C)),
      _StatCard(
          label: 'Pending Audits',
          value: '${s.pendingAudits}',
          icon: Icons.policy_outlined,
          color: s.pendingAudits > 0 ? const Color(0xFFBF616A) : const Color(0xFFA3BE8C)),
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: cards,
    );
  }

  Widget _buildTripsTable() {
    final trips = _trips ?? [];
    return Card(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Per-Trip Reconciliation',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
            if (trips.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32.0),
                child: Center(child: Text('No trips in this range.', style: TextStyle(color: Colors.white54))),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFF2C3244)),
                  dataRowMinHeight: 50,
                  dataRowMaxHeight: 60,
                  headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70),
                  columns: const [
                    DataColumn(label: Text('Departed')),
                    DataColumn(label: Text('Route')),
                    DataColumn(label: Text('Van')),
                    DataColumn(label: Text('Bookings')),
                    DataColumn(label: Text('Collected')),
                    DataColumn(label: Text('Cash In Hand')),
                    DataColumn(label: Text('Unreconciled')),
                    DataColumn(label: Text('Audits')),
                  ],
                  rows: trips.map((t) {
                    return DataRow(
                      cells: [
                        DataCell(Text(DateFormat.MMMd().add_jm().format(t.departureDatetime),
                            style: const TextStyle(color: Colors.white70))),
                        DataCell(Text(t.routeName, style: const TextStyle(color: Colors.white))),
                        DataCell(Text(t.plateNumber ?? '—', style: const TextStyle(color: Colors.white70))),
                        DataCell(Text('${t.totalBookings}/${t.seatCapacity}',
                            style: const TextStyle(color: Colors.white70))),
                        DataCell(Text(_currency.format(t.collectedFare),
                            style: const TextStyle(color: Colors.white))),
                        DataCell(Text(_currency.format(t.cashInHand),
                            style: const TextStyle(color: Color(0xFFEBCB8B)))),
                        DataCell(Text(
                          _currency.format(t.unreconciledAmount),
                          style: TextStyle(
                            color: t.unreconciledAmount > 0 ? const Color(0xFFBF616A) : Colors.white70,
                            fontWeight: t.unreconciledAmount > 0 ? FontWeight.bold : FontWeight.normal,
                          ),
                        )),
                        DataCell(
                          t.pendingAudits > 0
                              ? Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error, size: 18)
                              : const Icon(Icons.check_circle_outline, color: Color(0xFFA3BE8C), size: 18),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
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
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
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
                    style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub!, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}
