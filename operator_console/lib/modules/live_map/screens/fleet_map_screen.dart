import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../core/design/components/components.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/repositories/dispatch_repository.dart';
import '../../../data/repositories/tracking_repository.dart';
import '../../../core/design/tokens.dart';

/// Overview: the cooperative's view of NAHGM -- every van currently
/// reporting, on one map, and a card for whichever one is selected.
///
/// Route legs are drawn straight between terminal nodes rather than
/// snapped to roads. That is not a shortcut -- it is what the system
/// measures. NAHGM matches a van to its nearest node and computes ETAs
/// from node-to-node haversine hops, so a road-following line would draw
/// a path none of those numbers came from.
///
/// Tiles are OpenStreetMap, which needs no API key, darkened on the client
/// by flutter_map's own colour filter when the console is dark -- the
/// same tiles, not a second vendor. Everything that makes this screen
/// useful -- the position, the matched node, the ETAs -- comes from the
/// backend; the tile layer only draws the streets beneath it.
///
/// The van card shows only what the backend reports: plate, route
/// progress by stop, next arrival, speed, passengers aboard, crew. It has
/// no fuel, heading or rating because the system measures none of them.
class FleetMapScreen extends StatefulWidget {
  const FleetMapScreen({super.key});

  @override
  State<FleetMapScreen> createState() => _FleetMapScreenState();
}

enum _Filter { all, live, silent }

class _FleetMapScreenState extends State<FleetMapScreen> {
  late final TrackingRepository _tracking = context.read<TrackingRepository>();
  late final DispatchRepository _dispatch = context.read<DispatchRepository>();

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

  /// Today's trips by id, for the card's crew and passenger figures. A
  /// failed load only hides those tiles; the map does not depend on it.
  Map<String, TripBoardEntry> _trips = const {};
  _Filter _filter = _Filter.all;
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
    try {
      final board = await _dispatch.tripBoard(DateTime.now());
      if (!mounted) return;
      setState(() => _trips = {for (final t in board) t.tripId: t});
    } on ApiException {
      // The card simply leaves out crew and passengers.
    }
  }

  Future<void> _select(FleetVan van) async {
    setState(() {
      _selectedTripId = van.tripId;
      _selectedRoute = const [];
    });
    try {
      final nodes = await _tracking.routeNodes(van.tripId);
      if (!mounted || _selectedTripId != van.tripId) return;
      setState(() => _selectedRoute = nodes);
      // Frame the whole route and the van together -- dispatch wants the
      // stretch still ahead, not a close-up of the bonnet. Padded on the
      // left for the card that floats over the map.
      _map.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([
            for (final n in nodes) LatLng(n.latitude, n.longitude),
            LatLng(van.latitude, van.longitude),
          ]),
          padding: const EdgeInsets.fromLTRB(400, 64, 48, 48),
        ),
      );
    } on ApiException {
      if (!mounted) return;
      setState(() => _selectedRoute = const []);
      _map.move(LatLng(van.latitude, van.longitude), 12);
    }
  }

  void _deselect() => setState(() {
        _selectedTripId = null;
        _selectedRoute = const [];
      });

  @override
  void dispose() {
    _timer?.cancel();
    _map.dispose();
    super.dispose();
  }

  List<FleetVan> get _shown => switch (_filter) {
        _Filter.all => _vans,
        _Filter.live => _vans.where((v) => !v.isStale).toList(),
        _Filter.silent => _vans.where((v) => v.isStale).toList(),
      };

  @override
  Widget build(BuildContext context) {
    final selected = _vans.where((v) => v.tripId == _selectedTripId).firstOrNull;
    final live = _vans.where((v) => !v.isStale).length;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            title: 'Overview',
            description: 'Where every van on a trip is right now. Click a van to see '
                'its trip. Updates every ${_refreshInterval.inSeconds} seconds.',
            actions: [RefreshButton(onPressed: _refresh)],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(_error!, style: TextStyle(color: AppColors.danger)),
            ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: Stack(
                children: [
                  Positioned.fill(child: _mapView()),
                  // Filters, top left over the map (the reference's chips).
                  Positioned(
                    left: AppSpacing.lg,
                    top: AppSpacing.lg,
                    child: _FilterChips(
                      value: _filter,
                      counts: (_vans.length, live, _vans.length - live),
                      onChanged: (f) => setState(() => _filter = f),
                    ),
                  ),
                  Positioned(
                    left: AppSpacing.lg,
                    top: 72,
                    bottom: AppSpacing.lg,
                    width: 360,
                    child: _loading
                        ? const SizedBox.shrink()
                        : selected != null
                            ? _VanCard(
                                van: selected,
                                route: _selectedRoute,
                                trip: _trips[selected.tripId],
                                onClose: _deselect,
                              )
                            : _VanList(vans: _shown, empty: _vans.isEmpty, onSelect: _select),
                  ),
                  if (_loading) const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapView() => FlutterMap(
        mapController: _map,
        options: MapOptions(
          // Davao City, the cooperative's base. The camera moves to a van
          // as soon as one is selected.
          initialCenter: LatLng(7.0731, 125.6128),
          initialZoom: 9,
          backgroundColor: AppColors.surface,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            // OSM's tile policy asks for an identifying agent; a client that
            // sends none can be blocked without warning.
            userAgentPackageName: 'ph.edu.umindanao.sabaygo',
            // flutter_map's own inversion matrix: OSM's tiles, darkened --
            // in the dark palette only.
            tileBuilder: AppColors.isDark ? darkModeTileBuilder : null,
          ),
          PolylineLayer(polylines: _polylines()),
          MarkerLayer(markers: _markers()),
          // ODbL requires crediting the contributors -- a licence
          // condition, not decoration.
          const RichAttributionWidget(
            attributions: [TextSourceAttribution('OpenStreetMap contributors')],
          ),
        ],
      );

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

    for (final van in _shown) {
      final selected = van.tripId == _selectedTripId;
      markers.add(
        Marker(
          point: LatLng(van.latitude, van.longitude),
          width: selected ? 64 : 40,
          height: selected ? 64 : 40,
          child: Tooltip(
            message: van.isStale
                ? '${van.label} · no signal recently'
                : [
                    van.label,
                    if (van.nearestStopName != null) 'near ${van.nearestStopName}',
                  ].join(' · '),
            child: GestureDetector(
              onTap: () => _select(van),
              child: _VanPin(isStale: van.isStale, isSelected: selected),
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
            points: [for (final n in _selectedRoute) LatLng(n.latitude, n.longitude)],
            color: AppColors.highlight,
            strokeWidth: 4,
          ),
      ];
}

// ------------------------------------------------------------- over the map
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.value, required this.counts, required this.onChanged});

  final _Filter value;
  final (int, int, int) counts;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    final (all, live, silent) = counts;
    Widget chip(_Filter f, String label, int n) {
      final on = f == value;
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.xs),
        child: Material(
          color: on ? AppColors.primary : Colors.transparent,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => onChanged(f),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
              child: Text('$label  $n',
                  style: TextStyle(
                      color: on ? AppColors.onFill : AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          chip(_Filter.all, 'All', all),
          chip(_Filter.live, 'Live', live),
          chip(_Filter.silent, 'No signal', silent),
        ],
      ),
    );
  }
}

