import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/sos_repository.dart';
import '../../../core/design/tokens.dart';

/// The office's emergency desk (spec 2.3.5).
///
/// Two things are deliberate here. Open alerts poll fast -- ten seconds,
/// against the audit queue's twenty -- because an emergency that sits
/// unseen on a screen is the failure this module exists to prevent. And
/// every alert shows its SMS row by row: a text that was never attempted,
/// or that the gateway refused, is displayed as such rather than folded
/// into a reassuring "notified" badge.
class SosConsoleScreen extends StatefulWidget {
  const SosConsoleScreen({super.key});

  @override
  State<SosConsoleScreen> createState() => _SosConsoleScreenState();
}

class _SosConsoleScreenState extends State<SosConsoleScreen> {
  late final SosRepository _sos = context.read<SosRepository>();

  List<SosAlert>? _alerts;
  bool _showResolved = false;
  bool _loading = true;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_loading) _load(quiet: true);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final rows = await _sos.list(status: _showResolved ? 'resolved' : 'open');
      if (!mounted) return;
      setState(() {
        _alerts = rows;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acknowledge(SosAlert a) async {
    try {
      await _sos.acknowledge(a.sosId);
      await _load(quiet: true);
      _toast('Acknowledged. ${a.raisedBy} has been told someone is responding.');
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _resolve(SosAlert a) async {
    final notes = await showDialog<String>(
      context: context,
      builder: (_) => _ResolveDialog(alert: a),
    );
    if (notes == null) return;
    try {
      await _sos.resolve(a.sosId, notes);
      await _load(quiet: true);
      _toast('Emergency closed.');
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    }
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _alerts ?? const <SosAlert>[];
    final openCount = rows.where((a) => !a.isResolved).length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(openCount),
          if (_error != null)
            Container(
              width: double.infinity,
              color: AppColors.dangerContainer,
              padding: const EdgeInsets.all(12),
              child: Text('Could not load alerts: $_error'),
            ),
          Expanded(
            child: _loading && _alerts == null
                ? const Center(child: CircularProgressIndicator())
                : rows.isEmpty
                    ? _empty()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        itemCount: rows.length,
                        itemBuilder: (_, i) => _AlertCard(
                          alert: rows[i],
                          onAcknowledge: () => _acknowledge(rows[i]),
                          onResolve: () => _resolve(rows[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _header(int openCount) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        child: Row(
          children: [
            Icon(Icons.emergency_share,
                color: openCount > 0 ? AppColors.danger : AppColors.textMuted),
            const SizedBox(width: 10),
            Text(
              _showResolved ? 'Closed emergencies' : 'Open emergencies',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            if (!_showResolved && openCount > 0) ...[
              const SizedBox(width: 12),
              Chip(
                label: Text('$openCount needing attention'),
                backgroundColor: AppColors.danger,
                labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                side: BorderSide.none,
              ),
            ],
            const Spacer(),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Open')),
                ButtonSegment(value: true, label: Text('History')),
              ],
              selected: {_showResolved},
              onSelectionChanged: (s) {
                setState(() => _showResolved = s.first);
                _load();
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      );

  Widget _empty() => Center(
        child: Text(
          _showResolved
              ? 'No emergency has been closed yet.'
              : 'No open emergencies. Crew and passengers can raise one from the app.',
          style: const TextStyle(color: AppColors.textMuted),
        ),
      );
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    required this.alert,
    required this.onAcknowledge,
    required this.onResolve,
  });

  final SosAlert alert;
  final VoidCallback onAcknowledge;
  final VoidCallback onResolve;

  static final _time = DateFormat('MMM d, HH:mm');

  @override
  Widget build(BuildContext context) {
    final urgent = alert.isOpen;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: urgent ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: urgent ? AppColors.danger : AppColors.divider,
          width: urgent ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusPill(status: alert.status),
                const SizedBox(width: 8),
                Text(
                  alert.category.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
                ),
                const SizedBox(width: 12),
                Text(_time.format(alert.raisedAt),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 10),
            Text('${alert.raisedBy} · ${alert.raisedByRole}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            if (alert.raisedByPhone != null)
              Text(alert.raisedByPhone!,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
            if (alert.tripLabel != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(alert.tripLabel!,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
              ),
            if (alert.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('"${alert.note}"',
                    style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
            const SizedBox(height: 10),
            _location(),
            const SizedBox(height: 10),
            _smsBlock(),
            if (alert.acknowledgedBy != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Acknowledged by ${alert.acknowledgedBy}'
                  '${alert.acknowledgedAt == null ? '' : ' at ${_time.format(alert.acknowledgedAt!)}'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
            if (alert.resolutionNotes != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Closed: ${alert.resolutionNotes}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ),
            if (!alert.isResolved) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (alert.isOpen)
                    FilledButton.icon(
                      onPressed: onAcknowledge,
                      icon: const Icon(Icons.visibility, size: 18),
                      label: const Text('Acknowledge'),
                    ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onResolve,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Close with a note'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _location() {
    if (!alert.hasLocation) {
      return const Row(
        children: [
          Icon(Icons.location_off, size: 16, color: AppColors.textMuted),
          SizedBox(width: 6),
          Text('No location — the handset could not provide a fix.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      );
    }
    final accuracy =
        alert.accuracyM == null ? '' : ' (±${alert.accuracyM!.round()} m)';
    return Row(
      children: [
        const Icon(Icons.place, size: 16, color: AppColors.info),
        const SizedBox(width: 6),
        Flexible(
          child: SelectableText(
            '${alert.latitude!.toStringAsFixed(5)}, '
            '${alert.longitude!.toStringAsFixed(5)}$accuracy'
            '${alert.mapUrl == null ? '' : '  ·  ${alert.mapUrl}'}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _smsBlock() {
    if (alert.smsAttempted == 0) {
      return const Row(
        children: [
          Icon(Icons.sms_failed_outlined, size: 16, color: AppColors.warning),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'No SMS was attempted — set sos_contact_numbers in Policies.',
              style: TextStyle(fontSize: 12, color: AppColors.danger),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SMS: ${alert.smsSent} sent'
          '${alert.smsFailed > 0 ? ', ${alert.smsFailed} failed' : ''}'
          '${alert.smsSkipped > 0 ? ', ${alert.smsSkipped} skipped' : ''}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        for (final d in alert.dispatches)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 2),
            child: Text(
              '${d.recipient} · ${d.status}'
              '${d.error == null ? '' : ' — ${d.error}'}',
              style: TextStyle(
                fontSize: 11,
                color: d.status == 'sent' ? AppColors.textMuted : AppColors.danger,
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, label) = switch (status) {
      'open' => (AppColors.danger, 'OPEN'),
      'acknowledged' => (AppColors.warning, 'RESPONDING'),
      _ => (AppColors.success, 'CLOSED'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }
}

/// Closing an emergency requires an account of what happened, the same
/// way dispositioning a YOLOv8 variance does.
class _ResolveDialog extends StatefulWidget {
  const _ResolveDialog({required this.alert});
  final SosAlert alert;

  @override
  State<_ResolveDialog> createState() => _ResolveDialogState();
}

class _ResolveDialogState extends State<_ResolveDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final empty = _controller.text.trim().isEmpty;
    return AlertDialog(
      title: Text('Close ${widget.alert.category} alert'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 4,
          maxLength: 512,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'What happened?',
            hintText: 'Ambulance met the van at Panabo. Passenger stable.',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              empty ? null : () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Close emergency'),
        ),
      ],
    );
  }
}
