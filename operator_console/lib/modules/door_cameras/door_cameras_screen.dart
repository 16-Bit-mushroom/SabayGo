import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/device_repository.dart';
import '../setup/step_frame.dart' show PlateTag;

/// The in-van phones, for a Terminal Manager who is not an IT person
/// (12 Nov, the owner's decision). Each van carries a phone at the door that
/// counts the passengers getting on and off; this page answers one question
/// per phone -- is it counting, and if not, what do I do? -- in everyday
/// words, first. The figures come after, and the charts only on request.
///
/// Only what the phone reported is shown. A reading it did not send says
/// "not reported", never zero; a phone that stopped sending says since
/// when. No speed is called good or bad: no operating rate is quoted
/// before the in-van benchmark exists (CLAUDE.md). The camera is "Counting"
/// or "Stopped", and how often it looks is said as a plain number.
class DoorCamerasScreen extends StatefulWidget {
  const DoorCamerasScreen({super.key});

  @override
  State<DoorCamerasScreen> createState() => _DoorCamerasScreenState();
}

class _DoorCamerasScreenState extends State<DoorCamerasScreen> {
  late final DeviceRepository _repo = context.read<DeviceRepository>();
  List<DoorCamera>? _cameras;
  String? _error;
  bool _loading = false;
  DateTime? _loadedAt;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (!quiet) _error = null;
    });
    try {
      final cameras = await _repo.live();
      if (!mounted) return;
      setState(() {
        _cameras = cameras;
        _error = null;
        _loadedAt = DateTime.now();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cameras = _cameras;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      children: [
        PageHeader(
          title: 'Door cameras',
          description: 'Each van carries a phone at the door that counts the passengers getting on and off. '
              'Here you can see whether each phone is working, and what to do when it is not. '
              'The page updates by itself every 15 seconds.',
          actions: [
            if (_loadedAt != null)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.md),
                child: Text('Updated ${DateFormat.jms().format(_loadedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            RefreshButton(onPressed: _load, busy: _loading),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: FactLine(
              Icons.sync_problem,
              cameras == null
                  ? 'The phones could not be loaded: $_error'
                  : 'Could not update just now: $_error. What you see is from '
                      '${_loadedAt == null ? 'earlier' : DateFormat.jms().format(_loadedAt!)}.',
              colour: AppColors.warning,
            ),
          ),
        if (cameras == null && _error == null)
          const Padding(padding: EdgeInsets.all(AppSpacing.section), child: Center(child: CircularProgressIndicator()))
        else if (cameras != null && cameras.isEmpty)
          const EmptyState(
            icon: Icons.videocam_off_outlined,
            title: 'No phones added yet',
            hint: 'Add the van\'s phone in Setup › Phones and give it to a van. It shows here once it is on.',
          )
        else if (cameras != null)
          LayoutBuilder(builder: (context, c) {
            // Two to a row when there are two or more; a lone phone takes the
            // full width rather than leaving half the page empty.
            final two = c.maxWidth >= 1100 && cameras.length > 1;
            final w = two ? (c.maxWidth - AppSpacing.lg) / 2 : c.maxWidth;
            return Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.lg,
              children: [for (final cam in cameras) SizedBox(width: w, child: _CameraCard(cam))],
            );
          }),
      ],
    );
  }
}

/// How a phone is doing, in one sentence and what to do about it.
enum _Level { ok, attention, notCounting, notConnected }

class _Verdict {
  const _Verdict(this.level, this.title, [this.todo]);
  final _Level level;
  final String title;
  final String? todo;

  (Color, Color, IconData) get look => switch (level) {
        _Level.ok => (AppColors.success, AppColors.successContainer, Icons.check_circle_outline),
        _Level.attention => (AppColors.warning, AppColors.warningContainer, Icons.warning_amber_rounded),
        _Level.notCounting => (AppColors.danger, AppColors.dangerContainer, Icons.error_outline),
        _Level.notConnected => (AppColors.textMuted, AppColors.surfaceSunken, Icons.power_off_outlined),
      };
}

/// Battery heat in words. 45 °C is where phones commonly start slowing
/// themselves down to cool; 40 °C is the step before it.
const double _warmC = 40, _hotC = 45;

