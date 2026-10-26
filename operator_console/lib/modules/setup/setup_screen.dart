import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/components/components.dart';
import '../../core/design/tokens.dart';
import '../../data/repositories/device_repository.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/fleet_repository.dart';
import '../../data/repositories/policy_repository.dart';
import '../../data/repositories/route_repository.dart';
import '../../data/repositories/schedule_repository.dart';
import '../../viewmodels/auth_provider.dart';
import '../phones/phones_screen.dart';
import '../policy_editor/screens/policy_editor_screen.dart';
import '../schedule_management/screens/schedule_screen.dart';
import 'fares_step.dart';
import 'operators_vans_step.dart';
import 'routes_step.dart';
import 'setup_status.dart';
import 'staff_step.dart';
import 'step_frame.dart';
import 'terminals_step.dart';

/// Setup: everything A2Z needs before the first trip, on one page (UI
/// redesign v3). The steps are a pila -- the terminal's van queue -- in
/// the order the system needs them, and the head of the queue is what to
/// do now. Each step's records are entered beside its list, so a first-day
/// set-up never jumps between pages; the same page serves later edits.
///
/// Done, to do and blocked are read from the database, never assumed: a
/// list that could not be read says so instead of passing as empty.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.onOpenTrips});

  /// "Ready for the first trip": opens Trips.
  final VoidCallback onOpenTrips;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final bool _manager = context.read<AuthProvider>().profile?.role.isManager ?? false;
  late final List<SetupStep> _steps = [
    for (final s in SetupStep.values)
      if (_manager || !s.managerOnly) s,
  ];
  SetupFacts? _facts;
  SetupStep? _step;

  @override
  void initState() {
    super.initState();
    _count();
  }

  /// Reads what each step judges by. One list failing blanks its own step.
  Future<void> _count() async {
    final routeRepo = context.read<RouteRepository>();
    final dispatch = context.read<DispatchRepository>();
    final fleet = context.read<FleetRepository>();
    final schedule = context.read<ScheduleRepository>();
    final devices = context.read<DeviceRepository>();
    final policies = context.read<PolicyRepository>();
    Future<T?> attempt<T>(Future<T> f) => f.then<T?>((v) => v).catchError((_) => null);
    Future<T?> managerOnly<T>(Future<T> Function() f) => _manager ? attempt(f()) : Future<T?>.value(null);

    final r = await Future.wait([
      managerOnly(routeRepo.terminals),
      attempt(dispatch.listRoutes()),
      attempt(fleet.listOperators()),
      attempt(fleet.listVans()),
      attempt(fleet.listCrew()),
      managerOnly(schedule.listTemplates),
      attempt(devices.list()),
      managerOnly(policies.list),
    ]);
    final routes = r[1] as List<RouteSummary>?;
    final fares = <String, List<Fare>>{};
    if (_manager && routes != null) {
      final lists = await Future.wait([for (final x in routes) attempt(routeRepo.fares(x.routeId))]);
      for (var i = 0; i < routes.length; i++) {
        if (lists[i] != null) fares[routes[i].routeId] = lists[i]!;
      }
    }
    if (!mounted) return;
    setState(() {
      _facts = SetupFacts(
        terminals: r[0] as List<Terminal>?,
        routes: routes,
        fares: fares,
        operators: r[2] as List<OperatorRecord>?,
        vans: r[3] as List<Van>?,
        crew: r[4] as List<StaffMember>?,
        templates: r[5] as List<ScheduleTemplate>?,
        phones: r[6] as List<Phone>?,
        policies: r[7] as List<Policy>?,
      );
      _step ??= _head ?? _steps.first;
    });
  }

  StepStatus _status(SetupStep s) =>
      _facts?.of(s) ?? const StepStatus(SetupState.todo, 'Counting…');

  /// The first required step not done: what to do now. Null when every
  /// required step is done.
  SetupStep? get _head {
    if (_facts == null) return null;
    for (final s in _steps) {
      if (!s.optional && _status(s).state != SetupState.done) return s;
    }
    return null;
  }

  void _open(SetupStep s) {
    setState(() => _step = s);
    _count();
  }

  Widget _body(SetupStep step) => switch (step) {
        SetupStep.terminals => TerminalsStep(onChanged: _count),
        SetupStep.route => RoutesStep(onChanged: _count, onOpenStep: _open),
        SetupStep.fares => FaresStep(onChanged: _count, onOpenStep: _open),
        SetupStep.operatorsVans => OperatorsVansStep(onChanged: _count),
        SetupStep.staff => StaffStep(onChanged: _count),
        SetupStep.timetable => ScheduleScreen(onChanged: _count, onOpenRoute: () => _open(SetupStep.route)),
        SetupStep.phones => PhonesScreen(onChanged: _count),
        SetupStep.rules => const PolicyEditorScreen(),
      };

  @override
  Widget build(BuildContext context) {
    final step = _step;
    final head = _head;
    final required = [for (final s in _steps) if (!s.optional) s];
    final done = required.where((s) => _status(s).state == SetupState.done).length;
    // The Cashier's queue holds only their own steps, so "ready" is the
    // Terminal Manager's to see.
    final ready = _manager && _facts != null && head == null;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(
          title: 'Setup',
          description: _manager
              ? 'Everything A2Z needs before the first trip, in the order the system needs it. '
                  'The head of the queue is the next thing to do.'
              : 'The vans, staff and phones on A2Z\'s roster. The Terminal Manager sets up '
                  'terminals, routes, fares and the timetable.',
          actions: [
            if (ready)
              OutlinedButton.icon(
                onPressed: widget.onOpenTrips,
                icon: const Icon(Icons.departure_board, size: 18),
                label: const Text('Go to Trips'),
              )
            else if (step != null && head != null && head != step && _status(step).state == SetupState.done)
              OutlinedButton.icon(
                onPressed: () => _open(head),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text('Next: ${head.label}'),
              ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final queue = _Queue(
              steps: _steps,
              status: _status,
              selected: step,
              head: head,
              done: done,
              total: required.length,
              ready: ready,
              sosOff: _manager && !(_facts?.sosNumbersSet ?? true),
              onOpen: _open,
              compact: c.maxWidth < 980,
            );
            // The queue and the open step are separate stops for Tab: the
            // whole queue, then the step's list and form.
            final body = FocusTraversalGroup(
              child: step == null
                  ? const Center(child: CircularProgressIndicator())
                  : KeyedSubtree(key: ValueKey(step), child: _body(step)),
            );
            if (c.maxWidth < 980) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(height: 64, child: FocusTraversalGroup(child: queue)),
                const SizedBox(height: AppSpacing.lg),
                Expanded(child: body),
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: c.maxWidth >= 1100 ? 272 : 248, child: FocusTraversalGroup(child: queue)),
              const SizedBox(width: AppSpacing.xl),
              Expanded(child: body),
            ]);
          }),
        ),
      ]),
    );
  }
}

