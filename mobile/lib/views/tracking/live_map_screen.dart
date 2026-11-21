import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/journey_strip.dart';
import '../../core/design/components/status_chip.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_client.dart';
import '../../data/repositories/tracking_repository.dart';
import '../../data/repositories/trip_repository.dart';
import '../../viewmodels/live_map_viewmodel.dart';
import '../safety/sos_button.dart';

/// NAHGM's passenger-facing half: the route drawn as its nodes, and the
/// van's last matched position on it.
///
/// The legs are drawn straight between terminals rather than snapped to
/// roads, because that is what the system actually models — NAHGM measures
/// haversine distance node to node and its ETAs come from those same hops.
/// A road-snapped line would show the passenger a path the ETA was not
/// computed along.
class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({
    super.key,
    required this.tripId,
    required this.title,
    this.boardingStop,
    this.alightingStop,
  });

  final String tripId;
  final String title;
  final int? boardingStop;
  final int? alightingStop;

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  late final LiveMapViewModel _vm;
  final MapController _map = MapController();

  /// Set once the route has been framed, so a later rebuild does not yank
  /// the camera back while the passenger is panning around.
  bool _framed = false;

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiClient>();
    _vm = LiveMapViewModel(
      tripRepository: TripRepository(api),
      trackingRepository: TrackingRepository(api),
      tripId: widget.tripId,
      boardingStop: widget.boardingStop,
      alightingStop: widget.alightingStop,
    )..addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(_frameRouteOnce);
  }

  /// Frame every node and the van, so nothing starts off-screen. Done once:
  /// re-fitting on each poll would fight a passenger who is panning around.
  void _frameRouteOnce() {
    if (_framed || _vm.stops.isEmpty) return;
    _framed = true;
    _map.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints([
          for (final s in _vm.stops) LatLng(s.latitude, s.longitude),
          if (_vm.position != null)
            LatLng(_vm.position!.latitude, _vm.position!.longitude),
        ]),
        padding: const EdgeInsets.all(48),
      ),
    );
  }

  void _centreOnVan() {
    final pos = _vm.position;
    if (pos == null) return;
    _map.move(LatLng(pos.latitude, pos.longitude), 13);
  }

  @override
  void dispose() {
    _vm.removeListener(_onChanged);
    _vm.dispose();
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plate = _vm.position?.plateNumber;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (plate != null)
              Text('Van $plate',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
          ],
        ),
        // The passenger's own SOS lives here rather than on the ticket:
        // this is the screen someone has open while they are in the van.
        actions: [SosButton(tripId: widget.tripId)],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_vm.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_vm.error != null) {
      return _Message(
        icon: Icons.signal_wifi_off,
        title: 'Map unavailable',
        detail: _vm.error!,
      );
    }
    if (_vm.stops.isEmpty) {
      return const _Message(
        icon: Icons.route_outlined,
        title: 'No route to show',
        detail: 'This trip has no stops recorded.',
      );
    }

    return Column(
      children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter:
                  LatLng(_vm.stops.first.latitude, _vm.stops.first.longitude),
              initialZoom: 9,
              onMapReady: _frameRouteOnce,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                // OSM's tile policy asks for an identifying agent. An app
                // that does not send one can be blocked without warning.
                userAgentPackageName: 'ph.edu.umindanao.sabaygo',
              ),
              PolylineLayer(polylines: _polylines()),
              MarkerLayer(markers: _markers()),
              // Attribution is a licence condition of the tiles, not
              // decoration -- ODbL requires crediting the contributors.
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
            // Centre and Refresh as map buttons at the top right (20 Nov
            // redesign), where map controls are looked for.
            Positioned(
              top: AppSpacing.md,
              right: AppSpacing.md,
              child: Column(children: [
                if (_vm.position != null) ...[
                  _MapButton(icon: Icons.my_location, tooltip: 'Centre on the van', onPressed: _centreOnVan),
                  const SizedBox(height: AppSpacing.sm),
                ],
                _MapButton(icon: Icons.refresh, tooltip: 'Refresh', onPressed: _vm.refresh),
              ]),
            ),
          ]),
        ),
        _StatusPanel(vm: _vm),
      ],
    );
  }

  /// Route nodes plus the van. flutter_map markers are ordinary widgets, so
  /// the stop number is drawn into the pin itself -- a route is an ordered
  /// sequence, and the same terminal sits at a different number on every
  /// route that passes it.
  List<Marker> _markers() {
    final markers = <Marker>[
      for (final stop in _vm.stops)
        Marker(
          point: LatLng(stop.latitude, stop.longitude),
          width: 28,
          height: 28,
          // The journey strip's own marks (mobile/DESIGN.md): a hollow
          // pin-red ring where the passenger boards, a filled pin-red square
          // where they get off, and plain numbered stops between. Pin red,
          // not danger: getting off at your stop is not an alarm.
          child: _NodePin(
            sequence: stop.stopSequence,
            end: stop.stopSequence == widget.boardingStop
                ? _End.boarding
                : stop.stopSequence == widget.alightingStop
                    ? _End.alighting
                    : null,
          ),
        ),
    ];

    final pos = _vm.position;
    if (pos != null) {
      markers.add(
        Marker(
          point: LatLng(pos.latitude, pos.longitude),
          width: 38,
          height: 38,
          child: _VanPin(
            headingDeg: pos.headingDeg,
            // A stale fix is recoloured as well as captioned below: the
            // marker is no longer where the van is, and that has to be
            // readable at a glance.
            isStale: pos.isStale,
          ),
        ),
      );
    }
    return markers;
  }

  List<Polyline> _polylines() => [
        Polyline(
          points: [for (final s in _vm.stops) LatLng(s.latitude, s.longitude)],
          color: AppColors.primary.withValues(alpha: 0.45),
          strokeWidth: 4,
        ),
        if (_vm.trail.length >= 2)
          Polyline(
            points: [for (final p in _vm.trail) LatLng(p.latitude, p.longitude)],
            color: AppColors.success,
            strokeWidth: 5,
          ),
      ];
}

