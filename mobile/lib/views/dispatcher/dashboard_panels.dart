import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/design/components/status_chip.dart';
import '../../core/design/tokens.dart';
import '../../data/repositories/operations_repository.dart';

/// The pieces of the Dispatcher's dashboard (brief 9). Each takes what the
/// screen loaded and reports a tap back; the screen runs the call and
/// reloads, so every panel shows the server's state, never a guess.

final _peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
final _time = DateFormat('h:mm a');

/// A white band with a small caps heading, like the passenger list's.
class DashPanel extends StatelessWidget {
  const DashPanel({super.key, required this.title, required this.children, this.trailing});
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: AppColors.surfaceRaised,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(title.toUpperCase(),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 1.2)),
            ),
            ?trailing,
          ]),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ]),
      );
}

// ------------------------------------------------- aboard against listed
/// Before departure: the camera's count aboard against the list. More
/// aboard than listed stops Depart until each boarding is listed (with a
/// destination) or given a reason (brief 2.4, 6.1).
class DoorCheckPanel extends StatelessWidget {
  const DoorCheckPanel({
    super.key,
    required this.check,
    required this.busy,
    required this.onList,
    required this.onExplain,
    required this.onCrew,
  });

  final DoorCheck check;
  final bool busy;
  final ValueChanged<UnlistedBoarding> onList;
  final ValueChanged<UnlistedBoarding> onExplain;
  final ValueChanged<bool> onCrew;

  @override
  Widget build(BuildContext context) {
    final c = check;
    final pending = c.unlisted.where((u) => u.isPending).toList();
    return DashPanel(title: 'Camera count against the list', children: [
      Row(children: [
        _big('${c.aboard}', 'aboard (camera)', c.excess > 0 ? AppColors.danger : AppColors.textPrimary),
        _big('${c.listed + c.explained}', c.explained > 0 ? 'listed or explained' : 'listed', AppColors.primary),
      ]),
      const SizedBox(height: AppSpacing.sm),
      if (c.excess > 0)
        _note(Icons.warning_amber_rounded, AppColors.danger,
            '${c.excess} more aboard than listed. Add each person to the list with where they get off, '
            'or give a reason. Depart waits until then.')
      else if (c.aboard < c.listed)
        _note(Icons.info_outline, AppColors.textMuted,
            'Fewer aboard than listed: no-shows. Nothing to do.'),
      for (final u in pending)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Row(children: [
            Expanded(child: Text('Boarded ${_time.format(u.at)}, not on the list',
                style: const TextStyle(fontWeight: FontWeight.w600))),
            TextButton(onPressed: busy ? null : () => onExplain(u), child: const Text('Reason')),
            FilledButton(onPressed: busy ? null : () => onList(u), child: const Text('Add to list')),
          ]),
        ),
      for (final u in c.unlisted.where((u) => !u.isPending))
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            '${_time.format(u.at)}: ${u.resolution == 'listed' ? 'added to the list' : 'reason given: "${u.note ?? ''}"'}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ),
      const Divider(height: AppSpacing.xl),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: c.crewAboard,
        onChanged: busy ? null : onCrew,
        title: const Text('I am riding in the van as crew', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Logged, not counted as a passenger or toward the van\'s seats.'),
      ),
    ]);
  }

  Widget _big(String value, String label, Color colour) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: colour)),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ]),
      );
}

Widget _note(IconData icon, Color colour, String text) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colour),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: TextStyle(color: colour, fontSize: 13.5, fontWeight: FontWeight.w600))),
      ],
    );

// ------------------------------------------------------------ home pickup
/// The trip's home pickups (brief 2.6): activate at the terminal, mark the
/// van at the pin, close boarded or no-show, and confirm a payment
/// screenshot the relative sent.
class HomePickupsPanel extends StatelessWidget {
  const HomePickupsPanel({
    super.key,
    required this.pickups,
    required this.departed,
    required this.busy,
    required this.onAction,
  });

  final List<HomePickup> pickups;
  final bool departed;
  final bool busy;

  /// (pickup, action): activate | arrived | boarded | no_show | proof | confirm
  final void Function(HomePickup, String) onAction;

