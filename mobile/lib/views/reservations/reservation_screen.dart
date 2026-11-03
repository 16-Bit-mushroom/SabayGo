import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
import '../../viewmodels/reservation_viewmodel.dart';
import '../tracking/live_map_screen.dart';

/// One reservation (brief rev 721): the booking code the passenger gives
/// the Dispatcher, the fare, Unpaid or Paid, and when an unpaid seat is
/// released. A2Z takes cash only, at the terminal; there is no ticket to
/// scan and nothing to pay in the app.
class ReservationScreen extends StatefulWidget {
  final UvTripModel bookedTrip;

  /// The reservation just made, straight after reserving.
  final ReservationResult? reservation;

  /// The booking as listed, when opened from the reservations list.
  final BookingSummary? booking;

  const ReservationScreen({
    super.key,
    required this.bookedTrip,
    this.reservation,
  }) : booking = null;

  /// Open an existing booking from the list. Everything the screen shows
  /// is on the booking itself, so the trip is rebuilt from it rather than
  /// fetched again.
  ReservationScreen.fromBooking({super.key, required BookingSummary this.booking})
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
        reservation = null;

  @override
  State<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends State<ReservationScreen> {
  late final ReservationViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiClient>();
    _viewModel = ReservationViewModel(
      repository: BookingRepository(api),
      bookedTrip: widget.bookedTrip,
      reservation: widget.reservation,
      booking: widget.booking,
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
    final state = _state(trip);

    return Scaffold(
      appBar: AppBar(title: const Text('Reservation')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _viewModel.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter, AppSpacing.lg,
              AppSpacing.gutter, AppSpacing.section,
            ),
            children: [
              // State first, and only once: "am I sorted, and if not, what
              // do I do" is the passenger's question.
              StatusBand(
                tone: state.tone,
                icon: state.icon,
                title: state.title,
                body: state.body,
                // It changes underneath the passenger when the Dispatcher
                // marks the seat Paid.
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
      ),
    );
  }

  /// The booking code, then the journey it is for. The code is what the
  /// passenger says or shows at the van door; the details are read on the
  /// way there.
  Widget _pass(BuildContext context, UvTripModel trip, String passengerName) {
    final text = Theme.of(context).textTheme;
    final code = _viewModel.bookingCode;

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
                Text('Booking code', style: text.bodySmall),
                const SizedBox(height: AppSpacing.xs),
                Semantics(
                  label: 'Booking code ${code.split('').join(' ')}',
                  excludeSemantics: true,
                  child: SelectableText(
                    code.isEmpty ? '—' : code,
                    textAlign: TextAlign.center,
                    style: text.headlineMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: _viewModel.isCancelled ? AppColors.textMuted : AppColors.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (code.isNotEmpty)
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Booking code copied.')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                Text(
                  'Give this code or your name to the Dispatcher when you pay',
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
                  value: _viewModel.isPaid
                      ? 'Paid in cash${_viewModel.paidAt != null ? ' at ${clockTime(_viewModel.paidAt!)}' : ''}'
                      : 'Unpaid: cash to the Dispatcher',
                ),
                if (_viewModel.payBy != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppInfoRow(label: 'Pay before', value: clockTime(_viewModel.payBy!)),
                ],
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

  /// Actions, in the order they become relevant: arrive, track, cancel.
  ///
  /// Exactly one filled button at a time. Two competing primary actions is
  /// how someone at a van door taps the wrong one.
  List<Widget> _actions(BuildContext context, UvTripModel trip) {
    final actions = <Widget>[];
    final vm = _viewModel;

    if (vm.canCheckIn) {
      actions.add(
        FilledButton.icon(
          onPressed: vm.isCheckingIn ? null : vm.checkIn,
          icon: vm.isCheckingIn
              ? const _Spinner()
              : const Icon(Icons.location_on_outlined),
          label: Text(
            vm.isCheckingIn ? 'Checking in…' : "I'm at the terminal",
          ),
        ),
      );
      if (vm.checkinOpensAt != null) {
        actions.add(
          Text(
            'Check-in opens '
            '${clockTime(vm.checkinOpensAt!)} at '
            '${trip.origin.name}. It tells the Dispatcher you are there; it '
            'does not pay for or hold your seat.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      }
    }

    if (vm.hasLiveBooking && !vm.isPaid && vm.isActive) {
      actions.add(
        OutlinedButton.icon(
          onPressed: vm.isRefreshing ? null : vm.refresh,
          icon: vm.isRefreshing
              ? const _Spinner(color: AppColors.primary)
              : const Icon(Icons.refresh),
          label: const Text('I have paid — check again'),
        ),
      );
    }

    // Offered for any standing reservation: a passenger deciding when to
    // leave the house needs to see that the van has not started reporting
    // yet just as much as they need a position.
    if (vm.isActive) {
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

    // D.2: an accidental "I'm here" can be taken back.
    if (vm.canUndoCheckIn) {
      actions.add(
        TextButton.icon(
          onPressed: vm.isUndoingCheckIn ? null : vm.undoCheckIn,
          icon: const Icon(Icons.undo, size: 18),
          label: Text(
            vm.isUndoingCheckIn ? 'Undoing…' : 'Undo check-in',
          ),
        ),
      );
    }

    // Only an unpaid seat, before the list locks (the server says which).
    if (vm.canCancel && vm.isActive) {
      actions.add(
        TextButton.icon(
          onPressed: vm.isCancelling ? null : _confirmCancel,
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Cancel reservation'),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
        ),
      );
    } else if (vm.isPaid && vm.isActive) {
      actions.add(
        Text(
          'To cancel a paid seat, ask the Dispatcher in the chat. They hand '
          'back the cash.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
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
  ({StatusTone tone, IconData icon, String title, String body}) _state(UvTripModel trip) {
    final vm = _viewModel;
    if (vm.isCancelled) {
      return (
        tone: StatusTone.danger,
        icon: Icons.cancel_outlined,
        title: vm.wasReleased ? 'Released: not paid in time' : 'Cancelled',
        body: '${vm.cancelLabel ?? 'The reservation was cancelled.'} Book again '
            'if you still want to travel.',
      );
    }
    if (vm.status == 'no_show') {
      return (
        tone: StatusTone.info,
        icon: Icons.directions_bus_outlined,
        title: 'The van has departed',
        body: vm.isPaid
            ? 'This trip has left the terminal.'
            : 'The van left before this reservation was paid.',
      );
    }
    if (vm.status == 'completed') {
      return (
        tone: StatusTone.success,
        icon: Icons.check_circle_outline,
        title: 'Trip completed',
        body: 'Thank you for riding with A2Z.',
      );
    }
    if (vm.isBoarded) {
      return (
        tone: StatusTone.success,
        icon: Icons.check_circle_outline,
        title: 'On board',
        body: 'Have a safe trip.',
      );
    }
    if (vm.isPaid) {
      return (
        tone: StatusTone.success,
        icon: Icons.paid_outlined,
        title: 'Paid: you are on the passenger list',
        body: 'Board at ${trip.origin.name} before the van leaves at '
            '${clockTime(trip.departureTime)}.',
      );
    }
    final payBy = vm.payBy == null ? 'before the van leaves' : 'before ${clockTime(vm.payBy!)}';
    return (
      tone: StatusTone.warning,
      icon: Icons.payments_outlined,
      title: 'Reserved: pay at the terminal',
      body: 'Pay ${Money.format(vm.fare)} in cash to the Dispatcher at '
          '${trip.origin.name} $payBy. An unpaid reservation is released '
          'then and the space goes to someone else.',
    );
  }

  Future<void> _confirmCancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this reservation?'),
        content: const Text(
          'Your space will be released for someone else. You have not paid, '
          'so there is nothing to hand back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Cancel reservation'),
          ),
        ],
      ),
    );
    if (ok == true) await _viewModel.cancel();
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
