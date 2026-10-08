import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/audit_repository.dart';
import '../../data/repositories/dispatch_repository.dart';

/// "Phone capture" for one trip: ask the demo phone (ai_capture_app) to
/// photograph a leg, wait for it, and say what came of it.
///
/// Lives beside the trip it is about -- the Trips screen -- because that
/// is where the office can see the trip is under way and who is aboard.
/// Enabled only while the trip is boarding or departed: the backend
/// refuses any other trip, and a button that is bound to fail is worse
/// than one that says why it is off.
class PhoneCaptureButton extends StatefulWidget {
  const PhoneCaptureButton({
    super.key,
    required this.tripId,
    required this.tripStatus,
    this.onFinished,
  });

  final String tripId;
  final String tripStatus;

  /// Called once the phone's result is in (or the wait gave up), so the
  /// screen showing this trip can show the new audit straight away.
  final VoidCallback? onFinished;

  @override
  State<PhoneCaptureButton> createState() => _PhoneCaptureButtonState();
}

class _PhoneCaptureButtonState extends State<PhoneCaptureButton> {
  static const _pollEvery = Duration(seconds: 3);
  static const _waitAtMost = Duration(minutes: 3);

  bool _busy = false;
  String _busyLabel = '';

  bool get _underWay => widget.tripStatus == 'boarding' || widget.tripStatus == 'departed';

  Future<void> _run() async {
    final audits = context.read<AuditRepository>();
    final dispatch = context.read<DispatchRepository>();
    // The app-wide messenger outlives this button: the office may select
    // another trip or another tab while the phone is busy, and the result
    // must still be reported.
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;

    void say(String text, {bool error = false, int seconds = 6}) {
      messenger.showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? scheme.error : scheme.primary,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: seconds),
      ));
    }

    _setBusy('Loading stops...');
    final List<TripStop> stops;
    try {
      stops = await dispatch.tripStops(widget.tripId);
    } on ApiException catch (e) {
      _setBusy(null);
      say(e.message, error: true);
      return;
    }
    if (!mounted) return;
    _setBusy(null);

    final leg = await showDialog<int>(
      context: context,
      builder: (_) => _LegDialog(stops: stops, departed: widget.tripStatus == 'departed'),
    );
    if (leg == null || !mounted) return;

    _setBusy('Waiting for the phone...');
    final String requestedAt;
    try {
      requestedAt = await audits.triggerPhone(tripId: widget.tripId, legSequence: leg);
    } on ApiException catch (e) {
      _setBusy(null);
      say(e.message, error: true);
      return;
    }
    say('Capture requested for leg $leg. Waiting for the phone to take the photo.');

    // Wait for THIS request's outcome. A matching count is filed as
    // reconciled -- history, not the audit queue -- and a failure writes
    // no audit at all, so the queue alone could never report either.
    final outcome = await _awaitOutcome(audits, requestedAt);
    _setBusy(null);
    if (outcome == null) return; // a newer trigger replaced it; that one reports
    widget.onFinished?.call();

    switch (outcome['state']) {
      case 'fulfilled':
        final r = outcome['result'] as Map<String, dynamic>;
        final where = r['resolution_status'] == 'pending'
            ? 'Flagged -- it is in the YOLOv8 Audits queue.'
            : 'Filed as ${r['resolution_status']} under YOLOv8 Audits > History.';
        say(
          'Phone capture, leg ${r['leg_sequence']}: ${r['visual_count']} seen, '
          '${r['booked_count']} on the manifest. ${r['message']} $where',
          seconds: 12,
        );
      case 'failed':
        say('Phone capture failed: ${outcome['error']}', error: true, seconds: 12);
      default:
        say(
          'No photo from the phone after ${_waitAtMost.inMinutes} minutes. Is the '
          'capture app open with "Listen for a dispatch trigger" on?',
          error: true,
          seconds: 12,
        );
    }
  }

  /// Polls until the request made at [requestedAt] is fulfilled or failed.
  /// Null when a newer trigger replaced it; `timeout` when the phone never
  /// answered. Independent of this widget's lifetime on purpose.
  Future<Map<String, dynamic>?> _awaitOutcome(AuditRepository audits, String requestedAt) async {
    final deadline = DateTime.now().add(_waitAtMost);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(_pollEvery);
      final Map<String, dynamic> status;
      try {
        status = await audits.phoneStatus();
      } on ApiException {
        continue; // one failed poll is not an outcome
      }
      if (status['requested_at'] != requestedAt) return null;
      if (status['state'] != 'pending') return status;
    }
    return {'state': 'timeout'};
  }

  void _setBusy(String? label) {
    if (!mounted) return;
    setState(() {
      _busy = label != null;
      _busyLabel = label ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final button = OutlinedButton.icon(
      onPressed: _underWay && !_busy ? _run : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
      ),
      icon: _busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.phone_android),
      label: Text(_busy ? _busyLabel : 'Phone capture'),
    );
    if (_underWay) return button;
    return Tooltip(
      message: 'Available once the conductor opens boarding -- '
          'audits apply only to a trip that is boarding or departed.',
      child: button,
    );
  }
}

/// Which leg to photograph, by stop name. Leg k is stop k to stop k+1:
/// the stretch the passengers in the van are riding at that moment.
class _LegDialog extends StatefulWidget {
  const _LegDialog({required this.stops, required this.departed});
  final List<TripStop> stops;
  final bool departed;

  @override
  State<_LegDialog> createState() => _LegDialogState();
}

class _LegDialogState extends State<_LegDialog> {
  int _leg = 1;

  @override
  Widget build(BuildContext context) {
    final legs = [
      for (var i = 0; i + 1 < widget.stops.length; i++)
        (widget.stops[i].sequence, '${widget.stops[i].name} → ${widget.stops[i + 1].name}'),
    ].take(widget.departed ? widget.stops.length : 1).toList();
    return AlertDialog(
      backgroundColor: AppColors.surfaceRaised,
      title: const Text('Phone capture', style: TextStyle(color: AppColors.textPrimary)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.departed
                  ? 'Pick the leg the van is on now. The photo is compared with '
                      'everyone on the manifest for that leg.'
                  : 'The van is boarding, so this is leg 1. The photo is compared '
                      'with everyone on the manifest for that leg.',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.lg),
            RadioGroup<int>(
              groupValue: _leg,
              onChanged: (v) => setState(() => _leg = v!),
              child: Column(
                children: [
                  for (final (seq, label) in legs)
                    RadioListTile<int>(
                      value: seq,
                      contentPadding: EdgeInsets.zero,
                      title: Text('Leg $seq',
                          style: const TextStyle(color: AppColors.textPrimary)),
                      subtitle:
                          Text(label, style: const TextStyle(color: AppColors.textMuted)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: legs.isEmpty ? null : () => Navigator.of(context).pop(_leg),
          child: const Text('Request capture'),
        ),
      ],
    );
  }
}