String _heatWord(double c) => c >= _hotC ? 'Too hot' : (c >= _warmC ? 'Warm' : 'Normal');

_Verdict _verdictOf(DoorCamera cam) {
  final p = cam.phone;
  final last = p.lastReportAt;
  if (last == null) {
    return const _Verdict(_Level.notConnected, 'Not connected yet',
        'Open the SabayGo camera app on the phone and sign it in with its code from Setup › Phones.');
  }
  if (p.silent) {
    return _Verdict(_Level.notCounting, 'Not counting: the phone stopped sending at ${DateFormat.jm().format(last)}',
        'Check that the phone is switched on, the SabayGo camera app is open, and it has mobile data or Wi-Fi.');
  }
  if (p.cameraOk == false) {
    return const _Verdict(_Level.notCounting, 'Not counting: the camera is not working',
        'Close and reopen the SabayGo camera app. If it stays off, restart the phone.');
  }
  if (cam.lensBlocked == true) {
    return const _Verdict(_Level.notCounting, 'Not counting: something is covering the camera',
        'Wipe the lens, or move whatever is blocking its view of the door.');
  }
  if (cam.detectionRate == 0) {
    return const _Verdict(_Level.attention, 'The camera has stopped looking at the door',
        'Close and reopen the SabayGo camera app.');
  }
  final temp = p.batteryTempC;
  if (temp != null && temp >= _hotC) {
    return const _Verdict(_Level.attention, 'Needs attention: the phone is too hot',
        'Move it out of direct sun, or nearer the aircon. A very hot phone may slow down or switch itself off.');
  }
  final battery = p.batteryPct;
  if (battery != null && battery <= 20 && cam.charging != true) {
    return const _Verdict(_Level.attention, 'Needs attention: the battery is low', 'Plug the phone into the van\'s charger.');
  }
  if (p.gpsOk == false) {
    return const _Verdict(_Level.attention, 'Counting, but the van\'s location is not coming through',
        'Turn on Location on the phone.');
  }
  return const _Verdict(_Level.ok, 'Working: counting passengers at the door');
}

/// One phone.
class _CameraCard extends StatefulWidget {
  const _CameraCard(this.cam);
  final DoorCamera cam;

  @override
  State<_CameraCard> createState() => _CameraCardState();
}

