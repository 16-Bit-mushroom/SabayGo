import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/oversight_repository.dart';
import '../../data/repositories/sos_repository.dart';
import '../../data/repositories/tracking_repository.dart';
import '../design/components/actions.dart';
import '../design/components/focus_ring.dart';
import '../design/components/live_dot.dart';
import '../design/components/status_badge.dart';
import '../design/tokens.dart';
import '../../viewmodels/auth_provider.dart';

/// Where a chip in the strip leads. The shell maps each to its screen, so
/// this widget knows nothing about module positions -- the same contract
/// as the notification bell.
enum TodayTarget { fleet, trips, review, emergencies }

/// The top bar's four live pills (11 Nov, the owner's reference layout):
/// vans on the road (and how many have no signal), trips today (and how
/// many are under way), what waits on this person -- boardings not on a
/// list for the Terminal Manager (Boarding Audit), vans owing terminal fees
/// for the Cashier (Van Status Board) -- and open emergencies. Each opens
/// the page that explains it.
///
/// Every figure comes from an endpoint a page already reads. A figure that
/// fails to load shows a dash, never a zero: a zero would say "no
/// emergencies" when the truth is "could not ask".
class TodayStrip extends StatefulWidget {
  const TodayStrip({super.key, required this.onOpen});

  final ValueChanged<TodayTarget> onOpen;

  @override
  State<TodayStrip> createState() => _TodayStripState();
}

class _TodayStripState extends State<TodayStrip> {
  static const _refreshEvery = Duration(seconds: 30);

  List<FleetVan>? _vans;
  List<TripBoardEntry>? _trips;
  int? _review;
  bool _manager = false;
  int? _emergencies;
  Timer? _timer;

  /// When the figures last arrived, and whether a load is under way: the
  /// strip says how fresh it is, so a figure is never trusted blind.
  DateTime? _loadedAt;
  bool _loading = false;
  bool _failed = false;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refreshEvery, (_) => _load());
    consoleChanged.addListener(_load);
    // Moves "updated 10 s ago" along between loads.
    _clock = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock?.cancel();
    consoleChanged.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final tracking = context.read<TrackingRepository>();
    final dispatch = context.read<DispatchRepository>();
    final oversight = context.read<OversightRepository>();
    final manager = context.read<AuthProvider>().profile?.role.isManager ?? false;
    final sos = context.read<SosRepository>();

    // Independently: one endpoint down blanks one chip, not the strip.
    Future<T?> attempt<T>(Future<T> f) => f.then<T?>((v) => v).catchError((_) => null);
    final results = await Future.wait([
      attempt(tracking.activeFleet()),
      attempt(dispatch.tripBoard(DateTime.now())),
      manager
          ? attempt(oversight.boardingAudit(DateFormat('yyyy-MM-dd').format(DateTime.now())).then((trips) => trips
              .fold<int>(0, (n, t) => n + t.unlisted.where((u) => u.resolution == 'pending').length)))
          : attempt(oversight.vanBoard().then((vans) => vans.where((v) => v.owes > 0).length)),
      attempt(sos.list(status: 'open')),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = results.every((r) => r == null);
      if (!_failed) _loadedAt = DateTime.now();
      _vans = results[0] as List<FleetVan>?;
      _trips = results[1] as List<TripBoardEntry>?;
      _review = results[2] as int?;
      _manager = manager;
      _emergencies = (results[3] as List?)?.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vans = _vans;
    final silent = vans?.where((v) => v.isStale).length ?? 0;
    final trips = _trips;
    final underWay = trips?.where((t) => t.status == 'boarding' || t.status == 'departed').length ?? 0;
    final review = _review;
    final sos = _emergencies;
    // Narrow, the pills keep their figures and give their words to a
    // tooltip, so the last one (open emergencies) never scrolls away.
    return LayoutBuilder(builder: (context, c) {
      final compact = c.maxWidth < 760;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _Chip(
            icon: Icons.airport_shuttle_outlined,
            label: 'Vans on the road',
            compact: compact,
            live: (vans?.length ?? 0) > silent,
            value: vans == null ? '—' : '${vans.length}',
            note: silent > 0 ? '$silent no signal' : null,
            tone: silent > 0 ? Tone.warning : Tone.success,
            onTap: () => widget.onOpen(TodayTarget.fleet),
          ),
          _Chip(
            icon: Icons.departure_board_outlined,
            label: 'Trips today',
            compact: compact,
            value: trips == null ? '—' : '${trips.length}',
            note: underWay > 0 ? '$underWay under way' : null,
            tone: Tone.neutral,
            onTap: () => widget.onOpen(TodayTarget.trips),
          ),
          _Chip(
            icon: _manager ? Icons.how_to_reg_outlined : Icons.money_off,
            label: _manager ? 'Boardings to review' : 'Vans with a balance',
            compact: compact,
            value: review == null ? '—' : '$review',
            tone: (review ?? 0) > 0 ? Tone.warning : Tone.neutral,
            onTap: () => widget.onOpen(TodayTarget.review),
          ),
          _Chip(
            icon: Icons.emergency_outlined,
            label: 'Open emergencies',
            compact: compact,
            value: sos == null ? '—' : '$sos',
            tone: sos == null ? Tone.warning : (sos > 0 ? Tone.danger : Tone.neutral),
            onTap: () => widget.onOpen(TodayTarget.emergencies),
          ),
          _Freshness(loadedAt: _loadedAt, loading: _loading, failed: _failed, compact: compact, onTap: _load),
        ]),
      );
    });
  }
}

