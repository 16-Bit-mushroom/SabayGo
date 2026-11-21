import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/design/components/status_chip.dart';
import '../../core/design/tokens.dart';
import '../../core/offline/seat_mark_queue.dart';
import '../../data/repositories/operations_repository.dart';

/// The cards of the Dispatcher's trip screen (brief 9). Since the 20 Nov
/// redesign each sits on one of the screen's tabs -- Boarding, Pickups or
/// Rental, Fees & flags -- instead of all eight stacked on one page. Each
/// takes what the screen loaded and reports a tap back; the screen runs
/// the call and reloads, so every card shows the server's state, never a
/// guess.

final _peso = NumberFormat.currency(locale: 'en_PH', symbol: '₱', decimalDigits: 2);
final _time = DateFormat('h:mm a');
const _tabular = [FontFeature.tabularFigures()];

/// A white card with a green edge, a title and an optional chip: the
/// app's card (mobile/DESIGN.md). [alert] is for something that blocks
/// the trip: the edge turns SOS red at 2 px, a change of weight as well
/// as hue, so it reads on a washed-out screen.
class DashCard extends StatelessWidget {
  const DashCard({super.key, required this.title, required this.children, this.trailing, this.alert = false});

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final bool alert;

  @override
  // A Material, not a decorated box: the switch row in the door camera
  // card needs one to draw its ink (ListTile asserts it).
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Material(
      color: AppColors.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: alert ? AppColors.danger : AppColors.edge, width: alert ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The chip may take at most a little over half the width, so a
            // long status ellipsises instead of squeezing the title.
            LayoutBuilder(
              builder: (context, box) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: box.maxWidth * 0.55),
                      child: trailing!,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ...children,
          ],
        ),
      ),
    ),
  );
}

/// One sentence in a tinted band: what a state means and what to do.
class DashNote extends StatelessWidget {
  const DashNote(this.text, {super.key, required this.tone, this.icon});

  final String text;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: tone.bg,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: tone.fg.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[Icon(icon, size: 18, color: tone.fg), const SizedBox(width: AppSpacing.sm)],
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: tone.fg, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35),
          ),
        ),
      ],
    ),
  );
}

/// A big figure over its label, on a tint: the counts at the top of a
/// card. [value] is a word ("Not counted") when there is no number.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, required this.tone});

  final String value;
  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final word = int.tryParse(value) == null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: word ? 18 : 32,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: tone == StatusTone.muted ? AppColors.textPrimary : tone.fg,
              fontFeatures: _tabular,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ------------------------------------------------- aboard against listed
/// Before departure: the door camera's count aboard against the list.
/// More aboard than listed stops Depart until each boarding is listed
/// (with a destination) or given a reason (brief 2.4, 6.1). With no
/// camera reporting there is no count, and the card says so in words:
/// a 0 there would be the invented number the system never shows.
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
    final aboard = c.aboard;
    final pending = c.unlisted.where((u) => u.isPending).toList();
    final (chip, chipTone) = switch (c) {
      _ when c.excess > 0 => ('ACTION NEEDED', StatusTone.danger),
      _ when aboard == null => ('NOT COUNTED', StatusTone.warning),
      _ when c.camera == 'lens_blocked' => ('CAMERA COVERED', StatusTone.warning),
      _ when c.camera != 'live' => ('CAMERA SILENT', StatusTone.warning),
      _ => ('NOTHING TO FIX', StatusTone.success),
    };
    final cameraNote = switch (c.camera) {
      'no_phone' =>
        'No camera phone is with this van, so nothing is counted. '
            'The office sees this trip as not audited.',
      'silent' when aboard == null => 'The camera phone has not reported yet, so nothing is counted.',
      'silent' => 'The camera phone stopped reporting. This is its last count.',
      'lens_blocked' => 'The camera is covered. Clear the lens: the count may be low.',
      _ => null,
    };

    return DashCard(
      title: 'Door camera count',
      alert: c.excess > 0,
      trailing: StatusChip(chip, tone: chipTone),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _Figure(
                value: aboard == null ? 'Not counted' : '$aboard',
                label: 'Aboard (camera)',
                tone: c.excess > 0
                    ? StatusTone.danger
                    : aboard == null
                    ? StatusTone.warning
                    : StatusTone.muted,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _Figure(
                value: '${c.listed + c.explained}',
                label: c.explained > 0 ? 'Listed or explained' : 'Listed',
                tone: StatusTone.muted,
              ),
            ),
          ],
        ),
        if (cameraNote != null) ...[
          const SizedBox(height: AppSpacing.md),
          DashNote(cameraNote, tone: StatusTone.warning, icon: Icons.videocam_off_outlined),
        ],
        if (c.excess > 0) ...[
          const SizedBox(height: AppSpacing.md),
          DashNote(
            '${c.excess} more aboard than listed. Add each person to the list with where they get off, '
            'or give a reason. Depart waits until then.',
            tone: StatusTone.danger,
            icon: Icons.warning_amber_rounded,
          ),
        ] else if (aboard != null && aboard < c.listed) ...[
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Fewer aboard than listed: no-shows. Nothing to do.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13.5),
          ),
        ],
        for (final u in pending) ...[
          const SizedBox(height: AppSpacing.md),
          _UnlistedRow(boarding: u, busy: busy, onList: onList, onExplain: onExplain),
        ],
        for (final u in c.unlisted.where((u) => !u.isPending))
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              '${_time.format(u.at)}: ${u.resolution == 'listed' ? 'added to the list' : 'reason given: "${u.note ?? ''}"'}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ),
        const Divider(height: AppSpacing.xxl),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: c.crewAboard,
          onChanged: busy ? null : onCrew,
          title: const Text('I am riding in the van as crew', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Logged, not counted as a passenger or toward the van\'s seats.'),
        ),
      ],
    );
  }
}