class _CameraCardState extends State<_CameraCard> {
  bool _history = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cam = widget.cam;
    final p = cam.phone;
    final last = p.lastReportAt;
    final verdict = _verdictOf(cam);
    final (colour, tint, icon) = verdict.look;
    final temp = p.batteryTempC;
    final trip = cam.trip;
    final rate = cam.detectionRate;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: verdict.level == _Level.ok ? AppColors.divider : colour.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Which van, which phone.
        Row(children: [
          if (p.checkout != null) PlateTag(p.checkout!.plateNumber) else const StatusBadge('Not given to a van'),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.model, style: text.titleSmall, overflow: TextOverflow.ellipsis),
              Text(
                p.checkout == null
                    ? 'In the office'
                    : 'With ${p.checkout!.dispatcherName}'
                        '${last == null ? '' : ' · last heard from ${_ago(last)}'}',
                style: text.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpacing.md),
        // The answer first: is it counting, and what to do if not.
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: colour, size: 24),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(verdict.title, style: text.titleSmall?.copyWith(color: colour)),
                if (verdict.todo != null) ...[
                  const SizedBox(height: 2),
                  Text('What to do: ${verdict.todo}', style: text.bodyMedium),
                ],
              ]),
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(spacing: AppSpacing.lg, runSpacing: AppSpacing.xs, children: [
          _Check(Icons.videocam_outlined, 'Camera', p.cameraOk, yes: 'working', no: 'not working'),
          _Check(Icons.location_on_outlined, 'Location', p.gpsOk, yes: 'on', no: 'off'),
          _Check(Icons.visibility_outlined, 'Camera view', cam.lensBlocked == null ? null : !cam.lensBlocked!,
              yes: 'clear', no: 'blocked'),
          _Check(Icons.power_outlined, 'Charger', cam.charging, yes: 'plugged in', no: 'not plugged in', noIsBad: false),
        ]),
        const SizedBox(height: AppSpacing.lg),
        // One height for the four tiles, whatever each holds.
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: _Tile(
              label: 'Battery',
              value: p.batteryPct == null ? '—' : '${p.batteryPct} %',
              note: p.batteryPct == null
                  ? 'not reported'
                  : (cam.charging == true ? 'charging' : (cam.charging == false ? 'not charging' : null)),
              bar: p.batteryPct == null ? null : p.batteryPct! / 100,
              alert: p.batteryPct != null && p.batteryPct! <= 20 && cam.charging != true ? 'Low: plug in the charger' : null,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _Tile(
              label: 'Phone heat',
              value: temp == null ? '—' : _heatWord(temp),
              note: temp == null ? 'not reported' : '${temp.toStringAsFixed(1)} °C',
              alert: temp != null && temp >= _hotC ? 'Move it out of the sun' : null,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _Tile(
              label: 'Camera',
              value: rate == null ? '—' : (rate > 0 ? 'Counting' : 'Stopped'),
              note: rate == null
                  ? 'not reported'
                  : (rate > 0 ? 'looks at the door ${rate.toStringAsFixed(0)} times a second' : 'not looking at the door'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: _Tile(
              label: 'Passengers inside now',
              value: trip == null ? '—' : '${trip.aboard}',
              note: trip == null ? 'no trip today' : '${trip.listed} on the passenger list',
              alert: trip != null && trip.aboard > trip.listed ? 'More inside than on the list' : null,
            ),
          ),
        ])),
        const SizedBox(height: AppSpacing.md),
        // The charts are for a closer look, opened on request.
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _history = !_history),
            icon: Icon(_history ? Icons.expand_less : Icons.expand_more, size: 20),
            label: Text(_history ? 'Hide the last 2 hours' : 'Show the last 2 hours'),
          ),
        ),
        if (_history) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: _Spark(
                title: 'Phone heat',
                points: [for (final h in cam.history) (h.at, h.tempC)],
                unit: ' °C',
                digits: 1,
                reference: _hotC,
                referenceLabel: 'too hot',
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: _Spark(
                title: 'How often the camera looks at the door (times a second)',
                points: [for (final h in cam.history) (h.at, h.detectionRate)],
                unit: '',
                digits: 1,
              ),
            ),
          ]),
        ],
        const SizedBox(height: AppSpacing.sm),
        const Divider(),
        const SizedBox(height: AppSpacing.md),
        Row(children: [
          const Icon(Icons.directions_bus_outlined, size: 18, color: AppColors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              trip == null
                  ? 'Its van has no trip today.'
                  : 'Trip ${DateFormat.jm().format(trip.departure)}${trip.label == null ? '' : ' · ${trip.label}'}'
                      ' · ${_status(trip.status)} · counted ${trip.boarded} getting on, ${trip.alighted} getting off',
              style: text.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('Today: ${cam.boardedToday} got on · ${cam.alightedToday} got off', style: text.bodySmall),
        ]),
      ]),
    );
  }

  static String _status(String s) => switch (s) {
        'scheduled' => 'not yet started',
        'boarding' => 'boarding',
        'departed' => 'on the road',
        'completed' => 'arrived',
        _ => s,
      };

  static String _ago(DateTime at) {
    final s = DateTime.now().difference(at).inSeconds;
    if (s < 60) return '${s < 0 ? 0 : s} seconds ago';
    if (s < 3600) return '${s ~/ 60} min ago';
    return 'at ${DateFormat.jm().format(at)}';
  }
}

/// One check, in words: "Camera: working". Not reported when the phone
/// never said.
class _Check extends StatelessWidget {
  const _Check(this.icon, this.name, this.value, {required this.yes, required this.no, this.noIsBad = true});
  final IconData icon;
  final String name;
  final bool? value;
  final String yes;
  final String no;
  final bool noIsBad;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final bad = v == false && noIsBad;
    final colour = v == null ? AppColors.textMuted : (v ? AppColors.success : (bad ? AppColors.danger : AppColors.textMuted));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(bad ? Icons.error_outline : icon, size: 16, color: colour),
      const SizedBox(width: 4),
      Text.rich(TextSpan(children: [
        TextSpan(text: '$name: ', style: const TextStyle(color: AppColors.textMuted)),
        TextSpan(
          text: v == null ? 'not reported' : (v ? yes : no),
          style: TextStyle(fontWeight: FontWeight.w600, color: v == null ? AppColors.textMuted : AppColors.textPrimary),
        ),
      ]), style: const TextStyle(fontSize: 13)),
    ]);
  }
}