enum _End { boarding, alighting }

/// A numbered terminal node, shaped like the journey strip's marks when it
/// is the passenger's own stop.
class _NodePin extends StatelessWidget {
  const _NodePin({required this.sequence, this.end});

  final int sequence;
  final _End? end;

  @override
  Widget build(BuildContext context) {
    final (fill, edge, ink, square) = switch (end) {
      _End.boarding => (AppColors.surfaceRaised, AppColors.brand, AppColors.brand, false),
      _End.alighting => (AppColors.brand, AppColors.surfaceRaised, AppColors.onFill, true),
      null => (AppColors.surfaceRaised, AppColors.textPrimary, AppColors.textPrimary, false),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(5) : null,
        border: Border.all(color: edge, width: end == _End.boarding ? 3 : 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
      ),
      child: Center(
        child: Text(
          '$sequence',
          style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// A white, edged map button: a 48 dp target over busy tiles.
class _MapButton extends StatelessWidget {
  const _MapButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.surfaceRaised,
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.edge),
          minimumSize: const Size(AppSizing.minTouchTarget, AppSizing.minTouchTarget),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      );
}

/// The van, pointed the way it was last heading.
class _VanPin extends StatelessWidget {
  const _VanPin({required this.headingDeg, required this.isStale});

  final double? headingDeg;
  final bool isStale;

  @override
  Widget build(BuildContext context) {
    final colour = isStale ? AppColors.warning : AppColors.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colour,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5)],
      ),
      child: Transform.rotate(
        // Heading is degrees clockwise from north; the icon points north at
        // rest. Without a heading the arrow would lie, so a plain dot marker
        // is shown instead.
        angle: (headingDeg ?? 0) * math.pi / 180,
        child: Icon(
          headingDeg == null ? Icons.circle : Icons.navigation,
          color: Colors.white,
          size: headingDeg == null ? 12 : 20,
        ),
      ),
    );
  }
}