/// A boarding the camera counted that nobody on the list matches, with
/// the two ways to settle it.
class _UnlistedRow extends StatelessWidget {
  const _UnlistedRow({required this.boarding, required this.busy, required this.onList, required this.onExplain});

  final UnlistedBoarding boarding;
  final bool busy;
  final ValueChanged<UnlistedBoarding> onList;
  final ValueChanged<UnlistedBoarding> onExplain;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Boarded ${_time.format(boarding.at)}, not on the list',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : () => onExplain(boarding),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, AppSizing.minTouchTarget)),
                child: const Text('Reason'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : () => onList(boarding),
                style: FilledButton.styleFrom(minimumSize: const Size(0, AppSizing.minTouchTarget)),
                child: const Text('Add to list'),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------ home pickup
/// The trip's home pickups (brief 2.6): activate at the terminal, mark the
/// van at the pin, close boarded or no-show, and look at the landmark
/// photo the relative sent. Only the step that applies now is offered.
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

  /// (pickup, action): activate | arrived | boarded | no_show | photo
  final void Function(HomePickup, String) onAction;

  /// How many pickups wait on the Dispatcher now: the tab's badge.
  static int needingAction(List<HomePickup> pickups, {required bool departed}) => pickups
      .where(
        (p) => (p.status == 'requested' && !departed) || (p.status == 'activated' && departed) || p.status == 'arrived',
      )
      .length;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, p) in pickups.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          DashCard(
            title: p.beneficiaryName,
            trailing: StatusChip(_status(p.status), tone: _tone(p.status)),
            children: [
              Text(p.beneficiaryContact, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text(
                'Pin ${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13, fontFeatures: _tabular),
              ),
              if (p.note != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text('"${p.note}"', style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: AppSpacing.md),
              ..._actions(p),
              if (p.status == 'requested' && !departed)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'Marking both seats Paid activates it too. Not activated by departure, it is a no-show.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  List<Widget> _actions(HomePickup p) {
    Widget filled(String label, String action) =>
        FilledButton(onPressed: busy ? null : () => onAction(p, action), child: Text(label));
    Widget outlined(String label, String action) =>
        OutlinedButton(onPressed: busy ? null : () => onAction(p, action), child: Text(label));
    final steps = <Widget>[
      if (p.status == 'requested' && !departed) filled('Activate', 'activate'),
      if (p.status == 'activated' && departed) filled('Van is at the pin', 'arrived'),
      if (p.status == 'arrived') ...[filled('Boarded', 'boarded'), outlined('No-show', 'no_show')],
      if (p.hasPhoto) outlined('Landmark photo', 'photo'),
    ];
    return [
      for (final (i, w) in steps.indexed) ...[if (i > 0) const SizedBox(height: AppSpacing.sm), w],
    ];
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
    return DashCard(
      title: 'Van rental',
      trailing: StatusChip(paid ? 'FEE PAID' : 'FEE UNPAID', tone: paid ? StatusTone.success : StatusTone.warning),
      children: [
        Text(r.customerName ?? 'The renter', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        if (r.customerContact != null)
          Text(
            r.customerContact!,
            style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary),
          ),
        const SizedBox(height: AppSpacing.sm),
        Text('${r.pickupAddress} → ${r.destinationAddress}', style: const TextStyle(fontSize: 14.5)),
        Text(
          '${r.passengerCount} ${r.passengerCount == 1 ? 'passenger' : 'passengers'}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
        ),
        if (r.fee != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _peso.format(r.fee),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, fontFeatures: _tabular),
          ),
          const Text('Agreed fee', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
        if (!paid && r.fee != null) ...[
          const SizedBox(height: AppSpacing.md),
          const DashNote('Start waits for the fee.', tone: StatusTone.warning, icon: Icons.hourglass_empty),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: busy ? null : onCash,
            icon: const Icon(Icons.payments_outlined),
            label: Text('Collected ${_peso.format(r.fee)} in cash'),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------- terminal fees
/// What the Dispatcher hands over before Start (brief rev 721, 2.1): the
/// terminal fees to the Cashier (A2Z's 15 % of each line below, the DCOTT
/// ticket, the day's parking when unpaid) and the operator's share to the
/// operator. The operator's dispute of a line is recorded here, until the
/// payment.
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
      _ => ('UNPAID', StatusTone.warning),
    };
    final toOperator = s.operatorShareOwed - s.operatorShareHeld;
    return DashCard(
      title: 'Terminal fees',
      trailing: StatusChip(label, tone: tone),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: s.amountDue > 0 ? AppColors.warningContainer : AppColors.successContainer,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: s.amountDue > 0
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hand ${_peso.format(s.amountDue)} to the Cashier',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, fontFeatures: _tabular),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'A2Z\'s 15 % of the fares below, the DCOTT ticket, and the day\'s parking if not yet paid. '
                      'Start waits for it.',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.35),
                    ),
                  ],
                )
              : const Text(
                  'Nothing to hand to the Cashier now.',
                  style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success),
                ),
        ),
        if (toOperator > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Give the operator ${_peso.format(toOperator)}, in front of the Cashier',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, fontFeatures: _tabular),
          ),
        ],
        if (s.operatorShareOver > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          DashNote(
            'The operator holds ${_peso.format(s.operatorShareOver)} more than the share: it goes back to the Cashier.',
            tone: StatusTone.warning,
          ),
        ],
        if (s.disputed > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          DashNote('${_peso.format(s.disputed)} disputed: waits for the Terminal Manager.', tone: StatusTone.warning),
        ],
        if (s.lines.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          const Text(
            'FARES ON THE LIST',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppColors.textMuted),
          ),
          for (final l in s.lines) _line(l),
        ],
      ],
    );
  }

  Widget _line(ShareLine l) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l.count} × ${_peso.format(l.fare)} to ${l.destination}${l.isTopUp ? ' (top-up)' : ''}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFeatures: _tabular),
              ),
              Text(
                'A2Z\'s share ${_peso.format(l.share)}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5, fontFeatures: _tabular),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        disputedLines.contains(l.lineId)
            ? const StatusChip('DISPUTED', tone: StatusTone.warning)
            : TextButton(
                onPressed: busy ? null : () => onDispute(l),
                style: TextButton.styleFrom(minimumSize: const Size(0, AppSizing.minTouchTarget)),
                child: const Text('Dispute'),
              ),
      ],
    ),
  );
}

