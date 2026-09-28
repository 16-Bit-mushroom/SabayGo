import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
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

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Boarding Pass'),
        backgroundColor: AppColors.primary,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // --- THE DIGITAL TICKET ---
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _headerColor(),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              trip.operatorName ?? trip.plateNumber ?? "—",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _headerTextColor(),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _statusLabel(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _headerTextColor(),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // QR Code / Payment Area
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          if (_viewModel.hasLiveBooking && !_viewModel.isCancelled)
                            _buildGeofenceBadge(),

                          const SizedBox(height: 16),

                          _buildQrArea(),

                          const SizedBox(height: 12),
                          Text(
                            _viewModel.ticketNumber.isNotEmpty
                                ? _viewModel.ticketNumber
                                : trip.id,
                            style: const TextStyle(
                              letterSpacing: 1.2,
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          const Text(
                            'Show this to the conductor when you board',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 13),
                          ),

                          if (_viewModel.checkInMessage != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _viewModel.checkInMessage!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _viewModel.isCheckedIn
                                    ? AppColors.success
                                    : AppColors.warning,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (_viewModel.error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _viewModel.error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Divider with cutouts
                    Row(
                      children: [
                        Container(height: 20, width: 10, decoration: BoxDecoration(color: AppColors.surface, borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)))),
                        Expanded(child: LayoutBuilder(builder: (context, constraints) {
                          return Flex(
                            direction: Axis.horizontal,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate((constraints.constrainWidth() / 10).floor(), (index) => const SizedBox(width: 5, height: 1, child: DecoratedBox(decoration: BoxDecoration(color: AppColors.divider)))),
                          );
                        })),
                        Container(height: 20, width: 10, decoration: BoxDecoration(color: AppColors.surface, borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)))),
                      ],
                    ),

                    // Trip Info with Icons
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildInfoRow(Icons.person_outline, 'Passenger', passengerName),
                          const SizedBox(height: 12),

                          _buildInfoRow(Icons.trip_origin, 'Origin', trip.origin.name, iconColor: AppColors.success),
                          const SizedBox(height: 12),
                          _buildInfoRow(Icons.location_on, 'Destination', trip.destination.name, iconColor: AppColors.danger),
                          const SizedBox(height: 12),
                          _buildInfoRow(Icons.departure_board, 'Departure', _formatTime(trip.departureTime)),
                          const SizedBox(height: 12),
                          _buildInfoRow(Icons.flag_outlined, 'Est. Arrival', _formatTime(trip.estimatedArrivalTime)),

                          const SizedBox(height: 20),

                          _buildPaymentBox(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              if (_viewModel.isAwaitingPayment) ...[
                FilledButton.icon(
                  onPressed: _viewModel.isStartingCheckout ? null : _viewModel.startCheckout,
                  icon: _viewModel.isStartingCheckout
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.payment),
                  label: Text(_viewModel.isStartingCheckout ? 'Opening PayMongo…' : 'Pay ₱${_viewModel.fare.toStringAsFixed(2)}'),
                ),
                if (_viewModel.isPolling) ...[
                  const SizedBox(height: 12),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('Waiting for payment confirmation…',
                          style: TextStyle(color: AppColors.textMuted)),
                    ],
                  ),
                ] else if (_viewModel.hasLiveBooking) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _viewModel.refreshStatus,
                    child: const Text('Still pending — check again'),
                  ),
                ],
                const SizedBox(height: 12),
              ],

              // Live tracking. Offered from the moment the booking is paid
              // for, not only once the van is moving: a passenger deciding
              // when to leave the house needs to see that it has not
              // started reporting yet just as much as they need a position.
              if (!_viewModel.isAwaitingPayment && !_viewModel.isCancelled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
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
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

              if (_viewModel.canCheckIn && _viewModel.checkinOpensAt != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Check-in opens ${DateFormat('h:mm a').format(_viewModel.checkinOpensAt!)} at ${trip.origin.name}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                  ),
                ),
              if (_viewModel.canCheckIn)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: FilledButton.icon(
                    onPressed: _viewModel.isCheckingIn ? null : _viewModel.checkIn,
                    icon: _viewModel.isCheckingIn
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.location_on),
                    label: Text(_viewModel.isCheckingIn ? 'Checking in…' : "I'm at the terminal"),
                  ),
                ),

              // D.2: an accidental "I'm here" can be taken back until the
              // conductor scans the ticket.
              if (_viewModel.canUndoCheckIn)
                TextButton.icon(
                  onPressed: _viewModel.isUndoingCheckIn ? null : _viewModel.undoCheckIn,
                  icon: const Icon(Icons.undo, size: 18),
                  label: Text(_viewModel.isUndoingCheckIn ? 'Undoing…' : 'Undo check-in'),
                ),

              // Cancel Button
              if (!_viewModel.isCancelled && !_viewModel.isCheckedIn && !_viewModel.isBoarded)
                TextButton.icon(
                  onPressed: _confirmCancel,
                  icon: const Icon(Icons.cancel_outlined,
                      color: AppColors.danger),
                  label: const Text(
                    'Cancel booking',
                    style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                )
            ],
          ),
        ),
      ),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel booking',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await _viewModel.cancelTicket();
  }

  Color _headerColor() {
    if (_viewModel.isCancelled) return AppColors.dangerContainer;
    if (_viewModel.isAwaitingPayment) return AppColors.warningContainer;
    return AppColors.successContainer;
  }

  Color _headerTextColor() {
    if (_viewModel.isCancelled) return AppColors.danger;
    if (_viewModel.isAwaitingPayment) return AppColors.warning;
    return AppColors.success;
  }

  String _statusLabel() => switch (_viewModel.status) {
        'pending' => 'AWAITING PAYMENT',
        'confirmed' => 'CONFIRMED',
        'checked_in' => 'CHECKED IN',
        'boarded' => 'BOARDED',
        'cancelled' => 'CANCELLED',
        _ => _viewModel.status.toUpperCase(),
      };

  Widget _buildQrArea() {
    if (_viewModel.isAwaitingPayment) {
      return Column(
        children: [
          Icon(Icons.lock_clock, size: 96, color: AppColors.warning),
          const SizedBox(height: 8),
          const Text('Pay to unlock your QR ticket',
              style: TextStyle(color: AppColors.textMuted)),
        ],
      );
    }
    if (_viewModel.hasUsableTicket) {
      return QrImageView(
        data: _viewModel.qrPayload!,
        size: 160,
        backgroundColor: Colors.white,
      );
    }
    return Opacity(
      opacity: _viewModel.isCancelled ? 0.3 : 1.0,
      child: const Icon(Icons.qr_code_2, size: 120, color: AppColors.primary),
    );
  }

  Widget _buildGeofenceBadge() {
    final bool ready = _viewModel.isCheckedIn || _viewModel.isBoarded;
    final String label = _viewModel.isBoarded
        ? 'On Board'
        : _viewModel.isCheckedIn
            ? 'Checked in \u2014 ready to board'
            : 'Tap \u201cI\u2019m at the terminal\u201d when you arrive';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: ready
            ? AppColors.successContainer
            : AppColors.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(
            color: ready ? AppColors.success : AppColors.warning),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.check_circle : Icons.location_on,
            size: 16,
            color: ready ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: ready ? AppColors.success : AppColors.warning,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentBox() {
    final paid = !_viewModel.isAwaitingPayment && !_viewModel.isCancelled;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: paid ? AppColors.infoContainer : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: paid ? AppColors.info : AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(paid ? Icons.verified_user : Icons.hourglass_top,
                  color: paid ? AppColors.info : AppColors.textMuted,
                  size: 20),
              const SizedBox(width: 8),
              Text(
                paid ? 'Paid via PayMongo' : 'Payment pending',
                style: TextStyle(
                    color: paid ? AppColors.info : AppColors.textMuted,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Text(
            '₱${_viewModel.fare.toStringAsFixed(2)}',
            style: TextStyle(
                color: paid ? AppColors.info : AppColors.textMuted,
                fontWeight: FontWeight.bold,
                fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Color? iconColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: iconColor ?? AppColors.textMuted),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: AppColors.textMuted)),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return "—";
    return DateFormat('hh:mm a').format(dt);
  }
}
