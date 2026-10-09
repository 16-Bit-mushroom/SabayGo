import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/audit_repository.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/sos_repository.dart';
import '../../data/repositories/tracking_repository.dart';
import '../design/components/status_badge.dart';
import '../design/tokens.dart';

/// Where a chip in the strip leads. The shell maps each to its screen, so
/// this widget knows nothing about module positions -- the same contract
/// as the notification bell.
enum TodayTarget { fleet, trips, checks, emergencies }

/// The top bar's "today at a glance": vans reporting, trips, camera checks
/// waiting for review, open emergencies. Each chip opens the screen that
/// explains it.
///
/// Every figure comes from an endpoint a screen already reads; nothing is
/// computed here that a screen would not show. A figure that fails to load
/// shows a dash, never a zero -- a zero would say "no emergencies" when
/// the truth is "could not ask".
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
  int? _checks;
  int? _emergencies;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_refreshEvery, (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final tracking = context.read<TrackingRepository>();
    final dispatch = context.read<DispatchRepository>();
    final audits = context.read<AuditRepository>();
    final sos = context.read<SosRepository>();

    // Independently: one endpoint down blanks one chip, not the strip.
    Future<T?> attempt<T>(Future<T> f) => f.then<T?>((v) => v).catchError((_) => null);
    final results = await Future.wait([
      attempt(tracking.activeFleet()),
      attempt(dispatch.tripBoard(DateTime.now())),
      attempt(audits.pending()),
      attempt(sos.list(status: 'open')),
    ]);
    if (!mounted) return;
    setState(() {
      _vans = results[0] as List<FleetVan>?;
      _trips = results[1] as List<TripBoardEntry>?;
      _checks = (results[2] as List?)?.length;
      _emergencies = (results[3] as List?)?.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vans = _vans;
    final silent = vans?.where((v) => v.isStale).length ?? 0;
    final trips = _trips;
    final underWay =
        trips?.where((t) => t.status == 'boarding' || t.status == 'departed').length ?? 0;
    final checks = _checks;
    final sos = _emergencies;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Chip(
            icon: Icons.airport_shuttle_outlined,
            label: 'Vans on the road',
            value: vans == null ? '—' : '${vans.length}',
            note: silent > 0 ? '$silent no signal' : null,
            tone: silent > 0 ? Tone.warning : Tone.success,
            onTap: () => widget.onOpen(TodayTarget.fleet),
          ),
          _Chip(
            icon: Icons.departure_board_outlined,
            label: 'Trips today',
            value: trips == null ? '—' : '${trips.length}',
            note: underWay > 0 ? '$underWay under way' : null,
            tone: Tone.info,
            onTap: () => widget.onOpen(TodayTarget.trips),
          ),
          _Chip(
            icon: Icons.fact_check_outlined,
            label: 'Checks to review',
            value: checks == null ? '—' : '$checks',
            tone: (checks ?? 0) > 0 ? Tone.warning : Tone.neutral,
            onTap: () => widget.onOpen(TodayTarget.checks),
          ),
          _Chip(
            icon: Icons.emergency_outlined,
            label: 'Open emergencies',
            value: sos == null ? '—' : '$sos',
            tone: (sos ?? 0) > 0 ? Tone.danger : Tone.neutral,
            onTap: () => widget.onOpen(TodayTarget.emergencies),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    required this.value,
    required this.tone,
    required this.onTap,
    this.note,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? note;
  final Tone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (fg, _) = StatusBadge.colours(tone);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Material(
        color: AppColors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
          side: const BorderSide(color: AppColors.divider),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: AppColors.textMuted),
                const SizedBox(width: AppSpacing.sm),
                Text(label,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(width: AppSpacing.sm),
                Text(value,
                    style: TextStyle(color: fg == AppColors.textMuted ? AppColors.textPrimary : fg,
                        fontSize: 14, fontWeight: FontWeight.w800)),
                if (note != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(note!, style: TextStyle(color: fg, fontSize: 12)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
