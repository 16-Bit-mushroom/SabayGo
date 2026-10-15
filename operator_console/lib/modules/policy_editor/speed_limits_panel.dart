import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../core/network/api_exception.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/policy_repository.dart';

/// A2Z's speed limit for each stretch of a route, stop to stop, and the
/// stop zone (brief 6.3). Until a route has them only unscheduled stops
/// are flagged on it; with them, overspeed and slow stretches too. Each
/// stretch's expected time is worked out from its length when saved.
class SpeedLimitsPanel extends StatefulWidget {
  const SpeedLimitsPanel({super.key, required this.canEdit});
  final bool canEdit;

  @override
  State<SpeedLimitsPanel> createState() => _SpeedLimitsPanelState();
}

class _SpeedLimitsPanelState extends State<SpeedLimitsPanel> {
  late final PolicyRepository _policies = context.read<PolicyRepository>();
  List<RouteSummary>? _routes;
  RouteSummary? _route;
  List<RouteStretch> _stretches = const [];
  List<TextEditingController> _limits = [];
  final _zone = TextEditingController(text: '100');
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    context.read<DispatchRepository>().listRoutes().then((routes) {
      if (!mounted) return;
      setState(() => _routes = routes.where((r) => r.isActive).toList());
      if (_routes!.isNotEmpty) _pick(_routes!.first);
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
    });
  }

  @override
  void dispose() {
    for (final c in _limits) {
      c.dispose();
    }
    _zone.dispose();
    super.dispose();
  }

  Future<void> _pick(RouteSummary route) async {
    setState(() {
      _route = route;
      _busy = true;
      _error = null;
    });
    try {
      _show(await _policies.stretches(route.routeId));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(List<RouteStretch> stretches) {
    if (!mounted) return;
    final count = stretches.isNotEmpty ? stretches.length : (_route!.stopCount - 1).clamp(0, 99);
    for (final c in _limits) {
      c.dispose();
    }
    setState(() {
      _stretches = stretches;
      _limits = [
        for (var i = 0; i < count; i++)
          TextEditingController(text: stretches.isNotEmpty ? '${stretches[i].speedLimitKmh}' : '')
      ];
      if (stretches.isNotEmpty) _zone.text = '${stretches.first.stopZoneM}';
    });
  }

  Future<void> _save() async {
    final limits = [for (final c in _limits) int.tryParse(c.text.trim())];
    final zone = int.tryParse(_zone.text.trim());
    if (limits.any((l) => l == null || l <= 0) || zone == null) {
      setState(() => _error = 'Give every stretch a speed limit in km/h, and the stop zone in metres.');
      return;
    }
    setState(() => _busy = true);
    await runAction(context, () async {
      _show(await _policies.saveStretches(_route!.routeId, limits: limits.cast<int>(), stopZoneM: zone));
    }, 'Speed limits saved for ${_route!.routeName}. Flags on this route use them from now on.');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      title: 'Speed limits by route',
      icon: Icons.speed,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Each stretch runs stop to stop. Without limits, a route\'s trips are flagged only for '
            'unscheduled stops; with them, overspeed and slow stretches too.', style: text.bodySmall),
        const SizedBox(height: AppSpacing.md),
        if (_routes == null && _error == null) const LinearProgressIndicator(),
        if (_routes != null)
          DropdownButton<String>(
            value: _route?.routeId,
            items: [
              for (final r in _routes!) DropdownMenuItem(value: r.routeId, child: Text(r.routeName)),
            ],
            onChanged: (id) => _pick(_routes!.firstWhere((r) => r.routeId == id)),
          ),
        if (_error != null) Text(_error!, style: text.bodyMedium?.copyWith(color: AppColors.danger)),
        if (_route != null && !_busy) ...[
          if (_stretches.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text('Not set for this route yet.', style: text.bodyMedium?.copyWith(color: AppColors.warning)),
            ),
          for (var i = 0; i < _limits.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _stretches.isNotEmpty
                        ? 'Stretch ${i + 1}: ${_stretches[i].fromStop} → ${_stretches[i].toStop}, '
                            '${(_stretches[i].lengthM / 1000).toStringAsFixed(1)} km, expected '
                            '${(_stretches[i].expectedTimeS / 60).round()} min'
                        : 'Stretch ${i + 1}',
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _limits[i],
                    enabled: widget.canEdit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(suffixText: 'km/h', isDense: true),
                  ),
                ),
              ]),
            ),
          Row(children: [
            const Expanded(child: Text('Stop zone around each stop (radius)')),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _zone,
                enabled: widget.canEdit,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(suffixText: 'metres', isDense: true),
              ),
            ),
          ]),
          if (widget.canEdit) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _limits.isEmpty ? null : _save, child: const Text('Save speed limits')),
            ),
          ],
        ],
      ]),
    );
  }
}
