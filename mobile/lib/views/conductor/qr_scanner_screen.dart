import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/operations_repository.dart';

/// Scan tickets at the van door for one trip at one stop.
///
/// Stays open between passengers: a conductor works a queue, and
/// returning to the dashboard after every scan would double the taps.
/// Every scan goes to the server, which answers with a verdict for any
/// outcome — refused tickets are normal here, not errors.
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({
    super.key,
    required this.trip,
    required this.stopSequence,
  });

  final CrewTrip trip;
  final int stopSequence;

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _scanner = MobileScannerController();
  late final OperationsRepository _ops;
  bool _busy = false;
  int _accepted = 0;

  /// Long enough to read "Boarded" and the ticket number, short enough
  /// that the next passenger is not kept waiting.
  static const _autoCloseAfter = Duration(milliseconds: 1400);

  @override
  void initState() {
    super.initState();
    _ops = OperationsRepository(context.read<ApiClient>());
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    setState(() => _busy = true);
    await _scanner.stop();

    ScanVerdict verdict;
    try {
      verdict = await _ops.scan(
        qrPayload: raw,
        tripId: widget.trip.tripId,
        stopSequence: widget.stopSequence,
      );
    } on ApiException catch (e) {
      // A 403 here means the roster does not include this trip; anything
      // else is the network. Neither is a verdict on the ticket.
      verdict = ScanVerdict(result: 'error', accepted: false, message: e.message);
    }

    if (!mounted) return;
    if (verdict.accepted) _accepted++;
    await _showVerdict(verdict);
    if (!mounted) return;
    await _scanner.start();
    setState(() => _busy = false);
  }

  Future<void> _showVerdict(ScanVerdict v) {
    final colour = v.accepted ? AppColors.success : AppColors.danger;
    final title = switch (v.result) {
      _ when v.accepted => 'Boarded',
      'already_boarded' => 'Already aboard',
      'unpaid' => 'Not paid',
      'cancelled' => 'Cancelled',
      'wrong_stop' => 'Wrong stop',
      'wrong_trip' => 'Wrong trip',
      'error' => 'Could not verify',
      _ => 'Refused',
    };

    // Felt, not only seen: the conductor's eyes are on the passenger and
    // the door, and the yard is too loud for a beep. One light tap for a
    // good ticket; two heavy ones for anything that needs attention, so
    // the two can be told apart without looking.
    if (v.accepted) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
      Future<void>.delayed(const Duration(milliseconds: 140), HapticFeedback.heavyImpact);
    }

    // An accepted ticket clears itself after a beat, so a queue of good
    // tickets is scan, scan, scan -- the old sheet needed a tap for every
    // passenger. A refusal stays until dismissed: that one has to be read
    // and acted on. Screen-reader users keep the manual close, since a
    // sheet that vanishes mid-announcement takes its message with it.
    final autoClose = v.accepted && !MediaQuery.of(context).accessibleNavigation;
    var open = true;
    void close(BuildContext ctx) {
      if (!open) return;
      open = false;
      Navigator.pop(ctx);
    }

    return showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) {
        if (autoClose) {
          Future<void>.delayed(_autoCloseAfter, () {
            if (ctx.mounted) close(ctx);
          });
        }
        return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shows the sheet is about to go by itself, so its closing is
            // expected rather than a surprise.
            if (autoClose) ...[
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 1, end: 0),
                duration: _autoCloseAfter,
                builder: (_, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 3,
                  color: colour,
                  backgroundColor: AppColors.divider,
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Icon(v.accepted ? Icons.check_circle : Icons.cancel, color: colour, size: 36),
                const SizedBox(width: 12),
                Text(title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: colour)),
              ],
            ),
            const SizedBox(height: 12),
            Text(v.message, style: const TextStyle(fontSize: 16, height: 1.3)),
            if (v.ticketNumber != null) ...[
              const SizedBox(height: 12),
              Text(
                '${v.ticketNumber}'
                '${v.boardingStop != null && v.alightingStop != null ? '  ·  ${widget.trip.stopName(v.boardingStop!)} → ${widget.trip.stopName(v.alightingStop!)}' : ''}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => close(ctx),
              style: FilledButton.styleFrom(backgroundColor: colour),
              child: const Text('Next passenger', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(controller: _scanner, onDetect: _onDetect),
          CustomPaint(size: Size.infinite, painter: _ScannerOverlayPainter()),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _glassButton(icon: Icons.close, onTap: () => Navigator.pop(context, _accepted)),
                  ValueListenableBuilder(
                    valueListenable: _scanner,
                    builder: (context, state, _) => _glassButton(
                      icon: state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                      onTap: _scanner.toggleTorch,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            top: 90,
            left: 24,
            right: 24,
            child: Column(
              children: [
                Text(
                  widget.trip.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Boarding at ${widget.trip.stopName(widget.stopSequence)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),

          if (_busy)
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Column(
              children: [
                Text(
                  '$_accepted boarded this session',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, _accepted),
                  icon: const Icon(Icons.done, color: Colors.white),
                  label: const Text('Done scanning', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.white, width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    backgroundColor: Colors.black.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.65);
    const scanAreaSize = 260.0;
    final backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: scanAreaSize,
      height: scanAreaSize,
    );
    final cutoutPath = Path()..addRRect(RRect.fromRectAndRadius(cutoutRect, const Radius.circular(20)));
    canvas.drawPath(Path.combine(PathOperation.difference, backgroundPath, cutoutPath), paint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawRRect(RRect.fromRectAndRadius(cutoutRect, const Radius.circular(20)), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