// --------------------------------------------------------- driving flags
class FlagsPanel extends StatelessWidget {
  const FlagsPanel({super.key, required this.flags, required this.busy, required this.onDispute});
  final List<TripFlag> flags;
  final bool busy;
  final ValueChanged<TripFlag> onDispute;

  @override
  Widget build(BuildContext context) {
    return DashCard(
      title: 'Driving flags',
      trailing: StatusChip('${flags.length} ${flags.length == 1 ? 'FLAG' : 'FLAGS'}', tone: StatusTone.warning),
      children: [
        const Text(
          'For review by the Terminal Manager, not proof of misconduct.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
        for (final f in flags)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${f.kind} at ${_time.format(f.start)}${f.place != null ? ', ${f.place}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (f.disputeStatus == 'open')
                  const StatusChip('DISPUTED', tone: StatusTone.warning)
                else if (f.reviewStatus == 'dismissed')
                  const StatusChip('DISMISSED', tone: StatusTone.success)
                else
                  OutlinedButton(
                    onPressed: busy ? null : () => onDispute(f),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, AppSizing.minTouchTarget)),
                    child: const Text('Dispute'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------ the trip
/// Paid, unpaid, at the terminal and seats left, each on its own tint:
/// the top of the trip screen. Four abreast on a phone; two by two when
/// the text is large or the screen narrow, so no count is squeezed.
class TripCounts extends StatelessWidget {
  const TripCounts({
    super.key,
    required this.paid,
    required this.unpaid,
    required this.atTerminal,
    required this.seatsLeft,
  });

  final int paid;
  final int unpaid;
  final int atTerminal;
  final int seatsLeft;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('Paid', paid, StatusTone.success),
      ('Unpaid', unpaid, StatusTone.warning),
      ('At terminal', atTerminal, StatusTone.info),
      ('Seats left', seatsLeft, StatusTone.muted),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        final perRow = box.maxWidth / scaler.scale(1) >= 300 ? 4 : 2;
        const gap = AppSpacing.sm;
        const inset = AppSpacing.xs;
        final width = (box.maxWidth - gap * (perRow - 1)) / perRow;
        // Every label gets the room the tallest one needs, so the four
        // tiles come out one size: "At terminal" wraps on a narrow phone,
        // and its tile used to stand taller than the rest (20 Nov).
        final labelStyle = DefaultTextStyle.of(context).style.merge(_countLabel);
        var labelHeight = 0.0;
        for (final (label, _, _) in tiles) {
          final painter = TextPainter(
            text: TextSpan(text: label, style: labelStyle),
            textAlign: TextAlign.center,
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout(maxWidth: width - 2 * inset);
          if (painter.height > labelHeight) labelHeight = painter.height;
          painter.dispose();
        }
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final (label, value, tone) in tiles)
              SizedBox(
                width: width,
                child: Semantics(
                  label: '$label: $value',
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2, horizontal: inset),
                    decoration: BoxDecoration(
                      color: tone == StatusTone.muted ? AppColors.surfaceSunken : tone.bg,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$value',
                          style: TextStyle(
                            fontSize: 22,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: tone == StatusTone.muted ? AppColors.textPrimary : tone.fg,
                            fontFeatures: _tabular,
                          ),
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          height: labelHeight,
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: _countLabel.copyWith(
                              color: tone == StatusTone.muted ? AppColors.textMuted : tone.fg,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The words under each count in [TripCounts], which measures them with it.
const _countLabel = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600);

/// One reservation or walk-in before departure, read in the order the
/// Dispatcher checks it at the door: who, the code they show, where they
/// get off and the fare; then the action, on its own line so it never
/// squeezes the name, with the amount on it -- the cash to take is on the
/// button that records it. Someone who pressed "I'm here to pay" is
/// waiting with cash: their card is edged in ochre at 2 px, so it is found
/// first in sunlight.
class SeatCard extends StatelessWidget {
  const SeatCard({
    super.key,
    required this.seat,
    required this.stopName,
    required this.busy,
    required this.onPaid,
    required this.onCancel,
    this.mark,
  });

  final SeatOnList seat;

  /// Where the passenger gets off.
  final String stopName;

  /// A mark made on this phone that has not synced yet.
  final PendingSeatMark? mark;
  final bool busy;
  final VoidCallback onPaid;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final s = seat;
    final paidHere = mark?.isPaid ?? false;
    final paid = s.isPaid || paidHere;
    final hereToPay = !paid && s.status == 'checked_in';
    final (label, tone) = switch (s.status) {
      _ when paidHere => ('PAID · NOT SYNCED', StatusTone.info),
      'boarded' => ('ABOARD', StatusTone.success),
      _ when paid => ('PAID', StatusTone.success),
      'checked_in' => ('HERE TO PAY', StatusTone.warning),
      _ => ('UNPAID', StatusTone.warning),
    };
    final who = s.passengerName ?? (s.isWalkIn ? 'Walk-in passenger' : 'App passenger');
    final canCancel = mark == null && !s.isWalkIn;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: hereToPay ? AppColors.warning : AppColors.edge, width: hereToPay ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(who, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      s.bookingCode,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                flex: 2,
                child: Align(
                  alignment: Alignment.topRight,
                  child: StatusChip(label, tone: tone),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          Text(
            'To $stopName · ₱${s.fare.toStringAsFixed(0)}'
            '${s.isWalkIn ? ' · walk-in' : ''}${s.isHomePickupSeat ? ' · home pickup' : ''}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
          ),
          if (!paid || canCancel) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                if (canCancel)
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed: busy ? null : onCancel,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, AppSizing.minTouchTarget)),
                      child: const Text('Cancel'),
                    ),
                  ),
                if (canCancel && !paid) const SizedBox(width: AppSpacing.sm),
                if (!paid)
                  Expanded(
                    flex: 3,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, AppSizing.minTouchTarget)),
                      onPressed: busy ? null : onPaid,
                      icon: const Icon(Icons.payments_outlined, size: 20),
                      label: Text('Mark ₱${s.fare.toStringAsFixed(0)} paid'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