/// A headline reading: its name, the word or figure, a note under it, and
/// an optional bar (the battery) or alert in words with an icon.
class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, this.note, this.bar, this.alert});
  final String label;
  final String value;
  final String? note;
  final double? bar;
  final String? alert;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: text.bodySmall),
        const SizedBox(height: 2),
        Text(value,
            style: text.headlineSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            overflow: TextOverflow.ellipsis),
        if (bar != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              value: bar!.clamp(0, 1),
              minHeight: 5,
              backgroundColor: AppColors.primaryContainer,
              color: AppColors.primary,
            ),
          ),
        ],
        const SizedBox(height: 4),
        if (alert != null)
          Row(children: [
            const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.warning),
            const SizedBox(width: 4),
            Flexible(
              child: Text(alert!,
                  style: text.bodySmall?.copyWith(color: AppColors.warning, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis),
            ),
          ])
        else if (note != null)
          Text(note!, style: text.bodySmall, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

/// One measure over time: a 2 px line in the primary green, points placed
/// by their time, broken where the phone sent nothing or fell silent, the
/// latest point marked, an optional dashed reference line with its word,
/// and a crosshair with the reading under the pointer. The title names the
/// measure, so there is no legend.
class _Spark extends StatefulWidget {
  const _Spark({
    required this.title,
    required this.points,
    required this.unit,
    this.digits = 0,
    this.reference,
    this.referenceLabel,
  });

  final String title;
  final List<(DateTime, double?)> points;
  final String unit;
  final int digits;
  final double? reference;
  final String? referenceLabel;

  @override
  State<_Spark> createState() => _SparkState();
}

class _SparkState extends State<_Spark> {
  int? _hover;

  static const double _height = 84;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // The chart runs from the first report that carried this reading to the
    // latest, and its axis says so: readings that began three minutes ago
    // are not squeezed into the edge of a two-hour frame.
    final all = widget.points;
    final first = all.indexWhere((p) => p.$2 != null);
    final lastWith = all.lastIndexWhere((p) => p.$2 != null);
    final pts = first < 0 ? all : all.sublist(first, lastWith + 1);
    final values = [for (final p in pts) if (p.$2 != null) p.$2!];
    final has = values.isNotEmpty;
    String fmt(double v) => '${v.toStringAsFixed(widget.digits)}${widget.unit}';
    final hovered = _hover != null && _hover! < pts.length ? pts[_hover!] : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text(widget.title,
                style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
        if (hovered != null)
          Text(
            '${DateFormat.jm().format(hovered.$1)} · ${hovered.$2 == null ? 'not reported' : fmt(hovered.$2!)}',
            style: text.bodySmall?.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          )
        else if (has)
          Text('now ${fmt(values.last)}', style: text.bodySmall),
      ]),
      const SizedBox(height: 6),
      SizedBox(
        height: _height,
        child: !has
            ? Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  all.isEmpty ? 'Nothing heard from the phone in the last 2 hours' : 'This phone does not send this reading',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              )
            : LayoutBuilder(builder: (context, c) {
                return MouseRegion(
                  onHover: (e) {
                    if (pts.length < 2) return setState(() => _hover = 0);
                    final t0 = pts.first.$1.millisecondsSinceEpoch;
                    final span = pts.last.$1.millisecondsSinceEpoch - t0;
                    final at = t0 + (e.localPosition.dx / c.maxWidth).clamp(0.0, 1.0) * span;
                    var best = 0;
                    for (var k = 1; k < pts.length; k++) {
                      if ((pts[k].$1.millisecondsSinceEpoch - at).abs() <
                          (pts[best].$1.millisecondsSinceEpoch - at).abs()) {
                        best = k;
                      }
                    }
                    if (best != _hover) setState(() => _hover = best);
                  },
                  onExit: (_) => setState(() => _hover = null),
                  child: CustomPaint(
                    size: Size(c.maxWidth, _height),
                    painter: _SparkPainter(
                      points: pts,
                      reference: widget.reference,
                      referenceLabel: widget.referenceLabel,
                      hover: _hover,
                    ),
                  ),
                );
              }),
      ),
      if (has)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Text(DateFormat.jm().format(pts.first.$1), style: text.bodySmall),
            const Spacer(),
            Text('lowest ${fmt(values.reduce((a, b) => a < b ? a : b))} · highest ${fmt(values.reduce((a, b) => a > b ? a : b))}',
                style: text.bodySmall),
            const Spacer(),
            Text(DateFormat.jm().format(pts.last.$1), style: text.bodySmall),
          ]),
        ),
    ]);
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.points, this.reference, this.referenceLabel, this.hover});

  final List<(DateTime, double?)> points;
  final double? reference;
  final String? referenceLabel;
  final int? hover;

  @override
  void paint(Canvas canvas, Size size) {
    final values = [for (final p in points) if (p.$2 != null) p.$2!];
    if (values.isEmpty) return;
    var lo = values.reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    final ref = reference;
    // Drawn only when the readings come near it, so a quiet chart is not
    // flattened to show a threshold far above it.
    final showRef = ref != null && ref <= hi + (hi - lo > 2 ? (hi - lo) : 2) && ref >= lo - 2;
    if (showRef) {
      lo = lo < ref ? lo : ref;
      hi = hi > ref ? hi : ref;
    }
    if (hi - lo < 1e-6) {
      hi += 1;
      lo -= 1;
    }
    const pad = 8.0;
    final t0 = points.first.$1.millisecondsSinceEpoch;
    final span = points.last.$1.millisecondsSinceEpoch - t0;
    double x(int i) => points.length < 2 || span <= 0
        ? size.width / 2
        : (points[i].$1.millisecondsSinceEpoch - t0) / span * size.width;
    double y(double v) => pad + (1 - (v - lo) / (hi - lo)) * (size.height - pad * 2);

    // Recessive baseline.
    canvas.drawLine(Offset(0, size.height - 0.5), Offset(size.width, size.height - 0.5),
        Paint()..color = AppColors.divider..strokeWidth = 1);

    if (showRef) {
      final yy = y(ref);
      final dash = Paint()..color = AppColors.warning.withValues(alpha: 0.7)..strokeWidth = 1;
      for (double dx = 0; dx < size.width; dx += 8) {
        canvas.drawLine(Offset(dx, yy), Offset((dx + 4).clamp(0, size.width), yy), dash);
      }
      if (referenceLabel != null) {
        final tp = TextPainter(
          text: TextSpan(text: referenceLabel, style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(size.width - tp.width - 2, yy - tp.height - 1));
      }
    }

    // The line, broken where nothing was reported or the phone fell silent.
    final line = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Path? path;
    for (var i = 0; i < points.length; i++) {
      final v = points[i].$2;
      // A silence (no report for over 2.5 min; reports come every 30 s)
      // breaks the line rather than drawing across a stretch nobody saw.
      final silent = i > 0 && points[i].$1.difference(points[i - 1].$1).inSeconds > 150;
      if (silent && path != null) {
        canvas.drawPath(path, line);
        path = null;
      }
      if (v == null) {
        if (path != null) canvas.drawPath(path, line);
        path = null;
        continue;
      }
      final o = Offset(x(i), y(v));
      if (path == null) {
        path = Path()..moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    if (path != null) canvas.drawPath(path, line);

    void marker(int i) {
      final v = points[i].$2;
      if (v == null) return;
      final o = Offset(x(i), y(v));
      canvas.drawCircle(o, 5, Paint()..color = AppColors.surfaceRaised);
      canvas.drawCircle(o, 4, Paint()..color = AppColors.primary);
    }

    final h = hover;
    if (h != null && h < points.length) {
      canvas.drawLine(Offset(x(h), 0), Offset(x(h), size.height),
          Paint()..color = AppColors.border.withValues(alpha: 0.6)..strokeWidth = 1);
      marker(h);
    } else {
      final lastI = points.lastIndexWhere((p) => p.$2 != null);
      if (lastI >= 0) marker(lastI);
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.points != points || old.hover != hover || old.reference != reference;
}