/// The set-up queue: the pila strip. Numbered tiles in the order the
/// system needs them; the head is raised and marked Now. A done step's
/// tile fills green with a check, a blocked one is locked, and every state
/// is also said in words.
class _Queue extends StatelessWidget {
  const _Queue({
    required this.steps,
    required this.status,
    required this.selected,
    required this.head,
    required this.done,
    required this.total,
    required this.ready,
    required this.sosOff,
    required this.onOpen,
    required this.compact,
  });

  final List<SetupStep> steps;
  final StepStatus Function(SetupStep) status;
  final SetupStep? selected;
  final SetupStep? head;
  final int done;
  final int total;
  final bool ready;

  /// No SOS number is set: an emergency is recorded, nobody is texted.
  /// Said beside "Ready" rather than blocking it (a setting left unset is
  /// off, and A2Z has not supplied the numbers yet).
  final bool sosOff;
  final ValueChanged<SetupStep> onOpen;

  /// A narrow window: one scrolling row of tiles above the step.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (compact) {
      return _Strip(
        done: done,
        total: total,
        focus: selected,
        slots: [
          for (var i = 0; i < steps.length; i++)
            (
              steps[i],
              _Slot(
                number: i + 1,
                step: steps[i],
                status: status(steps[i]),
                selected: steps[i] == selected,
                head: steps[i] == head,
                compact: true,
                onTap: () => onOpen(steps[i]),
              ),
            ),
        ],
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      // The right gutter keeps the scrollbar off the count and the slots.
      child: ScrollWithThumb(
        child: Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, AppSpacing.md),
          child: Row(children: [
            Expanded(child: Text('Set-up queue', style: text.titleSmall)),
            Text('$done of $total done',
                style: text.bodySmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
        // Done steps fill the bar from the left, in order, as the queue
        // empties.
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : done / total,
            minHeight: 4,
            backgroundColor: AppColors.surfaceSunken,
            semanticsLabel: 'Set-up progress',
            semanticsValue: '$done of $total steps done',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        for (var i = 0; i < steps.length; i++)
          _Slot(
            number: i + 1,
            step: steps[i],
            status: status(steps[i]),
            selected: steps[i] == selected,
            head: steps[i] == head,
            compact: false,
            onTap: () => onOpen(steps[i]),
          ),
        if (ready) ...[
          const SizedBox(height: AppSpacing.sm),
          const Divider(),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            QueueTile('', icon: Icons.flag_outlined, filled: true, size: 32),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text('Ready for the first trip', style: text.titleSmall)),
          ]),
          if (sosOff) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.warning),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text('Emergency texts are off: no SOS numbers are set. An SOS is still '
                    'recorded here, but nobody is texted.', style: text.bodySmall),
              ),
            ]),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onOpen(SetupStep.rules),
                child: const Text('Set the SOS numbers'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text('Assign a van and Dispatcher to a departure on Trips, and check a phone out to them.',
              style: text.bodySmall),
        ],
      ]),
      ),
      ),
    );
  }
}