class _Chip extends StatefulWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    required this.onTap,
    required this.compact,
    this.note,
    this.live = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Tone tone;
  final VoidCallback onTap;
  final bool compact;

  /// A short second figure beside the value ("2 under way").
  final String? note;

  /// A breathing dot instead of the icon: something is moving right now.
  final bool live;

  @override
  State<_Chip> createState() => _ChipState();
}

/// Under the pointer a pill rises 1 px on the soft lift, takes the
/// secondary-hover edge and the wash, and its icon turns green: it opens
/// the page behind the figure.
class _ChipState extends State<_Chip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final (fg, bg) = StatusBadge.colours(w.tone);
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final said = '${w.label}: ${w.value}${w.note == null ? '' : ', ${w.note}'}';
    // A figure that needs someone (a boarding to review, an emergency)
    // keeps its status tint at rest, see-through, so it is seen before
    // it is read.
    final alarmed = w.tone == Tone.warning || w.tone == Tone.danger;
    final chip = Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: AnimatedContainer(
        duration: still ? Duration.zero : AppDuration.quick,
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(0, _hover && !still ? -1 : 0, 0),
        decoration: BoxDecoration(
          color: alarmed ? bg.withValues(alpha: 0.7) : AppColors.surfaceRaised.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: _hover ? AppColors.primaryLight : (alarmed ? fg.withValues(alpha: 0.35) : AppColors.divider)),
          boxShadow: _hover ? AppShadow.lift : AppShadow.none,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: FocusRing(
            radius: AppRadius.full,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: w.onTap,
              onHover: (h) => setState(() => _hover = h),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    w.live
                        ? const LiveDot()
                        : Icon(w.icon, size: 16, color: _hover ? AppColors.primary : AppColors.textMuted),
                    const SizedBox(width: AppSpacing.sm),
                    if (!w.compact) ...[
                      Text(w.label,
                          style: TextStyle(color: _hover ? AppColors.textPrimary : AppColors.textMuted, fontSize: 13)),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Text(w.value,
                        style: TextStyle(
                            color: fg == AppColors.textMuted ? AppColors.textPrimary : fg,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                    if (w.note != null && !w.compact) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Text(w.note!, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: said,
      excludeSemantics: true,
      onTap: w.onTap,
      child: w.compact ? Tooltip(message: said, excludeFromSemantics: true, child: chip) : chip,
    );
  }
}

/// How fresh the strip is: "Live · 10 s ago" with a breathing dot, a
/// spinner while it reloads, "Not updating" in red when nothing answered
/// (the figures beside it are then old, and say so). A click reloads now.
class _Freshness extends StatelessWidget {
  const _Freshness({
    required this.loadedAt,
    required this.loading,
    required this.failed,
    required this.compact,
    required this.onTap,
  });

  final DateTime? loadedAt;
  final bool loading;
  final bool failed;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final at = loadedAt;
    final secs = at == null ? null : DateTime.now().difference(at).inSeconds;
    final ago = secs == null
        ? 'loading'
        : secs < 5
            ? 'just now'
            : secs < 60
                ? '${(secs ~/ 5) * 5} s ago'
                : '${secs ~/ 60} min ago';
    final words = failed ? 'Not updating' : 'Live · $ago';
    final colour = failed ? AppColors.danger : AppColors.textMuted;
    return Tooltip(
      message: failed
          ? 'The server did not answer. The figures are from ${at == null ? 'nowhere yet' : DateFormat.jms().format(at)}. Click to try again.'
          : 'Refreshes every 30 seconds${at == null ? '' : '; last at ${DateFormat.jms().format(at)}'}. Click to refresh now.',
      child: Semantics(
        button: true,
        label: words,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (loading)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              else if (failed)
                const Icon(Icons.cloud_off_outlined, size: 16, color: AppColors.danger)
              else
                const LiveDot(),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(words, style: TextStyle(color: colour, fontSize: 12, fontWeight: failed ? FontWeight.w700 : FontWeight.w500)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
