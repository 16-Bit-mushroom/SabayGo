import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/fleet_repository.dart';
import '../remittance/record_payment_dialog.dart';

/// A trip's everyday steps, shared by the trip sheet's row button and the
/// trip's detail panel (11 Nov), so both ask the same questions and say
/// the same things: assign, record payment, start, depart.
class TripActions {
  const TripActions(this.trip, this.onChanged);

  final TripBoardEntry trip;

  /// Refreshes whoever shows the trip after a step succeeds.
  final VoidCallback onChanged;

  /// Runs one call, reports the result through the app-wide messenger and
  /// refreshes. A refusal is shown in the server's own words.
  Future<bool> run(BuildContext context, Future<void> Function() call, String done) async {
    final ok = await runAction(context, call, done);
    if (ok) onChanged();
    return ok;
  }

  /// The Terminal Manager lets this trip be assigned and started before
  /// its terminal fees are recorded. A written reason is required; it is
  /// kept with the trip and the Cashier is told. The fees stay owed.
  Future<bool> liftBlock(BuildContext context) async {
    final dispatch = context.read<DispatchRepository>();
    final reason = await askText(
      context,
      title: 'Lift the payment block?',
      intro: 'This trip may then start before its terminal fees are recorded. They stay on the '
          'van\'s statement. Your reason is kept with the trip and the Cashier is told.',
      label: 'Reason',
      confirmLabel: 'Lift block',
    );
    if (reason == null || reason.trim().isEmpty || !context.mounted) return false;
    return run(context, () => dispatch.overridePayment(trip.tripId, note: reason.trim()),
        'Payment block lifted for this trip.');
  }

  /// From the sheet's cells: a van, a Dispatcher or both, saved at once.
  /// The server checks the van is validated and its last fees recorded.
  Future<bool> assign(BuildContext context, {String? vanId, String? dispatcherId}) {
    final dispatch = context.read<DispatchRepository>();
    return run(context, () => dispatch.assign(trip.tripId, vanId: vanId, dispatcherId: dispatcherId),
        vanId != null && dispatcherId != null ? 'Van and Dispatcher saved.' : 'Saved.');
  }

  Future<void> start(BuildContext context) async {
    final dispatch = context.read<DispatchRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start this trip?'),
        content: Text(
          '${trip.plateNumber}, driven by ${trip.operatorName ?? 'its operator'}, with '
          '${trip.dispatcherName ?? 'the assigned Dispatcher'}. Starting copies the operator\'s '
          'name and licence and the plate onto the trip. Check the plate against the van.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start trip')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    var warnings = const <String>[];
    final started = await run(context, () async {
      warnings = await dispatch.start(trip.tripId);
    }, 'Trip started.');
    if (!started || warnings.isEmpty || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: AppColors.warning),
        title: const Text('Started, with warnings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final w in warnings) Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text('• $w'),
          )],
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  /// The same Record payment dialog as Money's (10 Nov): one place per
  /// job. Before departure the payment is the trip's (it also locks the
  /// trip's list); after, it goes on the van's statement.
  Future<void> recordPayment(BuildContext context) async {
    final dispatch = context.read<DispatchRepository>();
    final TripShare share;
    try {
      share = await dispatch.share(trip.tripId, tripStatus: trip.status);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is ApiException ? e.message : 'What is due could not be loaded. Try again.')));
      }
      return;
    }
    if (!context.mounted) return;
    final plate = trip.plateNumber ?? 'the van';
    final entry = await askPayment(
        context,
        PaymentFacts(
          plate: plate,
          amountDue: share.amountDue,
          disputed: share.disputed,
          operatorShareOwed: share.operatorShareOwed,
          operatorShareHeld: share.operatorShareHeld,
          operatorShareOver: share.operatorShareOver,
          intro: share.beforeDeparture
              ? 'The terminal fees ${trip.dispatcherName ?? 'the Dispatcher'} hands over for $plate: A2Z\'s '
                  '15 % of the lines below, the DCOTT ticket, and the day\'s parking if unpaid. Recording '
                  'them locks the passenger list and opens Start.'
              : 'This trip left without its terminal fees recorded. The payment goes on $plate\'s '
                  'statement for the day.',
          lines: [
            for (final l in share.lines)
              ('${l.passengerCount} × ${peso.format(l.farePerPassenger)} to ${l.destination}'
                  '${l.isTopUp ? ' · top-up' : ''}', l.shareAmount),
          ],
        ));
    if (entry == null || !context.mounted) return;
    final settles = (double.tryParse(entry.amount) ?? 0) >= share.amountDue - 0.004;
    await run(
        context,
        () => dispatch.recordPayment(share,
            amount: entry.amount, reference: entry.reference, operatorShare: entry.operatorShare,
            handedOverBy: entry.handedOverBy),
        // Start opens with the fees and the window both (12 Nov UI run: the
        // message said "Start is open" half an hour before it was).
        share.beforeDeparture && settles
            ? DateTime.now().isBefore(trip.startOpensAt)
                ? 'Payment recorded for $plate. Start opens at ${_clock(trip.startOpensAt)}.'
                : 'Payment recorded for $plate. Start is open.'
            : 'Payment recorded for $plate.');
  }

  Future<void> depart(BuildContext context) async {
    final dispatch = context.read<DispatchRepository>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Depart now?'),
        content: const Text('Boarding closes and the passenger list locks. Nobody boards after this, and '
            'paid seats still count in the terminal fees. No refund is issued.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Depart')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await run(context, () => dispatch.depart(trip.tripId), 'Trip departed.');
  }

}

/// The vans and Dispatchers a trip may be given: validated and active
/// (brief 4.2 rule 6). The server checks again, the operator's record too.
Future<(List<Van>, List<StaffMember>)> assignableRoster(FleetRepository fleet) async {
  final results = await Future.wait([fleet.listVans(), fleet.listCrew(role: 'dispatcher')]);
  final vans = (results[0] as List<Van>)
      .where((v) => v.validationStatus == 'validated' && v.operationalStatus == 'active')
      .toList();
  final crew = (results[1] as List<StaffMember>)
      .where((s) => s.validationStatus == 'validated' && s.employmentStatus == 'active')
      .toList();
  return (vans, crew);
}

/// "11:00 AM", as the sheet shows a time.
String _clock(DateTime at) {
  final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
  return '$h:${at.minute.toString().padLeft(2, '0')} ${at.hour < 12 ? 'AM' : 'PM'}';
}
