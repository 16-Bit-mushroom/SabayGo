import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/layout/console_router.dart';
import '../../data/repositories/oversight_repository.dart';
import '../setup/step_frame.dart' show PlateTag;
import '../../viewmodels/auth_provider.dart';

/// Every van boarding or on the road, as its two witnesses see it (10 Nov,
/// beside the Overview map):
///
///   * **the door camera** -- YOLOv8 on the van's phone counts people in
///     and out at the door line. Shown as the count against the van's
///     spaces (14), with the camera's state in words: live, covered,
///     silent since a time, or no phone. Over the spaces, the van is
///     flagged red here and the server has already alerted the Terminal
///     Manager, the Cashier and the Dispatcher (`edge/capacity.py`).
///   * **the GPS** -- live, last seen at a time, or no reading yet, and the
///     trip's driving flags still open for review.
///
/// Nothing is filled in: a van with no phone says "not counted", never 0,
/// and a silent camera shows its last count as last known.
class LiveVansPanel extends StatefulWidget {
  const LiveVansPanel({super.key});

  @override
  State<LiveVansPanel> createState() => _LiveVansPanelState();
}

class _LiveVansPanelState extends State<LiveVansPanel> {
  static const _refreshEvery = Duration(seconds: 15);
  List<VanStatus>? _vans;
  bool _failed = false;
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
    try {
      final all = await context.read<OversightRepository>().vanBoard();
      if (!mounted) return;
      setState(() {
        _failed = false;
        _vans = all.where((v) => v.underWay).toList()
          // Overloaded first, then on the road, then boarding.
          ..sort((a, b) {
            int rank(VanStatus v) => v.overloaded ? 0 : (v.state == 'travelling' ? 1 : 2);
            return rank(a).compareTo(rank(b));
          });
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final vans = _vans;
    final over = vans?.where((v) => v.overloaded).toList() ?? const [];
    final manager = context.read<AuthProvider>().profile?.role.isManager ?? false;
    final go = context.read<ConsoleLocation>().go;
    return Panel(
      title: 'Live vans',
      icon: Icons.sensors,
      info: 'How many people the camera at each van\'s door counts aboard, and where the van is. '
          'Updates every ${_refreshEvery.inSeconds} seconds.',
      fill: true,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // One scroll: an overload first, then every van under way.
        Expanded(
          child: vans == null
              ? (_failed
                  ? Center(child: Text('The vans did not load. They come back on the next refresh.',
                      textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: AppColors.textMuted)))
                  : const Center(child: CircularProgressIndicator()))
              : vans.isEmpty
                  ? const EmptyState(
                      icon: Icons.airport_shuttle_outlined,
                      title: 'No van is boarding or on the road',
                      hint: 'A van shows here from boarding until it arrives, with its door count and GPS.')
                  : ListView(padding: const EdgeInsets.only(bottom: AppSpacing.lg), children: [
                      for (final v in over) ...[
                        _Overload(van: v, manager: manager, onAudit: () => go('/reviews/boarding-audit')),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      for (final (i, v) in vans.indexed) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.sm),
                        _VanCard(
                          van: v,
                          onOpen: () => go('/trips/van-status-board'),
                          onFlags: () => go('/reviews/driving-flags'),
                        ),
                      ],
                    ]),
        ),
      ]),
    );
  }
}

