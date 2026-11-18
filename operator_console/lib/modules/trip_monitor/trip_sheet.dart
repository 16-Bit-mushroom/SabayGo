import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/fleet_repository.dart';
import '../../data/repositories/money_repository.dart';
import 'trip_actions.dart';

/// The day's trips as a sheet (11 Nov, the owner's reference layout): one
/// row a trip with two-line cells -- time over route, van over operator,
/// Dispatcher over the phone out with the van, listed over the camera's
/// count -- figures that fill themselves (ƒx), the status as a pill and
/// the row's one next step. Filter chips narrow it by state; a click on a
/// row opens the trip's detail from the right.
///
/// Everything shown is what the server holds: the camera count only when a
/// phone counted it, the fees from the van's statement, the next step only
/// when the signed-in role may take it (the office cannot mark a trip
/// arrived: the Dispatcher does).
class TripSheet extends StatefulWidget {
  const TripSheet({
    super.key,
    required this.trips,
    required this.statements,
    required this.roster,
    required this.isManager,
    required this.isCashier,
    required this.onOpen,
    required this.onChanged,
  });

  final List<TripBoardEntry> trips;

  /// The day's van statements: fares and fees per trip; null until loaded.
  final List<Statement>? statements;
  final (List<Van>, List<StaffMember>)? roster;
  final bool isManager;
  final bool isCashier;
  final void Function(TripBoardEntry trip, TripMoney? money) onOpen;
  final VoidCallback onChanged;

  @override
  State<TripSheet> createState() => _TripSheetState();
}

/// The filter chips over the sheet.
enum _Show { all, noVan, boarding, onTheRoad, arrived }

extension on _Show {
  String get label => switch (this) {
        _Show.all => 'All',
        _Show.noVan => 'No van yet',
        _Show.boarding => 'Boarding',
        _Show.onTheRoad => 'On the road',
        _Show.arrived => 'Arrived',
      };

  bool keeps(TripBoardEntry t) => switch (this) {
        _Show.all => true,
        _Show.noVan => t.status == 'scheduled' && !t.isAssigned,
        _Show.boarding => t.status == 'boarding',
        _Show.onTheRoad => t.status == 'departed',
        _Show.arrived => t.status == 'completed',
      };
}

// Column widths; the next-step column takes the rest.
/// The sheet's column widths (12 Nov UI run). Wide on a desktop. On a
/// laptop the fares column goes -- they are in the trip's detail and in
/// Money -- and the rest narrow, so the Next step column, the row's
/// action, stays on screen instead of past the right edge. Narrower than
/// that, the laptop set scrolls sideways under a visible scrollbar.
class _Cols {
  const _Cols({
    required this.time,
    required this.van,
    required this.disp,
    required this.list,
    required this.fares,
    required this.fees,
    required this.status,
  });
  final double time, van, disp, list, fares, fees, status;

  bool get showFares => fares > 0;

  /// Row padding, the gap before Status, and room for the next step.
  double get least => time + van + disp + list + fares + fees + status + 56 + 200;

  static const wide = _Cols(time: 244, van: 208, disp: 212, list: 176, fares: 124, fees: 136, status: 156);
  static const laptop = _Cols(time: 200, van: 172, disp: 176, list: 156, fares: 0, fees: 120, status: 132);

  static _Cols of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ColsScope>()?.cols ?? wide;
}

class _ColsScope extends InheritedWidget {
  const _ColsScope({required this.cols, required super.child});
  final _Cols cols;

  @override
  bool updateShouldNotify(_ColsScope old) => old.cols != cols;
}

class _TripSheetState extends State<TripSheet> {
  final _sideways = ScrollController();

  @override
  void dispose() {
    _sideways.dispose();
    super.dispose();
  }

  String _query = '';
  _Show _show = _Show.all;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final money = _Money(widget.trips, widget.statements);
    final q = _query.trim().toLowerCase();
    final rows = widget.trips
        .where(_show.keeps)
        .where((t) => q.isEmpty ||
            [
              t.plateNumber ?? '',
              t.operatorName ?? '',
              t.dispatcherName ?? '',
              t.routeName,
              DateFormat.jm().format(t.departureDatetime),
            ].join(' ').toLowerCase().contains(q))
        .toList();

