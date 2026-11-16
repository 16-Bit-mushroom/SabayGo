import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/fleet_repository.dart';

/// Opens **Post a trip** in a window (12 Nov: the owner wanted a button on
/// the Trips page, not the whole form across it). [onPosted] runs after a
/// trip is posted and the window has closed.
Future<void> showPostTripDialog(
  BuildContext context, {
  required (List<Van>, List<StaffMember>)? roster,
  required VoidCallback onPosted,
}) =>
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: PostTripBox(
            roster: roster,
            onPosted: () {
              Navigator.pop(ctx);
              onPosted();
            },
          ),
        ),
      ),
    );

/// **Post a trip** (Terminal Manager, 11 Nov): putting a trip up for
/// passengers should feel like writing a post. Pick the time, press Post,
/// and the trip is bookable in the passenger app at once; the van and the
/// Dispatcher may wait for the van's turn. The form lives in a window
/// ([showPostTripDialog]); "Post 7 days of trips" sits beside its button.
class PostTripBox extends StatefulWidget {
  const PostTripBox({super.key, required this.roster, required this.onPosted});

  /// Validated, active vans and Dispatchers; null while loading.
  final (List<Van>, List<StaffMember>)? roster;
  final VoidCallback onPosted;

  @override
  State<PostTripBox> createState() => _PostTripBoxState();
}

class _PostTripBoxState extends State<PostTripBox> {
  late final Future<List<RouteSummary>> _routes = context
      .read<DispatchRepository>()
      .listRoutes()
      .then((all) => all.where((r) => r.isActive).toList());
  String? _routeId;
  bool _tomorrow = false;
  late TimeOfDay _time = _suggested();
  String? _vanId;
  String? _dispatcherId;
  bool _busy = false;

  /// The next half hour, an hour from now: a time the server will accept.
  static TimeOfDay _suggested() {
    final t = DateTime.now().add(const Duration(hours: 1));
    final half = t.minute < 30 ? 30 : 0;
    final hour = t.minute < 30 ? t.hour : (t.hour + 1) % 24;
    return TimeOfDay(hour: hour, minute: half);
  }

  DateTime get _departure {
    final d = DateUtils.dateOnly(DateTime.now()).add(Duration(days: _tomorrow ? 1 : 0));
    return DateTime(d.year, d.month, d.day, _time.hour, _time.minute);
  }