/// A van over its spaces: said in red, with what the server already did.
class _Overload extends StatelessWidget {
  const _Overload({required this.van, required this.manager, required this.onAudit});
  final VanStatus van;
  final bool manager;
  final VoidCallback onAudit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final v = van;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.dangerContainer,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.danger),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${v.plateNumber} is over its ${v.seatCapacity} seats',
                  style: text.titleSmall?.copyWith(color: AppColors.danger)),
              Text('The camera counts ${v.aboard} aboard, ${v.aboard! - v.seatCapacity} too many. '
                  'The Terminal Manager, the Cashier and the Dispatcher were alerted.',
                  style: text.bodySmall?.copyWith(color: AppColors.textPrimary)),
              if (manager)
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.danger, padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                  onPressed: onAudit,
                  child: const Text('Open Boarding Audit'),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _VanCard extends StatelessWidget {
  const _VanCard({required this.van, required this.onOpen, required this.onFlags});
  final VanStatus van;
  final VoidCallback onOpen;
  final VoidCallback onFlags;

  static final _time = DateFormat.jm();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final v = van;
    final onRoad = v.state == 'travelling';
    final (camWords, camTone, counted) = switch (v.camera) {
      'live' => ('Camera live', AppColors.primary, true),
      'lens_blocked' => ('Camera covered: the count is paused', AppColors.warning, true),
      'silent' => (
          v.cameraSeenAt == null ? 'Camera silent: no report yet' : 'Camera silent since ${_time.format(v.cameraSeenAt!)}',
          AppColors.warning,
          v.aboard != null
        ),
      _ => ('No phone in the van: not counted', AppColors.textMuted, false),
    };
    final (gpsWords, gpsTone) = v.positionAt == null
        ? ('No GPS reading yet', AppColors.textMuted)
        : v.positionStale == true
            ? ('GPS last seen ${_time.format(v.positionAt!)}${v.nearestStopName != null ? ' near ${v.nearestStopName}' : ''}',
                AppColors.warning)
            : ('GPS live${v.nearestStopName != null ? ', near ${v.nearestStopName}' : ''}', AppColors.primary);
    final aboard = v.aboard;
    final over = v.overloaded;
    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: over ? AppColors.danger : AppColors.divider, width: over ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PlateTag(v.plateNumber),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(v.routeName ?? '', overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
          StatusBadge(onRoad ? 'On the road' : 'Boarding', tone: onRoad ? Tone.success : Tone.info),
        ]),
        const SizedBox(height: AppSpacing.sm),
        // The door count against the spaces, or why there is none.
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (counted && aboard != null) ...[
            Text('$aboard',
                style: TextStyle(
                    fontFamily: 'PlusJakartaSans', fontSize: 26, fontWeight: FontWeight.w700, height: 1.1,
                    color: over ? AppColors.danger : AppColors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 3),
              child: Text('of ${v.seatCapacity} aboard${v.camera == 'silent' ? ' (last count)' : ''}',
                  style: text.bodySmall),
            ),
          ] else
            Text('Not counted', style: text.titleSmall?.copyWith(color: AppColors.textMuted)),
        ]),
        if (counted && aboard != null) ...[
          const SizedBox(height: AppSpacing.xs + 2),
          _Load(aboard: aboard, capacity: v.seatCapacity),
        ],
        const SizedBox(height: AppSpacing.sm),
        _Line(Icons.videocam_outlined, camWords, camTone),
        _Line(Icons.gps_fixed, gpsWords, gpsTone),
        if ((v.openFlags ?? 0) > 0)
          InkWell(
            onTap: onFlags,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: _Line(Icons.flag_outlined,
                '${v.openFlags} driving flag${v.openFlags == 1 ? '' : 's'} to review', AppColors.warning, link: true),
          ),
      ]),
    );
    return ClickableCard(
      onTap: onOpen,
      label: '${v.plateNumber}, ${onRoad ? 'on the road' : 'boarding'}. '
          '${counted && aboard != null ? '$aboard of ${v.seatCapacity} aboard. ' : 'Not counted. '}'
          '$camWords. $gpsWords. Opens Van Status Board.',
      child: card,
    );
  }
}

/// The load bar: green up to the spaces, red over them.
class _Load extends StatelessWidget {
  const _Load({required this.aboard, required this.capacity});
  final int aboard;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    final over = aboard > capacity;
    final f = capacity == 0 ? 0.0 : (aboard / capacity).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: SizedBox(
        height: 6,
        child: Stack(children: [
          const Positioned.fill(child: ColoredBox(color: AppColors.primaryContainer)),
          FractionallySizedBox(
            widthFactor: f,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: over ? AppColors.danger : null,
                gradient: over
                    ? null
                    : const LinearGradient(colors: [AppColors.progressStart, AppColors.progressEnd]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.words, this.tone, {this.link = false});
  final IconData icon;
  final String words;
  final Color tone;
  final bool link;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: AppSpacing.xs + 2),
          Expanded(
            child: Text(words,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tone == AppColors.textMuted ? AppColors.textMuted : AppColors.textPrimary,
                    fontWeight: tone == AppColors.textMuted ? FontWeight.w400 : FontWeight.w500,
                    decoration: link ? TextDecoration.underline : null)),
          ),
        ]),
      );
}