    final table = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _HeadRow(),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Text(
              q.isNotEmpty
                  ? 'No trip matches "$_query".'
                  : _show == _Show.all
                      ? 'No trips on this day.'
                      : 'No trip is "${_show.label.toLowerCase()}" now.',
              style: text.bodyMedium?.copyWith(color: AppColors.textMuted)),
        ),
      for (final t in rows)
        _TripRow(
          trip: t,
          money: money.of(t),
          roster: widget.roster,
          isManager: widget.isManager,
          isCashier: widget.isCashier,
          onOpen: () => widget.onOpen(t, money.of(t)),
          onChanged: widget.onChanged,
        ),
      if (rows.isNotEmpty) _TotalRow(trips: rows, money: money),
    ]);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                Text('Trip sheet', style: text.titleMedium),
                Text('${widget.trips.length} trip${widget.trips.length == 1 ? '' : 's'}', style: text.bodySmall),
                const SizedBox(width: AppSpacing.sm),
                for (final s in _Show.values)
                  ChoiceChip(
                    label: Text(s.label),
                    selected: _show == s,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _show = s),
                  ),
              ]),
              SizedBox(
                width: 300,
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Search plate, operator, Dispatcher…',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(builder: (context, c) {
          if (c.maxWidth >= _Cols.wide.least) return _ColsScope(cols: _Cols.wide, child: table);
          if (c.maxWidth >= _Cols.laptop.least) return _ColsScope(cols: _Cols.laptop, child: table);
          return Scrollbar(
            controller: _sideways,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _sideways,
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: _Cols.laptop.least, child: _ColsScope(cols: _Cols.laptop, child: table)),
            ),
          );
        }),
      ]),
    );
  }
}

/// A trip's money, from its van's statement: its fares, A2Z's 15 % of its
/// lines, its DCOTT ticket and the day's parking on the van's first trip.
class TripMoney {
  const TripMoney({
    required this.fares,
    required this.share,
    required this.dcott,
    required this.parking,
    required this.vanBalance,
  });
  final double fares;
  final double share;
  final double dcott;
  final double parking;

  /// The van's undisputed balance for the day: what Record payment asks
  /// for. It differs from [fees] when part of them was recorded earlier --
  /// the parking paid while the van had no trip (18 Nov) -- or another
  /// trip of the van's is unpaid too.
  final double vanBalance;
  double get fees => share + dcott + parking;
  double get operatorShare => fares - fees > 0 ? fares - fees : 0;
}

/// The same rules the server charges by; the Record payment dialog shows
/// the server's own amount due.
class _Money {
  _Money(List<TripBoardEntry> trips, List<Statement>? statements) : loaded = statements != null {
    for (final s in statements ?? const <Statement>[]) {
      _byVan[s.vanId] = s;
      for (final l in s.lines) {
        _fares[l.tripId] = (_fares[l.tripId] ?? 0) + l.gross;
        _share[l.tripId] = (_share[l.tripId] ?? 0) + l.share;
      }
    }
    for (final t in trips) {
      if (t.vanId == null || t.status == 'cancelled') continue;
      final first = _first[t.vanId!];
      if (first == null || t.departureDatetime.isBefore(first.departureDatetime)) _first[t.vanId!] = t;
    }
  }

  final bool loaded;
  final Map<String, Statement> _byVan = {};
  final Map<String, double> _fares = {};
  final Map<String, double> _share = {};
  final Map<String, TripBoardEntry> _first = {};

  double? fares(TripBoardEntry t) => loaded ? (_fares[t.tripId] ?? 0) : null;

  /// Null when the statements did not load, or the trip has no van yet.
  TripMoney? of(TripBoardEntry t) {
    if (!loaded || t.status == 'cancelled') return null;
    final s = t.vanId == null ? null : _byVan[t.vanId];
    if (s == null) return null;
    return TripMoney(
      fares: _fares[t.tripId] ?? 0,
      share: _share[t.tripId] ?? 0,
      dcott: s.dcottTicketFee,
      parking: _first[t.vanId]?.tripId == t.tripId ? s.parkingFee : 0,
      vanBalance: s.amountDue,
    );
  }
}

/// A trip's money from the day's statements, for the trip's detail.
TripMoney? tripMoneyFor(TripBoardEntry trip, List<TripBoardEntry> all, List<Statement>? statements) =>
    _Money(all, statements).of(trip);

const _figures = [FontFeature.tabularFigures()];

TextStyle? _headStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .bodySmall
    ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: 0.6, fontSize: 11.5);

class _HeadRow extends StatelessWidget {
  const _HeadRow();