class _Floating extends StatelessWidget {
  const _Floating({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.divider),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 24)],
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

class _VanList extends StatelessWidget {
  const _VanList({required this.vans, required this.empty, required this.onSelect});

  final List<FleetVan> vans;
  final bool empty;
  final ValueChanged<FleetVan> onSelect;

  @override
  Widget build(BuildContext context) {
    if (empty) {
      return const Align(
        alignment: Alignment.topLeft,
        child: _Floating(
          child: EmptyState(
            icon: Icons.airport_shuttle_outlined,
            title: 'No van is on a trip right now',
            hint: 'A van appears here once its conductor opens boarding or departs, '
                'and its phone sends a location.',
          ),
        ),
      );
    }
    final text = Theme.of(context).textTheme;
    final time = DateFormat('h:mm a');
    return Align(
      alignment: Alignment.topLeft,
      child: _Floating(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          itemCount: vans.length,
          separatorBuilder: (_, _) => const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
          itemBuilder: (_, i) {
            final van = vans[i];
            return InkWell(
              onTap: () => onSelect(van),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                child: Row(
                  children: [
                    _VanIcon(stale: van.isStale),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(van.label, style: text.titleSmall),
                          Text(
                            [
                              if (van.nearestStopName != null) 'Near ${van.nearestStopName}',
                              if (van.speedKph != null) '${van.speedKph!.round()} km/h',
                              if (van.nextEta != null) 'next stop ${time.format(van.nextEta!)}',
                            ].join(' · '),
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (van.isStale)
                      // Dispatch may be about to phone this crew; "no
                      // signal" is the actionable word, not "offline".
                      const StatusBadge('No signal', tone: Tone.warning)
                    else
                      Icon(Icons.chevron_right, color: AppColors.textMuted),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The selected van, laid out like the reference dashboard's vehicle card.
class _VanCard extends StatelessWidget {
  const _VanCard({
    required this.van,
    required this.route,
    required this.trip,
    required this.onClose,
  });

  final FleetVan van;
  final List<RouteNode> route;
  final TripBoardEntry? trip;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = trip;
    final from = route.firstOrNull?.terminalName;
    final to = route.lastOrNull?.terminalName;
    // Progress by stop: the map-matched node's place on the route. NAHGM
    // matches to nodes, so this is the honest resolution -- not metres.
    final at = route.indexWhere((n) => n.terminalName == van.nearestStopName);
    final progress = route.length < 2 || at < 0 ? null : at / (route.length - 1);

    return Align(
      alignment: Alignment.topLeft,
      child: _Floating(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _VanIcon(stale: van.isStale, size: 44),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(van.label,
                                  overflow: TextOverflow.ellipsis, style: text.titleLarge),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            van.isStale
                                ? const StatusBadge('No signal', tone: Tone.warning)
                                : const StatusBadge('Live', tone: Tone.success),
                          ],
                        ),
                        Text(t?.routeName ?? van.tripLabel ?? 'Trip ${van.tripId}',
                            overflow: TextOverflow.ellipsis, style: text.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: onClose,
                    icon: Icon(Icons.close, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              // Route and progress.
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(from != null && to != null ? '$from → $to' : (t?.routeName ?? 'Route'),
                        style: text.titleSmall),
                    const SizedBox(height: AppSpacing.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      child: LinearProgressIndicator(
                        value: progress ?? 0,
                        minHeight: 6,
                        color: AppColors.highlight,
                        backgroundColor: AppColors.divider,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      [
                        if (van.nearestStopName != null) 'Near ${van.nearestStopName}',
                        if (at >= 0 && route.isNotEmpty) 'stop ${at + 1} of ${route.length}',
                      ].join(' · '),
                      style: text.bodySmall,
                    ),
                    if (van.nextEta != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 16, color: AppColors.textMuted),
                          const SizedBox(width: AppSpacing.xs),
                          Text('Next stop at ${DateFormat('h:mm a').format(van.nextEta!)}',
                              style: text.bodyMedium),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(child: _SpeedTile(kph: van.speedKph)),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _AboardTile(
                      aboard: t?.boarded,
                      seats: t?.seatCapacity,
                    ),
                  ),
                ],
              ),
              if (t != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Column(
                    children: [
                      PersonRow(role: 'Driver', name: t.driverName),
                      const SizedBox(height: AppSpacing.sm),
                      PersonRow(role: 'Conductor', name: t.conductorName),
                    ],
                  ),
                ),
              ],
              if (van.isStale) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.warningContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.signal_wifi_off, size: 18, color: AppColors.warning),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'No location received recently. The map shows the last '
                          'known position -- call the crew to check.',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedTile extends StatelessWidget {
  const _SpeedTile({required this.kph});
  final double? kph;

  /// Top of the dial. UV Express runs city streets and the national
  /// highway; nothing the GPS reports should pin it.
  static const _max = 120.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _Tile(
      label: 'Speed',
      child: SizedBox(
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size(110, 96),
              painter: _GaugePainter(value: ((kph ?? 0) / _max).clamp(0, 1)),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(kph == null ? '—' : '${kph!.round()}',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
                  Text('km/h', style: text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboardTile extends StatelessWidget {
  const _AboardTile({required this.aboard, required this.seats});
  final int? aboard;
  final int? seats;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final known = aboard != null && seats != null && seats! > 0;
    return _Tile(
      label: 'Passengers aboard',
      child: SizedBox(
        height: 96,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: known ? aboard! / seats! : 0,
                  strokeWidth: 7,
                  strokeCap: StrokeCap.round,
                  color: AppColors.info,
                  backgroundColor: AppColors.divider,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(known ? '$aboard' : '—',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(known ? 'of $seats seats' : 'no data', style: text.bodySmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.xs),
            child,
          ],
        ),
      );
}

/// A 240° dial: the reference's speedometer, drawn from the reported speed
/// alone. No "too fast" colour band -- the cooperative has set no speed
/// rule, and the console should not imply one.
class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value});
  final double value;

  static const _start = math.pi * 5 / 6; // 150°
  static const _sweep = math.pi * 4 / 3; // 240°

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - 6;
    final rect = Rect.fromCircle(center: Offset(size.width / 2, size.height / 2 + 6), radius: r);
    final track = Paint()
      ..color = AppColors.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false, track);
    if (value > 0) {
      canvas.drawArc(rect, _start, _sweep * value, false, track..color = AppColors.highlight);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value;
}

class _VanIcon extends StatelessWidget {
  const _VanIcon({required this.stale, this.size = 36});
  final bool stale;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: stale ? AppColors.warningContainer : AppColors.successContainer,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Icon(Icons.airport_shuttle,
            size: size * 0.55, color: stale ? AppColors.warning : AppColors.success),
      );
}

// --------------------------------------------------------------- map pins
/// A numbered terminal node on the selected van's route.
class _NodePin extends StatelessWidget {
  const _NodePin({required this.sequence});

  final int sequence;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.surface, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 3)],
        ),
        child: Center(
          child: Text(
            '$sequence',
            style: TextStyle(
                color: AppColors.onFill, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      );
}

/// A van. Selected: the highlight colour with a soft halo, as the
/// reference marks the vehicle in focus.
class _VanPin extends StatelessWidget {
  const _VanPin({required this.isStale, required this.isSelected});

  final bool isStale;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final fill = isSelected
        ? AppColors.highlight
        : isStale
            ? AppColors.warning
            : AppColors.success;
    final pin = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.surface, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 6)],
      ),
      // No rotation: /tracking/fleet carries no heading, and an arrow
      // pointing an arbitrary way would invent a direction of travel.
      child: Icon(Icons.airport_shuttle, color: AppColors.onFill, size: 18),
    );
    if (!isSelected) return Center(child: pin);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.highlight.withValues(alpha: 0.22),
      ),
      child: Center(child: pin),
    );
  }
}