/// The queue in a narrow window: one row of slots that scrolls sideways.
/// Its progress stays in front, a scrollbar shows whenever steps are out
/// of sight, and the open step is scrolled into view.
class _Strip extends StatefulWidget {
  const _Strip({required this.done, required this.total, required this.focus, required this.slots});

  final int done;
  final int total;
  final SetupStep? focus;
  final List<(SetupStep, Widget)> slots;

  @override
  State<_Strip> createState() => _StripState();
}

class _StripState extends State<_Strip> {
  final _scroll = ScrollController();
  final _keys = <SetupStep, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(_Strip old) {
    super.didUpdateWidget(old);
    if (old.focus != widget.focus) _reveal();
  }

  void _reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _keys[widget.focus]?.currentContext;
        if (c != null && mounted) {
          Scrollable.ensureVisible(c,
              alignment: 0.5,
              duration: MediaQuery.of(context).disableAnimations ? Duration.zero : AppDuration.quick);
        }
      });

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text('${widget.done} of ${widget.total} done',
          style: Theme.of(context).textTheme.bodySmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(children: [
              for (final (i, (step, slot)) in widget.slots.indexed) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                KeyedSubtree(key: _keys.putIfAbsent(step, GlobalKey.new), child: slot),
              ],
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.number,
    required this.step,
    required this.status,
    required this.selected,
    required this.head,
    required this.compact,
    required this.onTap,
  });

  final int number;
  final SetupStep step;
  final StepStatus status;
  final bool selected;
  final bool head;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // The head of the queue is raised wherever the office is looking: what
    // to do now never moves because another step is open. The open step is
    // outlined.
    final raised = head && !compact;
    final size = raised ? 44.0 : 30.0;
    final tile = switch (status.state) {
      SetupState.done => QueueTile('$number', filled: true, done: true, size: size),
      SetupState.blocked => QueueTile('', icon: Icons.lock_outline, muted: true, size: size),
      SetupState.optional => QueueTile('', icon: Icons.tune, muted: true, size: size),
      SetupState.todo => QueueTile('$number', size: size),
    };
    final word = switch (status.state) {
      SetupState.done => 'done',
      SetupState.blocked => 'waiting',
      SetupState.optional => 'optional',
      SetupState.todo => head ? 'next' : 'to do',
    };
    final reduce = MediaQuery.of(context).disableAnimations;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Step $number, ${step.label}, $word. ${status.note}',
      excludeSemantics: true,
      // The child's tap is excluded with its semantics; without this the
      // step is a button a screen reader cannot press.
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(bottom: compact ? 0 : AppSpacing.xs),
        child: Material(
          color: Colors.transparent,
          child: FocusRing(
            color: AppColors.textPrimary,
            child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.md),
            hoverColor: AppColors.surfaceSunken,
            child: AnimatedContainer(
              duration: reduce ? Duration.zero : AppDuration.quick,
              curve: Curves.easeOut,
              padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: raised ? AppSpacing.md : AppSpacing.sm),
              decoration: BoxDecoration(
                color: head ? AppColors.primaryContainer : Colors.transparent,
                border: Border.all(color: selected ? AppColors.primary : Colors.transparent, width: 1.5),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max, children: [
                tile,
                const SizedBox(width: AppSpacing.md),
                if (compact)
                  Text(step.label, style: text.labelLarge)
                else
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: Text(step.label,
                              overflow: TextOverflow.ellipsis,
                              style: (raised ? text.titleMedium : text.titleSmall)!.copyWith(
                                  color: status.state == SetupState.blocked ? AppColors.textMuted : null)),
                        ),
                        if (head) ...[const SizedBox(width: AppSpacing.sm), const _NowPill()],
                      ]),
                      Text(status.note,
                          style: status.warning ? text.bodySmall!.copyWith(color: AppColors.warning) : text.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                if (compact && head) ...[const SizedBox(width: AppSpacing.sm), const _NowPill()],
              ]),
            ),
          ),
          ),
        ),
      ),
    );
  }
}

/// The head of the queue, said in a word.
class _NowPill extends StatelessWidget {
  const _NowPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Text('Now',
          style: TextStyle(color: AppColors.onFill, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
    );
  }
}