  @override
  Widget build(BuildContext context) {
    final s = _headStyle(context);
    final cols = _Cols.of(context);
    Widget head(String label, double w, {bool auto = false, bool end = false}) => SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Row(mainAxisAlignment: end ? MainAxisAlignment.end : MainAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: s),
              if (auto) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Fills itself',
                  child: Text('ƒx', style: s?.copyWith(color: AppColors.primary, fontStyle: FontStyle.italic)),
                ),
              ],
            ]),
          ),
        );
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider), bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(children: [
        head('Time & route', cols.time),
        head('Van & operator', cols.van),
        head('Dispatcher & phone', cols.disp),
        head('Listed vs aboard', cols.list, auto: true),
        if (cols.showFares) head('Fares (B+W)', cols.fares, auto: true, end: true),
        head('Terminal fees', cols.fees, auto: true, end: true),
        const SizedBox(width: AppSpacing.lg),
        head('Status', cols.status),
        Expanded(child: Text('NEXT STEP', style: s, textAlign: TextAlign.right)),
      ]),
    );
  }
}

/// A trip's state in the office's words, and its tone: the sheet's status
/// column and the detail's header say the same thing.
(String, Tone) tripStatusWords(TripBoardEntry t) {
  if (t.status == 'cancelled') return ('Cancelled', Tone.danger);
  if (t.paymentStatus == 'left_unpaid') return ('Left unpaid', Tone.danger);
  return switch (t.status) {
    'scheduled' when !t.isAssigned => ('No van yet', Tone.warning),
    'scheduled' when t.paymentStatus == 'unpaid' => ('Fees unpaid', Tone.warning),
    'scheduled' => ('Ready to start', Tone.success),
    'boarding' => ('Boarding', Tone.success),
    'departed' => ('On the road', Tone.success),
    'completed' => ('Arrived', Tone.neutral),
    _ => (t.status, Tone.neutral),
  };
}

/// The status as the reference draws it: on the road is the one solid
/// pill (the vans that matter right now), the rest are tints.
class TripStatusPill extends StatelessWidget {
  const TripStatusPill(this.trip, {super.key});
  final TripBoardEntry trip;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = tripStatusWords(trip);
    final solid = trip.status == 'departed' && trip.paymentStatus != 'left_unpaid';
    final (bg, fg) = solid
        ? (AppColors.primary, AppColors.onFill)
        : switch (tone) {
            Tone.success => (AppColors.successContainer, AppColors.success),
            Tone.warning => (AppColors.warningContainer, AppColors.warning),
            Tone.danger => (AppColors.dangerContainer, AppColors.danger),
            Tone.info => (AppColors.infoContainer, AppColors.info),
            Tone.neutral => (AppColors.surfaceSunken, AppColors.textMuted),
          };
    return Semantics(
      label: 'Status: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.full)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

/// The phone out with the van, as the trip board reports it.
String _phoneLine(TripBoardEntry t) {
  if (t.phoneSilent == null) return 'No phone out';
  if (t.phoneSilent == true) return 'Phone silent';
  return t.phoneBatteryPct == null ? 'Phone reporting' : 'Phone reporting, ${t.phoneBatteryPct} %';
}

/// The row's next step, by state and role. The same rules decide the
/// detail's footer button.
class TripNextStep extends StatelessWidget {
  const TripNextStep({
    super.key,
    required this.trip,
    required this.isManager,
    required this.isCashier,
    required this.onChanged,
    this.wide = false,
  });

  final TripBoardEntry trip;
  final bool isManager;
  final bool isCashier;
  final VoidCallback onChanged;

  /// In the detail's footer: a full-width button.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final actions = TripActions(t, onChanged);
    final text = Theme.of(context).textTheme;
    final size = wide ? const Size.fromHeight(48) : const Size(0, 38);
    Widget note(String s, {IconData? icon}) => Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (icon != null) ...[Icon(icon, size: 15, color: AppColors.textMuted), const SizedBox(width: 6)],
            Flexible(child: Text(s, style: text.bodySmall, textAlign: TextAlign.right)),
          ],
        );
    Widget filled(String label, IconData icon, Future<void> Function() go) => FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: size, padding: const EdgeInsets.symmetric(horizontal: 16)),
          onPressed: go,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );
    Widget outlined(String label, IconData icon, Future<void> Function() go, {Color? colour}) => OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              minimumSize: size,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              foregroundColor: colour,
              side: colour == null ? null : BorderSide(color: colour)),
          onPressed: go,
          icon: Icon(icon, size: 18),
          label: Text(label),
        );

    if (t.status == 'cancelled') return note('Voided');
    if (t.paymentStatus == 'left_unpaid') {
      return isCashier
          ? outlined('Record payment', Icons.payments_outlined, () => actions.recordPayment(context))
          : note('Balance on Money');
    }
    switch (t.status) {
      case 'scheduled':
        if (!t.isAssigned) return note('Pick a van and a Dispatcher');
        if (t.paymentStatus == 'unpaid') {
          if (isCashier) return filled('Record payment', Icons.payments_outlined, () => actions.recordPayment(context));
          if (isManager) {
            return Tooltip(
              message: 'Start waits for the terminal fees. Lift the block with a written reason, or wait '
                  'for the Cashier to record the payment.',
              child: outlined('Start blocked (unpaid)', Icons.lock_outline, () => actions.liftBlock(context),
                  colour: AppColors.danger),
            );
          }
          return note('Waiting for the Cashier');
        }
        if (DateTime.now().isBefore(t.startOpensAt)) {
          return note('Start opens at ${DateFormat.jm().format(t.startOpensAt)}', icon: Icons.schedule);
        }
        return filled('Start trip', Icons.play_arrow, () => actions.start(context));
      case 'boarding':
        return filled('Depart', Icons.logout, () => actions.depart(context));
      case 'departed':
        return note('The Dispatcher marks arrival', icon: Icons.near_me_outlined);
      case 'completed':
        return note('Completed', icon: Icons.check);
    }
    return const SizedBox.shrink();
  }
}

