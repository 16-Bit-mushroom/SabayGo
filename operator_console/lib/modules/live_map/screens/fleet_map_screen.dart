import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/repositories/tracking_repository.dart';

/// The cooperative's view of NAHGM: every van currently reporting, on one
/// map, with the route of whichever one is selected.
///
/// Route legs are drawn straight between terminal nodes rather than
/// snapped to roads. That is not a shortcut -- it is what the system
/// measures. NAHGM matches a van to its nearest node and computes ETAs
/// from node-to-node haversine hops, so a road-following line would draw
/// a path none of those numbers came from.
///
/// Tiles are OpenStreetMap, which needs no API key: everything that makes
/// this screen useful -- the position, the matched node, the ETAs -- comes
/// from the backend, and the tile layer only draws the streets beneath it.
class FleetMapScreen extends StatefulWidget {
  const FleetMapScreen({super.key});

  @override
  State<FleetMapScreen> createState() => _FleetMapScreenState();
}

class _FleetMapScreenState extends State<FleetMapScreen> {
  late final TrackingRepository _tracking = context.read<TrackingRepository>();

  /// Dispatch watches this screen for minutes at a time, so it refreshes
  /// on its own. Fifteen seconds is slower than the handset map: an office
  /// is deciding whether to hold a departure, not whether to leave the
  /// house now.
  static const _refreshInterval = Duration(seconds: 15);

  final MapController _map = MapController();
  Timer? _timer;

  bool _loading = true;
  String? _error;

  List<FleetVan> _vans = const [];
  String? _selectedTripId;
  List<RouteNode> _selectedRoute = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(_refreshInterval, (_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final vans = await _tracking.activeFleet();
      if (!mounted) return;
      setState(() {
        _vans = vans;
        _error = null;
        // A van that finished its trip stops being reported; the selection
        // has to let go with it or the map keeps drawing a route nobody is
        // on.
        if (_selectedTripId != null &&
            !vans.any((v) => v.tripId == _selectedTripId)) {
          _selectedTripId = null;
          _selectedRoute = const [];
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(FleetVan van) async {
    setState(() => _selectedTripId = van.tripId);
    try {
      final nodes = await _tracking.routeNodes(van.tripId);
      if (!mounted) return;
      setState(() => _selectedRoute = nodes);
      // Frame the whole route and the van together -- dispatch wants the
      // stretch still ahead, not a close-up of the bonnet.
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([
            for (final n in nodes) LatLng(n.latitude, n.longitude),
            LatLng(van.latitude, van.longitude),
          ]),
          padding: const EdgeInsets.all(48),
        ),
      );
    } on ApiException {
      if (!mounted) return;
      setState(() => _selectedRoute = const []);
      _map.move(LatLng(van.latitude, van.longitude), 12);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Live Fleet',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Text(
                '${_vans.length} reporting · refreshes every '
                '${_refreshInterval.inSeconds}s',
                style: const TextStyle(color: Colors.black54),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                SizedBox(width: 320, child: _vanList()),
                const SizedBox(width: 16),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FlutterMap(
                      mapController: _map,
                      options: const MapOptions(
                        // Davao City, the cooperative's base. The camera
                        // moves to a van as soon as one is selected.
                        initialCenter: LatLng(7.0731, 125.6128),
                        initialZoom: 9,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          // OSM's tile policy asks for an identifying agent;
                          // a client that sends none can be blocked without
                          // warning.
                          userAgentPackageName: 'ph.edu.umindanao.sabaygo',
                        ),
                        PolylineLayer(polylines: _polylines()),
                        MarkerLayer(markers: _markers()),
                        // ODbL requires crediting the contributors -- a
                        // licence condition, not decoration.
                        const RichAttributionWidget(
                          attributions: [
                            TextSourceAttribution('OpenStreetMap contributors'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _vanList() {
    if (_vans.isEmpty) {
      return const _Notice(
        icon: Icons.directions_car_outlined,
        title: 'No van is reporting',
        detail: 'Vans appear here once a boarding or departed trip sends a '
            'position.',
      );
    }
    final time = DateFormat('h:mm a');
    return Card(
      child: ListView.separated(
        itemCount: _vans.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final van = _vans[i];
          final selected = van.tripId == _selectedTripId;
          return ListTile(
            selected: selected,
            leading: Icon(
              Icons.local_shipping,
              color: van.isStale ? Colors.orange.shade700 : Colors.green.shade700,
            ),
            title: Text(van.label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              [
                if (van.nearestStopName != null) 'near ${van.nearestStopName}',
                if (van.speedKph != null) '${van.speedKph!.round()} km/h',
                if (van.nextEta != null) 'next ${time.format(van.nextEta!)}',
              ].join(' · '),
            ),
            trailing: van.isStale
                ? Tooltip(
                    // Dispatch may be about to phone this crew; "silent"
                    // is the actionable word, not "offline".
                    message: 'No recent position report',
                    child: Chip(
                      label: const Text('SILENT'),
                      backgroundColor: Colors.orange.shade50,
                      labelStyle: TextStyle(
                          fontSize: 11, color: Colors.orange.shade900),
                    ),
                  )
                : null,
            onTap: () => _select(van),
          );
        },
      ),
    );
  }

  List<Marker> _markers() {
    final markers = <Marker>[
      for (final node in _selectedRoute)
        Marker(
          point: LatLng(node.latitude, node.longitude),
          width: 28,
          height: 28,
          child: Tooltip(
            message: 'Stop ${node.stopSequence} · ${node.terminalName}',
            child: _NodePin(sequence: node.stopSequence),
          ),
        ),
    ];

    for (final van in _vans) {
      markers.add(
        Marker(
          point: LatLng(van.latitude, van.longitude),
          width: 38,
          height: 38,
          child: Tooltip(
            message: van.isStale
                ? '${van.label} · no recent position report'
                : [
                    van.label,
                    if (van.nearestStopName != null)
                      'near ${van.nearestStopName}',
                  ].join(' · '),
            child: GestureDetector(
              onTap: () => _select(van),
              child: _VanPin(
                isStale: van.isStale,
                isSelected: van.tripId == _selectedTripId,
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  List<Polyline> _polylines() => [
        if (_selectedRoute.length >= 2)
          Polyline(
            points: [
              for (final n in _selectedRoute) LatLng(n.latitude, n.longitude),
            ],
            color: const Color(0xFF2D2059),
            strokeWidth: 4,
          ),
      ];
}

/// A numbered terminal node on the selected van's route.
class _NodePin extends StatelessWidget {
  const _NodePin({required this.sequence});

  final int sequence;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF2D2059),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
        ),
        child: Center(
          child: Text(
            '$sequence',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      );
}

class _VanPin extends StatelessWidget {
  const _VanPin({required this.isStale, required this.isSelected});

  final bool isStale;
  final bool isSelected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: isStale
              ? Colors.orange.shade700
              : isSelected
                  ? const Color(0xFF88C0D0)
                  : Colors.green.shade700,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5)],
        ),
        // No rotation: /tracking/fleet carries no heading, and an arrow
        // pointing an arbitrary way would invent a direction of travel.
        child: const Icon(Icons.local_shipping, color: Colors.white, size: 18),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.title, required this.detail});

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
              Icon(icon, size: 44, color: Colors.black38),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      );
}