  Future<void> _post(String routeId) async {
    final when = _departure;
    final label = DateFormat.jm().format(when);
    if (!when.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label today has passed. Pick a later time, or tomorrow.')));
      return;
    }
    setState(() => _busy = true);
    final ok = await runAction(
      context,
      () => context
          .read<DispatchRepository>()
          .postTrip(routeId: routeId, departure: when, vanId: _vanId, dispatcherId: _dispatcherId),
      'Posted. Passengers can book the $label trip ${_tomorrow ? 'tomorrow' : 'today'} now.',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _vanId = null;
        _dispatcherId = null;
        _time = _suggested();
      }
    });
    if (ok) widget.onPosted();
  }

  /// The departure has gone by: the box says so and Post is disabled, so a
  /// trip nobody can catch is never posted (poka-yoke) -- not a refusal
  /// after the click.
  bool get _passed => !_departure.isAfter(DateTime.now());

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  // ── the fields, the same in the bar and the card ────────────────────────
  Widget _routeField(List<RouteSummary> routes, String? routeId) => routes.length == 1
      ? FieldBox(fixed: true, child: Text(routes.first.routeName))
      : FieldSelect<String?>(
          icon: Icons.route_outlined,
          value: routeId,
          items: [for (final r in routes) (r.routeId, r.routeName)],
          onChanged: (v) => setState(() => _routeId = v),
        );

  Widget _dayField() {
    final f = DateFormat('EEE d MMM');
    return FieldSelect<bool>(
      icon: Icons.calendar_today_outlined,
      value: _tomorrow,
      items: [
        (false, 'Today, ${f.format(DateTime.now())}'),
        (true, 'Tomorrow, ${f.format(DateTime.now().add(const Duration(days: 1)))}'),
      ],
      onChanged: (v) => setState(() => _tomorrow = v ?? false),
    );
  }

  Widget _timeField() => FieldBox(
        icon: Icons.schedule,
        chevron: true,
        problem: _passed,
        onTap: _pickTime,
        semanticLabel: 'Leaves at ${_time.format(context)}${_passed ? ', already passed' : ''}. Change the time',
        child: Text(_passed ? '${_time.format(context)} · passed' : _time.format(context)),
      );

  Widget _vanField(List<Van> vans) => FieldSelect<String?>(
        icon: Icons.airport_shuttle_outlined,
        value: _vanId,
        items: [(null, 'Later, at its turn'), for (final v in vans) (v.vanId, v.plateNumber)],
        onChanged: (v) => setState(() => _vanId = v),
      );

  Widget _crewField(List<StaffMember> crew) => FieldSelect<String?>(
        icon: Icons.badge_outlined,
        value: _dispatcherId,
        items: [(null, 'Later'), for (final d in crew) (d.userId, d.fullName)],
        onChanged: (v) => setState(() => _dispatcherId = v),
      );

  Widget _postButton(String? routeId) {
    final label = _time.format(context);
    final why = routeId == null
        ? 'Choose a route first.'
        : _passed
            ? '$label today has passed. Pick a later time, or Tomorrow.'
            : 'Opens booking for the $label trip ${_tomorrow ? 'tomorrow' : 'today'}.';
    return Tooltip(
      message: why,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size(120, AppSizing.field)),
        onPressed: routeId == null || _busy || _passed ? null : () => _post(routeId),
        icon: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onAction))
            : const Icon(Icons.send_outlined, size: 18),
        label: Text(_busy ? 'Posting…' : 'Post'),
      ),
    );
  }

  /// What passengers will see once it is posted, in words, before the
  /// click (visibility of system status); in red with the fix when the
  /// time has passed.
  Widget _preview(List<RouteSummary> routes, String? routeId, List<Van> vans, List<StaffMember> crew) {
    final text = Theme.of(context).textTheme;
    final time = _time.format(context);
    if (_passed) {
      return Row(children: [
        const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text('$time today has passed: nobody could catch it. Pick a later time, press + Next slot, or choose Tomorrow.',
              style: text.bodySmall?.copyWith(color: AppColors.danger, fontWeight: FontWeight.w600)),
        ),
      ]);
    }
    final route = routes.where((r) => r.routeId == routeId).map((r) => r.routeName).firstOrNull ?? '';
    final van = vans.where((v) => v.vanId == _vanId).map((v) => v.plateNumber).firstOrNull;
    final who = crew.where((d) => d.userId == _dispatcherId).map((d) => d.fullName).firstOrNull;
    return Row(children: [
      const Icon(Icons.visibility_outlined, size: 16, color: AppColors.primary),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: Text.rich(
          TextSpan(style: text.bodySmall, children: [
            const TextSpan(text: 'Passengers will see  '),
            TextSpan(
                text: '$route · ${_tomorrow ? 'tomorrow' : 'today'} $time',
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            TextSpan(text: '   ·   van ${van ?? 'at its turn'}   ·   Dispatcher ${who ?? 'later'}'),
          ]),
        ),
      ),
    ]);
  }

  /// The window's form, grouped by what the eye reads first (proximity):
  /// the trip -- route, day, time; then who runs it, both optional; then
  /// what passengers will see, and Post, the largest control, at the
  /// bottom right where the eye ends (Fitts). Every box is
  /// [AppSizing.field] high.
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final vans = widget.roster?.$1 ?? const <Van>[];
    final crew = widget.roster?.$2 ?? const <StaffMember>[];
    Widget field(Widget label, Widget box) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          label,
          const SizedBox(height: 6),
          box,
        ]);
    const gap = SizedBox(width: AppSpacing.md, height: AppSpacing.md);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: FutureBuilder<List<RouteSummary>>(
        future: _routes,
        builder: (context, snap) {
          final routes = snap.data ?? const <RouteSummary>[];
          final routeId = _routeId ?? (routes.isNotEmpty ? routes.first.routeId : null);
          return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primaryContainer,
                child: Icon(Icons.campaign_outlined, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Post a trip', style: text.titleLarge),
                  Text('Passengers can book it in the app as soon as you post it.', style: text.bodySmall),
                ]),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.close),
              ),
            ]),
            const SizedBox(height: AppSpacing.xl),
            if (snap.hasError)
              Text('The routes did not load. Close this and refresh the page.',
                  style: TextStyle(color: AppColors.danger))
            else if (snap.connectionState != ConnectionState.done)
              const LinearProgressIndicator()
            else if (routes.isEmpty)
              Text('No route is in service. Add one in Setup › Route first.', style: text.bodyMedium)
            else ...[
              field(const FieldLabel('Route'), _routeField(routes, routeId)),
              gap,
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: field(const FieldLabel('Day'), _dayField())),
                gap,
                Expanded(
                  child: field(
                      FieldLabel('Leaves at', link: '+ Next slot', onLink: () => setState(() {
                        _tomorrow = false;
                        _time = _suggested();
                      })),
                      _timeField()),
                ),
              ]),
              gap,
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(child: field(const FieldLabel('Van · optional'), _vanField(vans))),
                gap,
                Expanded(child: field(const FieldLabel('Dispatcher · optional'), _crewField(crew))),
              ]),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: _passed ? AppColors.dangerContainer : AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: _preview(routes, routeId, vans, crew),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(0, AppSizing.field)),
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppSpacing.sm),
                _postButton(routeId),
              ]),
            ],
          ]);
        },
      ),
    );
  }
}