String _age(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

/// Everything the map itself cannot say: how old the fix is, which node
/// the van was matched to, and when it reaches the stops ahead. A sheet with
/// rounded top corners and a green edge, not a shadow (20 Nov redesign).
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.vm});

  final LiveMapViewModel vm;

  @override
  Widget build(BuildContext context) {
    final pos = vm.position;
    final time = DateFormat('h:mm a');
    final text = Theme.of(context).textTheme;
    // "Arriving soon": the van's nearest stop is the passenger's own. A
    // fact about where the van was matched, never an estimated time; it
    // stands in for the ETA the server drops once that stop is nearest
    // (docs/KNOWN_ISSUES.md, NAHGM).
    final arriving = pos != null &&
        !pos.isStale &&
        vm.alightingStop != null &&
        pos.nearestStopSequence == vm.alightingStop;
    final mineListed = pos?.etas.any((e) => e.stopSequence == vm.alightingStop) ?? false;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: const BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border(top: BorderSide(color: AppColors.edge, width: 2)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pos == null)
              _Banner(
                tone: StatusTone.info,
                icon: Icons.schedule,
                text: vm.isAwaitingFirstReport
                    ? 'The van has not started reporting yet. The route is '
                        'shown above; tracking begins when it leaves the terminal.'
                    : 'No position available right now.',
              )
            else ...[
              if (pos.isStale)
                _Banner(
                  tone: StatusTone.warning,
                  icon: Icons.warning_amber_rounded,
                  // Named as a last-known position, never dressed up as
                  // current: a passenger acts on this by walking to a
                  // terminal.
                  text: 'Last reported ${_age(pos.secondsSinceReport)} ago. '
                      'This is where the van was, not where it is now.',
                )
              else if (vm.hasPassedBoardingStop)
                const _Banner(
                  tone: StatusTone.danger,
                  icon: Icons.info_outline,
                  text: 'The van has already passed your boarding stop. Message the Dispatcher if you need help.',
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        [
                          pos.nearestStopName == null ? (pos.plateNumber ?? 'Van') : 'Near ${pos.nearestStopName}',
                          if (pos.speedKph != null) '${pos.speedKph!.round()} km/h',
                        ].join(' · '),
                        style: text.bodyLarge!.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (!pos.isStale)
                        Text('Last reported ${_age(pos.secondsSinceReport)} ago', style: text.bodySmall),
                    ]),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: StatusChip(
                      arriving ? 'ARRIVING SOON' : pos.isStale ? 'LAST KNOWN' : 'LIVE',
                      tone: arriving ? StatusTone.success : pos.isStale ? StatusTone.warning : StatusTone.success,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text('REMAINING STOPS',
                  style: text.labelSmall!.copyWith(color: AppColors.textMuted, fontWeight: FontWeight.w800, letterSpacing: 1)),
              const SizedBox(height: AppSpacing.xs),
              if (arriving && !mineListed)
                _StopRow(
                  sequence: vm.alightingStop!,
                  name: vm.alightingNode?.terminalName ?? 'Your stop',
                  detail: 'Arriving soon',
                  mine: true,
                ),
              if (pos.etas.isEmpty && !arriving)
                const Text('No stops remaining on this route.', style: TextStyle(color: AppColors.textMuted))
              else
                for (final eta in pos.etas)
                  _StopRow(
                    sequence: eta.stopSequence,
                    name: eta.terminalName,
                    // Stationary vans get no ETA from the server, so the
                    // distance is shown instead of a fabricated time.
                    detail: eta.eta == null
                        ? '${(eta.distanceM / 1000).toStringAsFixed(1)} km'
                        : '${(eta.distanceM / 1000).toStringAsFixed(1)} km · ${time.format(eta.eta!)} · ${eta.minutesAway} min',
                    mine: eta.stopSequence == vm.alightingStop,
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One stop ahead and when the van reaches it. The passenger's own stop
/// carries the journey strip's red square and is set in green.
class _StopRow extends StatelessWidget {
  const _StopRow({required this.sequence, required this.name, required this.detail, required this.mine});

  final int sequence;
  final String name;
  final String detail;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: mine ? AppColors.surfaceRaised : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: mine ? AppColors.edge : AppColors.divider),
      ),
      child: Row(children: [
        if (mine) ...[
          const JourneyMarker(JourneyEnd.alighting),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(
          child: Text(
            '$sequence · $name${mine ? ' (your stop)' : ''}',
            style: text.bodyMedium!.copyWith(fontWeight: mine ? FontWeight.w700 : FontWeight.w600),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            detail,
            textAlign: TextAlign.end,
            style: text.bodySmall!.copyWith(
              color: mine ? AppColors.primary : AppColors.textMuted,
              fontWeight: mine ? FontWeight.w700 : FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ]),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.tone, required this.icon, required this.text});

  final StatusTone tone;
  final IconData icon;
  final String text;

  /// A tone, not a loose colour: its text and tint were checked together
  /// (the band it replaced set ochre text on a 10 % ochre tint).
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: tone.bg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: tone.fg.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: tone.fg),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(text, style: TextStyle(color: AppColors.textPrimary, fontSize: 13.5, height: 1.35)),
            ),
          ],
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.detail});

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 44, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted)),
            ],
          ),
        ),
      );
}