class _TripRow extends StatefulWidget {
  const _TripRow({
    required this.trip,
    required this.money,
    required this.roster,
    required this.isManager,
    required this.isCashier,
    required this.onOpen,
    required this.onChanged,
  });

  final TripBoardEntry trip;
  final TripMoney? money;
  final (List<Van>, List<StaffMember>)? roster;
  final bool isManager;
  final bool isCashier;
  final VoidCallback onOpen;
  final VoidCallback onChanged;

  @override
  State<_TripRow> createState() => _TripRowState();
}

class _TripRowState extends State<_TripRow> {
  bool _hover = false;

  TripBoardEntry get t => widget.trip;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cols = _Cols.of(context);
    final actions = TripActions(t, widget.onChanged);
    final editable = t.status == 'scheduled';
    final vans = widget.roster?.$1 ?? const <Van>[];
    final crew = widget.roster?.$2 ?? const <StaffMember>[];
    final m = widget.money;
    final paid = t.paymentStatus == 'paid' || (t.status != 'scheduled' && t.paymentStatus != 'left_unpaid');
    final small = text.bodySmall?.copyWith(fontSize: 12);
    final full = t.seatCapacity == 0 ? 0.0 : (t.booked / t.seatCapacity).clamp(0.0, 1.0);

    Widget two(Widget top, String? under, {TextStyle? underStyle, bool end = false}) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            top,
            if (under != null) ...[
              const SizedBox(height: 6),
              Text(under, style: underStyle ?? small, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ],
        );

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: Material(
        color: AppColors.surfaceRaised,
        child: InkWell(
          onTap: widget.onOpen,
          // The same hover as every record row: the see-through wash
          // (theme) and the emerald bar sliding in at the left edge.
          child: AnimatedContainer(
            duration: AppDuration.quick,
            height: 88,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.surfaceSunken))),
            foregroundDecoration: BoxDecoration(
                border: Border(left: _hover ? const BorderSide(color: AppColors.accent, width: 3) : BorderSide.none)),
            child: Row(children: [
              SizedBox(
                width: cols.time,
                child: two(
                  Text(DateFormat.jm().format(t.departureDatetime),
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: _figures)),
                  t.tripLabel == null ? t.routeName : '${t.routeName}, ${t.tripLabel}',
                ),
              ),
              SizedBox(
                width: cols.van,
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xl),
                  child: two(
                    editable
                        ? _PickCell(
                            value: t.vanId,
                            hint: 'Pick a van',
                            items: [
                              for (final v in vans) (v.vanId, v.plateNumber, v.operatorName),
                              if (t.vanId != null && !vans.any((v) => v.vanId == t.vanId))
                                (t.vanId!, t.plateNumber ?? 'Van', t.operatorName),
                            ],
                            onPick: (id) => actions.assign(context, vanId: id),
                          )
                        : _Fixed(t.plateNumber ?? '—'),
                    t.operatorName == null ? null : 'Op: ${t.operatorName}',
                  ),
                ),
              ),
              SizedBox(
                width: cols.disp,
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xl),
                  child: two(
                    editable
                        ? _PickCell(
                            value: t.dispatcherId,
                            hint: 'Pick a Dispatcher',
                            items: [
                              for (final d in crew) (d.userId, d.fullName, null),
                              if (t.dispatcherId != null && !crew.any((d) => d.userId == t.dispatcherId))
                                (t.dispatcherId!, t.dispatcherName ?? 'Dispatcher', null),
                            ],
                            onPick: (id) => actions.assign(context, dispatcherId: id),
                          )
                        : _Fixed(t.dispatcherName ?? '—'),
                    t.isAssigned ? _phoneLine(t) : null,
                    underStyle: small?.copyWith(color: t.phoneSilent == true ? AppColors.danger : null),
                  ),
                ),
              ),
              SizedBox(
                width: cols.list,
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.lg),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Row(children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(text: '${t.booked}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        TextSpan(text: ' of ${t.seatCapacity}', style: TextStyle(color: AppColors.textMuted)),
                      ]), style: text.bodyMedium?.copyWith(fontFeatures: _figures)),
                      const Spacer(),
                      Tooltip(
                        message: t.doorAboard == null
                            ? 'No door camera count for this trip'
                            : 'Counted by the door camera (YOLOv8)',
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(t.doorAboard == null ? Icons.videocam_off_outlined : Icons.videocam_outlined,
                              size: 14, color: t.doorAboard == null ? AppColors.textMuted : AppColors.primary),
                          const SizedBox(width: 3),
                          Text(t.doorAboard == null ? 'No count' : 'Aboard: ${t.doorAboard}',
                              style: small?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: t.doorAboard == null ? AppColors.textMuted : AppColors.primary)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      child: LinearProgressIndicator(
                        value: full,
                        minHeight: 5,
                        backgroundColor: AppColors.primaryContainer,
                        color: AppColors.primary,
                        semanticsLabel: 'Seats listed',
                        semanticsValue: '${t.booked} of ${t.seatCapacity}',
                      ),
                    ),
                  ]),
                ),
              ),
              if (cols.showFares) SizedBox(
                width: cols.fares,
                child: Text(m == null || m.fares == 0 ? '—' : peso.format(m.fares),
                    textAlign: TextAlign.right,
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: _figures)),
              ),
              SizedBox(
                width: cols.fees,
                child: m == null
                    ? Text('—', textAlign: TextAlign.right, style: text.bodyMedium)
                    : two(
                        Text(peso.format(m.fees),
                            style: text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: paid ? AppColors.primary : AppColors.warning,
                                fontFeatures: _figures)),
                        paid ? '✓ Recorded' : 'Unpaid',
                        underStyle: small?.copyWith(color: paid ? AppColors.primary : AppColors.warning),
                        end: true,
                      ),
              ),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(width: cols.status, child: Align(alignment: Alignment.centerLeft, child: TripStatusPill(t))),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TripNextStep(
                      trip: t, isManager: widget.isManager, isCashier: widget.isCashier, onChanged: widget.onChanged),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.trips, required this.money});
  final List<TripBoardEntry> trips;
  final _Money money;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, fontFeatures: _figures);
    final live = trips.where((t) => t.status != 'cancelled').toList();
    final pax = live.fold<int>(0, (n, t) => n + t.booked);
    final cap = live.fold<int>(0, (n, t) => n + t.seatCapacity);
    double sum(double? Function(TripBoardEntry) f) => live.fold<double>(0, (n, t) => n + (f(t) ?? 0));
    final fares = sum(money.fares);
    final fees = sum((t) => money.of(t)?.fees);
    final cols = _Cols.of(context);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider, width: 2)),
      ),
      child: Row(children: [
        SizedBox(
          width: cols.time + cols.van + cols.disp,
          child: Text.rich(TextSpan(children: [
            TextSpan(text: 'Daily sheet totals', style: s),
            TextSpan(
                text: '  ${live.length} trip${live.length == 1 ? '' : 's'}, 15 % + ₱75 DCOTT + ₱50 parking',
                style: text.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ])),
        ),
        SizedBox(width: cols.list, child: Text('$pax of $cap seats', style: s)),
        if (cols.showFares)
          SizedBox(width: cols.fares, child: Text(money.loaded ? peso.format(fares) : '—', style: s, textAlign: TextAlign.right)),
        SizedBox(
            width: cols.fees,
            child: Text(money.loaded ? peso.format(fees) : '—',
                style: s?.copyWith(color: AppColors.primary), textAlign: TextAlign.right)),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Text('Click a row for its detail', style: text.bodySmall, textAlign: TextAlign.right),
        ),
      ]),
    );
  }
}

