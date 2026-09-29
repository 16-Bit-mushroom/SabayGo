import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/design/components/app_card.dart';
import '../../core/design/components/info_row.dart';
import '../../core/design/components/journey_strip.dart';
import '../../core/design/components/money.dart';
import '../../core/design/components/status_band.dart';
import '../../core/design/components/status_chip.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../core/util/when.dart';
import '../../data/repositories/booking_repository.dart';
import '../../models/transit_node_model.dart';
import '../../models/uv_trip_model.dart';
import '../../viewmodels/auth_provider.dart';
import '../../viewmodels/ticket_viewmodel.dart';
import '../tracking/live_map_screen.dart';

class TicketScreen extends StatefulWidget {
  final UvTripModel bookedTrip;

  /// The booking just created. Carries the ticket number, the fare that
  /// was actually charged, and the QR payload. Null when the screen is
  /// opened from a list rather than straight after reserving.
  final ReservationResult? reservation;

  /// When check-in opens at the passenger's own stop (from /bookings/mine).
  final DateTime? checkinOpensAt;

  const TicketScreen({
    super.key,
    required this.bookedTrip,
    this.reservation,
    this.checkinOpensAt,
  });

  /// Open an existing booking from the list. Everything the ticket shows
  /// is on the booking itself, so the trip is rebuilt from it rather than
  /// fetched again.
  TicketScreen.fromBooking({super.key, required BookingSummary booking})
      : bookedTrip = UvTripModel(
          id: booking.tripId,
          tripLabel: booking.routeName,
          departureTime: booking.departure,
          origin: TransitNodeModel(
            id: 'stop-${booking.boardingStop}',
            name: booking.boardingTerminal,
            area: '',
            stopSequence: booking.boardingStop,
          ),
          destination: TransitNodeModel(
            id: 'stop-${booking.alightingStop}',
            name: booking.alightingTerminal,
            area: '',
            stopSequence: booking.alightingStop,
          ),
          boardingStop: booking.boardingStop,
          alightingStop: booking.alightingStop,
          availableSeats: 0,
          approximateFare: booking.fare,
        ),
        reservation = ReservationResult(
          bookingId: booking.bookingId,
          ticketNumber: booking.ticketNumber,
          fare: booking.fare,
          status: booking.status,
          qrPayload: booking.qrPayload,
        ),
        checkinOpensAt = booking.checkinOpensAt;

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  late final TicketViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiClient>();
    _viewModel = TicketViewModel(
      repository: BookingRepository(api),
      bookedTrip: widget.bookedTrip,
      reservation: widget.reservation,
      checkinOpensAt: widget.checkinOpensAt,
    )..addListener(_onStateChanged);
  }

  void _onStateChanged() => setState(() {});

  @override
  void dispose() {
    _viewModel.removeListener(_onStateChanged);
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = _viewModel.trip;
    final profile = context.watch<AuthProvider>().profile;
    final passengerName = profile?.displayName ?? profile?.email ?? '—';
    final state = _state();

    return Scaffold(
      appBar: AppBar(title: const Text('Boarding pass')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter, AppSpacing.lg,
            AppSpacing.gutter, AppSpacing.section,
          ),
          children: [
            // State first, and only once. Whatever else is on this screen,
            // the passenger's question is "am I sorted, and if not, what do
            // I do" — so that is the top of the page, in a sentence.
            StatusBand(
              tone: state.tone,
              icon: state.icon,
              title: state.title,
              body: state.body,
              // The status changes underneath the passenger when a payment
              // webhook lands mid-poll.
              liveRegion: true,
            ),
            ?_message(),
            const SizedBox(height: AppSpacing.lg),
            _pass(context, trip, passengerName),
            const SizedBox(height: AppSpacing.xl),
            ..._actions(context, trip),
          ],
        ),
      ),
    );
  }

  /// The pass: the QR the conductor scans, then the journey it is for.
  ///
  /// One card, two halves, a tear line between them — the QR half is what
  /// gets held up at the door, the details half is what gets read on the
  /// way there.
  Widget _pass(BuildContext context, UvTripModel trip, String passengerName) {
    final text = Theme.of(context).textTheme;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.xxl, AppSpacing.xl, AppSpacing.xl,
            ),
            child: Column(
              children: [
                _qr(),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _viewModel.ticketNumber.isNotEmpty
                      ? _viewModel.ticketNumber
                      : trip.id,
                  textAlign: TextAlign.center,
                  style: text.titleMedium!.copyWith(
                    letterSpacing: 1.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Show this to the conductor when you board',
                  textAlign: TextAlign.center,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          const _TearLine(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                JourneyStrip(
                  origin: trip.origin.name,
                  destination: trip.destination.name,
                  originNote: 'Departs ${clockTime(trip.departureTime)}',
                  destinationNote: trip.estimatedArrivalTime == null
                      // The search response carries no arrival: it depends
                      // on where the passenger gets off, and inventing one
                      // here would be a promise the route offsets never
                      // made.
                      ? null
                      : 'Arrives about '
                          '${clockTime(trip.estimatedArrivalTime!)}',
                ),
                const SizedBox(height: AppSpacing.xl),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.lg),
                AppInfoRow(label: 'Passenger', value: passengerName),
                const SizedBox(height: AppSpacing.md),
                AppInfoRow(
                  label: 'Fare',
                  value: Money.format(_viewModel.fare),
                  valueWidget: Money(
                    _viewModel.fare,
                    style: text.bodyLarge!
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppInfoRow(
                  label: 'Payment',
                  value: _viewModel.isAwaitingPayment
                      ? 'Not paid yet'
                      : 'Paid via PayMongo',
                ),
                if (trip.plateNumber != null ||
                    trip.operatorName != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppInfoRow(
                    label: 'Van',
                    value: trip.plateNumber ?? trip.operatorName!,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qr() {
    if (_viewModel.isAwaitingPayment) {
      return Column(
        children: [
          const Icon(Icons.lock_outline, size: 64, color: AppColors.warning),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Your QR ticket appears here once the payment is confirmed.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  color: AppColors.textMuted,
                ),
          ),
        ],
      );
    }

    if (_viewModel.hasUsableTicket) {
      return Semantics(
        // A blind passenger still holds the phone up to be scanned, so the
        // code needs naming rather than hiding.
        label: 'QR boarding ticket. Show this to the conductor.',
        image: true,
        excludeSemantics: true,
        child: QrImageView(
          data: _viewModel.qrPayload!,
          size: 184,
          backgroundColor: Colors.white,
        ),
      );
    }

    return Opacity(
      opacity: _viewModel.isCancelled ? 0.25 : 1,
      child: const Icon(Icons.qr_code_2, size: 120, color: AppColors.primary),
    );
  }

  /// Feedback from the last action, kept apart from the status band.
  ///
  /// The band says what the booking *is*; this says what just happened when
  /// the passenger pressed something — "you are too far from the terminal"
  /// is not a status, and reading it as one would leave it on screen after
  /// it stopped being true.
  Widget? _message() {
    final error = _viewModel.error;
    final note = _viewModel.checkInMessage;
    if (error == null && note == null) return null;

    final isError = error != null;
    final tone = isError
        ? StatusTone.danger
        : _viewModel.isCheckedIn
            ? StatusTone.success
            : StatusTone.warning;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              size: 18,
              color: tone.fg,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                error ?? note!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(color: tone.fg, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Actions, in the order they become relevant: pay, arrive, board.
  ///
  /// Exactly one filled button at a time. Two competing primary actions is
  /// how someone at a van door taps the wrong one.
  List<Widget> _actions(BuildContext context, UvTripModel trip) {
    final actions = <Widget>[];

    if (_viewModel.isAwaitingPayment) {
      actions.add(
        FilledButton.icon(
          onPressed:
              _viewModel.isStartingCheckout ? null : _viewModel.startCheckout,
          icon: _viewModel.isStartingCheckout
              ? const _Spinner()
              : const Icon(Icons.lock_outline),
          label: Text(
            _viewModel.isStartingCheckout
                ? 'Opening PayMongo…'
                : 'Pay ${Money.format(_viewModel.fare)}',
          ),
        ),
      );
      if (_viewModel.isPolling) {
        actions.add(
          Semantics(
            liveRegion: true,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Spinner(color: AppColors.primary),
                SizedBox(width: AppSpacing.md),
                Text(
                  'Waiting for the payment to be confirmed…',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        );
      } else if (_viewModel.hasLiveBooking) {
        actions.add(
          TextButton(
            onPressed: _viewModel.refreshStatus,
            child: const Text('Still pending — check again'),
          ),
        );
      }
    } else if (_viewModel.canCheckIn) {
      actions.add(
        FilledButton.icon(
          onPressed: _viewModel.isCheckingIn ? null : _viewModel.checkIn,
          icon: _viewModel.isCheckingIn
              ? const _Spinner()
              : const Icon(Icons.location_on_outlined),
          label: Text(
            _viewModel.isCheckingIn ? 'Checking in…' : "I'm at the terminal",
          ),
        ),
      );
      if (_viewModel.checkinOpensAt != null) {
        actions.add(
          Text(
            'Check-in opens '
            '${clockTime(_viewModel.checkinOpensAt!)} at '
            '${trip.origin.name}. It is a heads-up for the conductor, not a '
            'requirement for boarding.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      }
    }

    // Offered from the moment the booking is paid for, not only once the van
    // is moving: a passenger deciding when to leave the house needs to see
    // that it has not started reporting yet just as much as they need a
    // position.
    if (!_viewModel.isAwaitingPayment && !_viewModel.isCancelled) {
      actions.add(
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LiveMapScreen(
                tripId: trip.id,
                title: 'Track the van',
                boardingStop: trip.boardingStop,
                alightingStop: trip.alightingStop,
              ),
            ),
          ),
          icon: const Icon(Icons.map_outlined),
          label: const Text('Track the van'),
        ),
      );
    }

    // D.2: an accidental "I'm here" can be taken back until the conductor
    // scans the ticket.
    if (_viewModel.canUndoCheckIn) {
      actions.add(
        TextButton.icon(
          onPressed:
              _viewModel.isUndoingCheckIn ? null : _viewModel.undoCheckIn,
          icon: const Icon(Icons.undo, size: 18),
          label: Text(
            _viewModel.isUndoingCheckIn ? 'Undoing…' : 'Undo check-in',
          ),
        ),
      );
    }

    if (!_viewModel.isCancelled &&
        !_viewModel.isCheckedIn &&
        !_viewModel.isBoarded) {
      actions.add(
        TextButton.icon(
          onPressed: _confirmCancel,
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Cancel booking'),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
        ),
      );
    }

    return [
      for (final (i, action) in actions.indexed) ...[
        if (i > 0) const SizedBox(height: AppSpacing.md),
        action,
      ],
    ];
  }

  /// Status, as a sentence with a next step.
  ({StatusTone tone, IconData icon, String title, String body}) _state() {
    if (_viewModel.isCancelled) {
      return (
        tone: StatusTone.danger,
        icon: Icons.cancel_outlined,
        title: 'Cancelled',
        body: 'The space has been released. The cooperative does not issue '
            'refunds, so any fare already paid is not returned.',
      );
    }
    if (_viewModel.isAwaitingPayment) {
      return (
        tone: StatusTone.warning,
        icon: Icons.schedule,
        title: 'Waiting for payment',
        body: 'Your space is held while the payment is pending. Pay to get '
            'the QR ticket the conductor scans.',
      );
    }
    if (_viewModel.isBoarded) {
      return (
        tone: StatusTone.success,
        icon: Icons.check_circle_outline,
        title: 'On board',
        body: 'The conductor has scanned your ticket. Have a safe trip.',
      );
    }
    if (_viewModel.isCheckedIn) {
      return (
        tone: StatusTone.success,
        icon: Icons.how_to_reg_outlined,
        title: 'Checked in at the terminal',
        body: 'The conductor can see you are waiting. Show the QR when the '
            'van is ready to board.',
      );
    }
    return (
      tone: StatusTone.info,
      icon: Icons.confirmation_number_outlined,
      title: 'Confirmed',
      body: _viewModel.canCheckIn
          ? 'Your space is booked. Tap "I\'m at the terminal" when you get '
              'there, then show the QR to the conductor.'
          : 'Your space is booked. Show the QR to the conductor when you '
              'board.',
    );
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text(
          'Your space will be released. The cooperative does not issue '
          'refunds, so any fare already paid is not returned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (ok == true) await _viewModel.cancelTicket();
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({this.color = Colors.white});

  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
}

/// The tear line across the pass.
///
/// Drawn rather than assembled: the old one built `width / 10` SizedBoxes
/// inside a LayoutBuilder on every frame, and the two rounded notches at
/// either end were containers filled with the scaffold colour, so they only
/// looked like cut-outs as long as nothing behind the card ever changed.
class _TearLine extends StatelessWidget {
  const _TearLine();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(
          painter: _DashPainter(),
          child: const SizedBox(height: 1.5, width: double.infinity),
        ),
      );
}

class _DashPainter extends CustomPainter {
  static const _dash = 5.0;
  static const _gap = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.divider
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    for (var x = AppSpacing.lg; x < size.width - AppSpacing.lg; x += _dash + _gap) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset((x + _dash).clamp(0, size.width - AppSpacing.lg), size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => false;
}
