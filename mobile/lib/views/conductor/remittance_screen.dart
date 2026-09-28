import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/offline/walk_in_sync_service.dart';
import '../../data/repositories/operations_repository.dart';

/// Hand over the cash from a trip.
///
/// The expected figure is computed by the server from the walk-ins this
/// crew member logged — it is never typed in, because the number a
/// person is measured against must not be editable by that person. What
/// they declare is compared against it, and the office records what it
/// actually counted.
class RemittanceScreen extends StatefulWidget {
  const RemittanceScreen({super.key, required this.trip});

  final CrewTrip trip;

  @override
  State<RemittanceScreen> createState() => _RemittanceScreenState();
}

class _RemittanceScreenState extends State<RemittanceScreen> {
  late final OperationsRepository _ops;
  final _declared = TextEditingController();
  final _notes = TextEditingController();
  Remittance? _remit;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ops = OperationsRepository(context.read<ApiClient>());
    _load();
  }

  @override
  void dispose() {
    _declared.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _ops.remittancePreview(widget.trip.tripId);
      if (!mounted) return;
      setState(() => _remit = r);
      if (!r.isSubmitted && _declared.text.isEmpty) {
        _declared.text = r.expectedAmount.toStringAsFixed(2);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_declared.text);
    if (amount == null || amount < 0) {
      _snack('Enter the amount you are handing over.');
      return;
    }
    final expected = _remit?.expectedAmount ?? 0;
    final diff = amount - expected;
    if (diff.abs() >= 0.005) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Amount differs'),
          content: Text(
            'You are declaring ₱${amount.toStringAsFixed(2)} against an expected '
            '₱${expected.toStringAsFixed(2)} — ${diff > 0 ? 'over' : 'short'} by '
            '₱${diff.abs().toStringAsFixed(2)}. The difference is recorded, not refused. '
            'Add a note if there is a reason.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go back')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit anyway')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _submitting = true);
    try {
      final r = await _ops.submitRemittance(
        tripId: widget.trip.tripId,
        declaredAmount: amount,
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      setState(() => _remit = r);
      _snack('Submitted. The office will confirm the count.');
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _remit;
    final pendingCount =
        context.watch<WalkInSyncService>().pendingCountFor(widget.trip.tripId);
    return Scaffold(
      appBar: AppBar(title: const Text('Remit cash')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && r == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(widget.trip.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(
                      DateFormat('EEE, MMM d • hh:mm a').format(widget.trip.departure),
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('CASH IN HAND', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text('₱${r!.expectedAmount.toStringAsFixed(2)}',
                              style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('from ${r.bookingCount} cash passenger${r.bookingCount == 1 ? '' : 's'} you logged',
                              style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (!r.isSubmitted && pendingCount > 0) _pendingSyncNotice(pendingCount),
                    if (r.isSubmitted)
                      _submittedView(r)
                    else
                      _form(blocked: pendingCount > 0),
                  ],
                ),
    );
  }

  /// The expected figure above comes from bookings the server knows
  /// about. Cash from a walk-in still sitting in the offline queue isn't
  /// counted in it yet, so remitting now would understate what's
  /// actually owed -- same reasoning as keeping `pending` cash separate
  /// from `unreconciled` everywhere else in this app.
  Widget _pendingSyncNotice(int count) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, size: 20, color: AppColors.warning),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$count passenger${count == 1 ? '' : 's'} logged offline for this trip '
                "haven't synced yet. The figure above doesn't include them -- "
                'connect and sync before remitting.',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              onPressed: () => context.read<WalkInSyncService>().flush(),
              child: const Text('Sync now'),
            ),
          ],
        ),
      );

  Widget _form({required bool blocked}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Amount handing over (₱)', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          TextField(
            controller: _declared,
            enabled: !blocked,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          const Text('Notes (optional)', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textMuted)),
          const SizedBox(height: 6),
          TextField(
            controller: _notes,
            enabled: !blocked,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'e.g. one passenger paid via GCash to me directly'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: (_submitting || blocked) ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.payments),
            label: Text(_submitting ? 'Submitting…' : 'Submit remittance'),
          ),
        ],
      );

  Widget _submittedView(Remittance r) {
    final (label, colour) = switch (r.status) {
      'received' => ('RECEIVED BY OFFICE', AppColors.accent),
      'disputed' => ('VARIANCE FLAGGED', AppColors.danger),
      _ => ('SUBMITTED — AWAITING OFFICE', AppColors.warning),
    };
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colour.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: colour, fontWeight: FontWeight.w800, letterSpacing: 1, fontSize: 12)),
          const SizedBox(height: 12),
          _row('Declared', '₱${(r.declaredAmount ?? 0).toStringAsFixed(2)}'),
          if (r.receivedAmount != null) _row('Office counted', '₱${r.receivedAmount!.toStringAsFixed(2)}'),
          if (r.variance != null) _row('Variance', '₱${r.variance!.toStringAsFixed(2)}'),
          if (r.submittedAt != null)
            _row('Submitted', DateFormat('MMM d, hh:mm a').format(r.submittedAt!)),
          if (r.notes != null && r.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.notes!, style: const TextStyle(color: AppColors.textMuted)),
          ],
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(color: AppColors.textMuted)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
