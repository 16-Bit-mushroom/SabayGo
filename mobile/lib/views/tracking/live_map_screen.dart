import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        // The passenger's own SOS lives here rather than on the ticket:
        // this is the screen someone has open while they are in the van.
        actions: [SosButton(tripId: widget.tripId)],
      ),
      floatingActionButton: _vm.position == null
          ? null
          : FloatingActionButton(
              onPressed: _centreOnVan,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              tooltip: 'Centre on the van',
              child: const Icon(Icons.my_location),
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
          child: FlutterMap(
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
        ),
        _StatusPanel(vm: _vm, onRefresh: _vm.refresh),
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
          child: _NodePin(
            sequence: stop.stopSequence,
            colour: stop.stopSequence == widget.boardingStop
                ? AppColors.accent
                : stop.stopSequence == widget.alightingStop
                    ? AppColors.danger
                    : AppColors.primary,
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
            color: AppColors.accent,
            strokeWidth: 5,
          ),
      ];
}

/// A numbered terminal node.
class _NodePin extends StatelessWidget {
  const _NodePin({required this.sequence, required this.colour});

  final int sequence;
  final Color colour;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: colour,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
        ),
        child: Center(
          child: Text(
            '$sequence',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
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
/// the van was matched to, and when it reaches the stops ahead.
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.vm, required this.onRefresh});

  final LiveMapViewModel vm;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final pos = vm.position;
    final time = DateFormat('h:mm a');

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pos == null)
              _Banner(
                colour: AppColors.textMuted,
                icon: Icons.schedule,
                text: vm.isAwaitingFirstReport
                    ? 'The van has not started reporting yet. The route is '
                        'shown below; tracking begins when it leaves the terminal.'
                    : 'No position available right now.',
              )
            else ...[
              if (pos.isStale)
                _Banner(
                  colour: AppColors.warning,
                  icon: Icons.warning_amber_rounded,
                  // Named as a last-known position, never dressed up as
                  // current: a passenger acts on this by walking to a
                  // terminal.
                  text: 'Last reported ${_age(pos.secondsSinceReport)} ago. '
                      'This is where the van was, not where it is now.',
                )
              else if (vm.hasPassedBoardingStop)
                _Banner(
                  colour: AppColors.danger,
                  icon: Icons.info_outline,
                  text: 'The van has already passed your boarding stop.',
                ),
              Row(
                children: [
                  const Icon(Icons.local_shipping_outlined,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      pos.nearestStopName == null
                          ? (pos.plateNumber ?? 'Van')
                          : 'Near ${pos.nearestStopName}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  if (pos.speedKph != null)
                    Text('${pos.speedKph!.round()} km/h',
                        style: const TextStyle(color: AppColors.textMuted)),
                ],
              ),
              const SizedBox(height: 10),
              if (pos.etas.isEmpty)
                const Text('No stops remaining on this route.',
                    style: TextStyle(color: AppColors.textMuted))
              else
                for (final eta in pos.etas)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text('${eta.stopSequence}',
                              style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          child: Text(
                            eta.terminalName,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: eta.stopSequence == vm.boardingStop
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        Text(
                          // Stationary vans get no ETA from the server, so
                          // the distance is shown instead of a fabricated
                          // time.
                          eta.eta == null
                              ? '${(eta.distanceM / 1000).toStringAsFixed(1)} km'
                              : '${time.format(eta.eta!)}  ·  ${eta.minutesAway} min',
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.colour, required this.icon, required this.text});

  final Color colour;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colour.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colour),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: colour, fontSize: 12.5, height: 1.3)),
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