/// A value that can no longer change in the sheet (the trip has started).
class _Fixed extends StatelessWidget {
  const _Fixed(this.value);
  final String value;

  @override
  Widget build(BuildContext context) => Text(value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700));
}

/// A dropdown cell as the reference draws it: a bordered box, amber while
/// empty ("Pick a van"), saved the moment a choice is made.
class _PickCell extends StatefulWidget {
  const _PickCell({required this.value, required this.hint, required this.items, required this.onPick});
  final String? value;
  final String hint;

  /// (id, label, note under the label in the menu).
  final List<(String, String, String?)> items;
  final Future<bool> Function(String id) onPick;

  @override
  State<_PickCell> createState() => _PickCellState();
}

class _PickCellState extends State<_PickCell> {
  bool _busy = false;
  bool _hover = false;

  /// The same box as every input (FieldBox): [AppSizing.field] high, the
  /// small radius, the secondary-hover edge and the wash under the pointer.
  /// Empty, it keeps the ochre that says "pick one".
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final empty = widget.value == null;
    final box = AnimatedContainer(
      duration: AppDuration.quick,
      height: AppSizing.field,
      padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
            color: _hover ? AppColors.primaryLight : (empty ? const Color(0xFFE0B252) : AppColors.border)),
        color: empty ? AppColors.warningContainer : AppColors.surfaceRaised,
      ),
      foregroundDecoration: BoxDecoration(
        color: _hover ? AppColors.hoverWash : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: _busy
          ? const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
          : DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: widget.items.any((i) => i.$1 == widget.value) ? widget.value : null,
                isExpanded: true,
                iconSize: 20,
                icon: Icon(Icons.expand_more, color: empty ? AppColors.warning : AppColors.textMuted),
                hint: Text(widget.hint,
                    style: text.bodyMedium?.copyWith(color: AppColors.warning, fontWeight: FontWeight.w700)),
                selectedItemBuilder: (_) => [
                  for (final (_, label, _) in widget.items)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                ],
                items: [
                  for (final (id, label, note) in widget.items)
                    DropdownMenuItem(
                      value: id,
                      child: note == null
                          ? Text(label)
                          : Row(children: [
                              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                              const SizedBox(width: AppSpacing.sm),
                              Flexible(child: Text(note, style: text.bodySmall, overflow: TextOverflow.ellipsis)),
                            ]),
                    ),
                ],
                onChanged: (id) async {
                  if (id == null || id == widget.value) return;
                  setState(() => _busy = true);
                  await widget.onPick(id);
                  if (mounted) setState(() => _busy = false);
                },
              ),
            ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: box,
    );
  }
}