  @override
  Widget build(BuildContext context) {
    return DashPanel(title: 'Home pickups', children: [
      for (final (i, p) in pickups.indexed) ...[
        if (i > 0) const Divider(height: AppSpacing.xl),
        Row(children: [
          Expanded(child: Text(p.beneficiaryName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          StatusChip(_status(p.status), tone: _tone(p.status)),
        ]),
        const SizedBox(height: 2),
        Text('${p.beneficiaryContact} · pin ${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        if (p.note != null) Text('"${p.note}"', style: const TextStyle(fontSize: 13)),
        if (p.hasProof)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(p.proofConfirmed ? 'Payment screenshot confirmed' : 'Payment screenshot sent, not yet confirmed',
                style: TextStyle(
                    fontSize: 13, color: p.proofConfirmed ? AppColors.success : AppColors.warning,
                    fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
          if (p.hasProof) OutlinedButton(onPressed: busy ? null : () => onAction(p, 'proof'), child: const Text('View screenshot')),
          if (p.hasProof && !p.proofConfirmed && !departed)
            FilledButton.tonal(onPressed: busy ? null : () => onAction(p, 'confirm'), child: const Text('Confirm payment')),
          if (p.status == 'requested' && !departed)
            FilledButton(onPressed: busy ? null : () => onAction(p, 'activate'), child: const Text('Activate')),
          if (p.status == 'activated' && departed)
            FilledButton(onPressed: busy ? null : () => onAction(p, 'arrived'), child: const Text('Van is at the pin')),
          if (p.status == 'arrived') ...[
            FilledButton(onPressed: busy ? null : () => onAction(p, 'boarded'), child: const Text('Boarded')),
            OutlinedButton(onPressed: busy ? null : () => onAction(p, 'no_show'), child: const Text('No-show')),
          ],
        ]),
        if (p.status == 'requested' && !departed)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xs),
            child: Text('Scanning the relative\'s ticket activates it too. Not activated by departure, it is a no-show.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
          ),
      ],
    ]);
  }

  static String _status(String s) => switch (s) {
        'requested' => 'NOT ACTIVATED',
        'activated' => 'ACTIVATED',
        'arrived' => 'AT THE PIN',
        'boarded' => 'BOARDED',
        'no_show' => 'NO-SHOW',
        _ => s.toUpperCase(),
      };

  static StatusTone _tone(String s) => switch (s) {
        'boarded' => StatusTone.success,
        'activated' || 'arrived' => StatusTone.info,
        'no_show' || 'cancelled' => StatusTone.danger,
        _ => StatusTone.warning,
      };
}

// ------------------------------------------------------------------ rental
class RentalPanel extends StatelessWidget {
  const RentalPanel({super.key, required this.rental, required this.busy, required this.onCash});
  final Rental rental;
  final bool busy;
  final VoidCallback onCash;

  @override
  Widget build(BuildContext context) {
    final r = rental;
    final paid = r.paymentStatus == 'paid';
    return DashPanel(
      title: 'Van rental',
      trailing: StatusChip(paid ? 'FEE PAID' : 'FEE UNPAID', tone: paid ? StatusTone.success : StatusTone.warning),
      children: [
        Text(r.customerName ?? 'The renter', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        if (r.customerContact != null) Text(r.customerContact!, style: const TextStyle(color: AppColors.textMuted)),
        const SizedBox(height: AppSpacing.xs),
        Text('${r.pickupAddress} → ${r.destinationAddress} · ${r.passengerCount} passengers'),
        if (r.fee != null) Text('Fee ${_peso.format(r.fee)}', style: const TextStyle(fontWeight: FontWeight.w700)),
        if (!paid && r.fee != null) ...[
          const SizedBox(height: AppSpacing.sm),
          FilledButton.icon(
            onPressed: busy ? null : onCash,
            icon: const Icon(Icons.payments_outlined),
            label: Text('Collected ${_peso.format(r.fee)} in cash'),
          ),
          const Text('Start waits for the fee.', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------ A2Z's share
/// What the Dispatcher hands to the Cashier before Start: A2Z's share of
/// each line of the list (brief 2.1). The operator's dispute of a line is
/// recorded here, until the payment.
class SharePanel extends StatelessWidget {
  const SharePanel({
    super.key,
    required this.share,
    required this.disputedLines,
    required this.busy,
    required this.onDispute,
  });

  final TripShare share;
  final Set<String> disputedLines;
  final bool busy;
  final ValueChanged<ShareLine> onDispute;

  @override
  Widget build(BuildContext context) {
    final s = share;
    final (label, tone) = switch (s.paymentStatus) {
      'paid' => ('PAID', StatusTone.success),
      'overridden' => ('BLOCK LIFTED', StatusTone.warning),
      'left_unpaid' => ('LEFT UNPAID', StatusTone.danger),
      _ => ('NOT PAID', StatusTone.warning),
    };
    return DashPanel(title: 'A2Z\'s share', trailing: StatusChip(label, tone: tone), children: [
      if (s.amountDue > 0)
        Text('Hand ${_peso.format(s.amountDue)} to the Cashier', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))
      else
        const Text('Nothing to hand over now.', style: TextStyle(fontWeight: FontWeight.w600)),
      if (s.disputed > 0)
        Text('${_peso.format(s.disputed)} disputed: waits for the Terminal Manager.',
            style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600)),
      const SizedBox(height: AppSpacing.sm),
      for (final l in s.lines)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(
              child: Text('${l.count} × ${_peso.format(l.fare)} to ${l.destination}${l.isTopUp ? ' (top-up)' : ''}',
                  style: const TextStyle(fontSize: 13.5)),
            ),
            Text(_peso.format(l.share), style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: AppSpacing.xs),
            disputedLines.contains(l.lineId)
                ? const Padding(
                    padding: EdgeInsets.only(left: AppSpacing.sm),
                    child: StatusChip('DISPUTED', tone: StatusTone.warning),
                  )
                : IconButton(
                    tooltip: 'Record the operator\'s dispute',
                    onPressed: busy ? null : () => onDispute(l),
                    icon: const Icon(Icons.gavel_outlined, size: 20),
                  ),
          ]),
        ),
    ]);
  }
}

// --------------------------------------------------------- driving flags
class FlagsPanel extends StatelessWidget {
  const FlagsPanel({super.key, required this.flags, required this.busy, required this.onDispute});
  final List<TripFlag> flags;
  final bool busy;
  final ValueChanged<TripFlag> onDispute;

  @override
  Widget build(BuildContext context) {
    return DashPanel(title: 'Driving flags', children: [
      const Text('For review by the Terminal Manager, not proof of misconduct.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
      for (final f in flags)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Row(children: [
            Expanded(
              child: Text('${f.kind} at ${_time.format(f.start)}${f.place != null ? ', ${f.place}' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (f.disputeStatus == 'open')
              const StatusChip('DISPUTED', tone: StatusTone.warning)
            else if (f.reviewStatus == 'dismissed')
              const StatusChip('DISMISSED', tone: StatusTone.success)
            else
              TextButton(onPressed: busy ? null : () => onDispute(f), child: const Text('Dispute')),
          ]),
        ),
    ]);
  }
}
