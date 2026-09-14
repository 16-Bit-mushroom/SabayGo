import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/audit_repository.dart';

class AuditDashboardScreen extends StatefulWidget {
  const AuditDashboardScreen({super.key});

  @override
  State<AuditDashboardScreen> createState() => _AuditDashboardScreenState();
}

class _AuditDashboardScreenState extends State<AuditDashboardScreen> {
  late final AuditRepository _audits = context.read<AuditRepository>();

  List<PendingAudit>? _logs;
  int _selectedIndex = 0;
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
      final logs = await _audits.pending();
      if (!mounted) return;
      setState(() {
        _logs = logs;
        if (_selectedIndex >= logs.length) _selectedIndex = 0;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolve(PendingAudit audit, {required String resolution}) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (_) => _ResolveNotesDialog(
        title: resolution == 'resolved' ? 'Flag Driver & Resolve' : 'Clear Without Action',
      ),
    );
    if (notes == null || notes.trim().isEmpty) return;

    try {
      await _audits.resolve(auditId: audit.auditId, resolution: resolution, notes: notes.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resolution == 'resolved' ? 'Audit resolved.' : 'Audit cleared.'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;
        final logs = _logs ?? [];
        final selectedLog = logs.isNotEmpty ? logs[_selectedIndex] : null;

        return Padding(
          padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Live YOLOv8 Audit Queue',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const Spacer(),
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
                        : logs.isEmpty
                            ? _buildEmpty()
                            : isDesktop
                                ? Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(flex: 3, child: _buildDataGrid(logs)),
                                      const SizedBox(width: 24),
                                      Expanded(flex: 2, child: _buildProofPanel(selectedLog!)),
                                    ],
                                  )
                                : SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        _buildDataGrid(logs),
                                        const SizedBox(height: 24),
                                        _buildProofPanel(selectedLog!),
                                      ],
                                    ),
                                  ),
              ),
            ],
          ),
        );
      },
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

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, color: Color(0xFFA3BE8C), size: 40),
          SizedBox(height: 12),
          Text('No pending variances. The cabin matches the manifest.',
              style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildDataGrid(List<PendingAudit> logs) {
    return Card(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFF2C3244)),
              dataRowMinHeight: 50,
              dataRowMaxHeight: 60,
              headingTextStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70),
              columns: const [
                DataColumn(label: Text('Trip')),
                DataColumn(label: Text('Leg')),
                DataColumn(label: Text('Manifest')),
                DataColumn(label: Text('YOLO Count')),
                DataColumn(label: Text('Variance')),
              ],
              rows: List<DataRow>.generate(logs.length, (index) {
                final log = logs[index];
                final rowAlert = log.variance > 0;
                return DataRow(
                  selected: _selectedIndex == index,
                  onSelectChanged: (selected) {
                    if (selected == true) setState(() => _selectedIndex = index);
                  },
                  cells: [
                    DataCell(Text(log.tripLabel ?? log.tripId.substring(0, 8),
                        style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white))),
                    DataCell(Text(log.legSequence.toString(), style: const TextStyle(color: Colors.white70))),
                    DataCell(Text(log.bookedCount.toString(), style: const TextStyle(color: Colors.white70))),
                    DataCell(
                      Text(
                        log.visualCount.toString(),
                        style: TextStyle(
                            color: rowAlert ? Theme.of(context).colorScheme.error : Colors.white,
                            fontWeight: rowAlert ? FontWeight.bold : FontWeight.normal),
                      ),
                    ),
                    DataCell(
                      Text(
                        '+${log.variance}',
                        style: TextStyle(
                            color: rowAlert ? Theme.of(context).colorScheme.error : Colors.white,
                            fontWeight: rowAlert ? FontWeight.bold : FontWeight.normal),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProofPanel(PendingAudit log) {
    final isAlert = log.variance > 0;
    final imageUrl = log.snapshotAbsoluteUrl;
    return Card(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('Audit: ${log.tripLabel ?? log.tripId.substring(0, 8)}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  if (isAlert) Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF151923),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: imageUrl == null
                    ? const Center(
                        child: Icon(Icons.image_not_supported_outlined, color: Colors.white24, size: 40))
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image_outlined, color: Colors.white24, size: 40)),
                          loadingBuilder: (context, child, progress) => progress == null
                              ? child
                              : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      ),
              ),
              const SizedBox(height: 24),
              const Text('AI Reconciliation Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white54, letterSpacing: 1.2)),
              const Divider(color: Colors.white10),
              _buildDetailRow('Captured', DateFormat.jm().add_yMMMd().format(log.capturedAt)),
              _buildDetailRow('Digital Manifest', log.bookedCount.toString()),
              _buildDetailRow('Physical Reality', log.visualCount.toString(), isAlert: isAlert),
              _buildDetailRow('Detected Leakage', '+${log.variance} Passengers', isAlert: isAlert),
              if (log.confidenceAvg != null)
                _buildDetailRow('Model Confidence', '${(log.confidenceAvg! * 100).toStringAsFixed(0)}%'),
              const SizedBox(height: 32),
              if (isAlert)
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _resolve(log, resolution: 'resolved'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.gavel),
                        label: const Text('Flag & Resolve', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _resolve(log, resolution: 'ignored'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.close),
                        label: const Text('Ignore', style: TextStyle(fontSize: 14)),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _resolve(log, resolution: 'ignored'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2C3244),
                      foregroundColor: Colors.white70,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Clear / No Action Needed', style: TextStyle(fontSize: 15)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isAlert = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w400, color: Colors.white70)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isAlert ? Theme.of(context).colorScheme.error : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResolveNotesDialog extends StatefulWidget {
  const _ResolveNotesDialog({required this.title});
  final String title;

  @override
  State<_ResolveNotesDialog> createState() => _ResolveNotesDialogState();
}

class _ResolveNotesDialogState extends State<_ResolveNotesDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF222736),
      title: Text(widget.title, style: const TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Notes for the audit trail (required)',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF151923),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