/// What passengers can book right now, as the passenger app lists them:
/// the trips still waiting to start, the soonest first. Shown in the post
/// box's split view, by choice.
class OpenForBooking extends StatelessWidget {
  const OpenForBooking({super.key, required this.trips});
  final List<TripBoardEntry> trips;

  static List<TripBoardEntry> openOf(List<TripBoardEntry> trips) {
    final now = DateTime.now();
    return trips.where((t) => t.status == 'scheduled' && t.departureDatetime.isAfter(now)).toList()
      ..sort((a, b) => a.departureDatetime.compareTo(b.departureDatetime));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final open = openOf(trips);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Passengers can book now', style: text.titleMedium),
          const SizedBox(width: AppSpacing.xs),
          const InfoTip('As the passenger app lists them, soonest first. Unpaid reservations are released '
              'before departure.'),
        ]),
        const SizedBox(height: AppSpacing.md),
        if (open.isEmpty)
          Text('No trip is open for booking. Post one, or post 7 days of trips from the schedules.', style: text.bodyMedium)
        else
          for (final t in open.take(5))
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
              child: Row(children: [
                Text(DateFormat.jm().format(t.departureDatetime),
                    style: text.titleSmall?.copyWith(fontFeatures: _figures)),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text(t.routeName, style: text.bodySmall, overflow: TextOverflow.ellipsis)),
                Text('${t.seatCapacity - t.booked} seats open',
                    style: text.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ]),
            ),
        if (open.length > 5) Text('and ${open.length - 5} more', style: text.bodySmall),
      ]),
    );
  }
}
