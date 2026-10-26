import '../../data/repositories/device_repository.dart';
import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/fleet_repository.dart';
import '../../data/repositories/policy_repository.dart';
import '../../data/repositories/route_repository.dart';
import '../../data/repositories/schedule_repository.dart';

/// The set-up queue, in the order the system needs it: a route needs its
/// terminals, fares need a route, a trip needs a validated van, Dispatcher
/// and a departure on the timetable, and an audited trip needs a phone.
enum SetupStep {
  terminals('Terminals', managerOnly: true),
  route('Route', managerOnly: true),
  fares('Fares', managerOnly: true),
  operatorsVans('Operators & vans'),
  staff('Staff'),
  timetable('Timetable', managerOnly: true),
  phones('Phones'),
  rules('Rules & Settings', managerOnly: true, optional: true);

  const SetupStep(this.label, {this.managerOnly = false, this.optional = false});

  final String label;

  /// Hidden from the Cashier, as the pages were (brief section 3).
  final bool managerOnly;

  /// Never blocks the first trip: a setting left unset is off.
  final bool optional;
}

enum SetupState { done, todo, blocked, optional }

/// A step's state and the one sentence that explains it.
class StepStatus {
  const StepStatus(this.state, this.note, {this.warning = false});
  final SetupState state;
  final String note;

  /// Something is off that does not block the step: said in the note.
  final bool warning;
}

/// What the database already holds, read once from the endpoints the steps
/// themselves use, and judged step by step. A list that fails to load is
/// null, and its step says so rather than claiming it is empty.
class SetupFacts {
  SetupFacts({
    this.terminals,
    this.routes,
    this.fares = const {},
    this.operators,
    this.vans,
    this.crew,
    this.templates,
    this.phones,
    this.policies,
  });

  final List<Terminal>? terminals;
  final List<RouteSummary>? routes;
  final Map<String, List<Fare>> fares;
  final List<OperatorRecord>? operators;
  final List<Van>? vans;
  final List<StaffMember>? crew;
  final List<ScheduleTemplate>? templates;
  final List<Phone>? phones;
  final List<Policy>? policies;

  /// False only when the settings were read and no SOS number is set, so
  /// an emergency is recorded but nobody is texted. Unread is not "off".
  bool get sosNumbersSet =>
      policies?.any((p) => p.policyKey == 'sos_contact_numbers' && p.policyValue.trim().isNotEmpty) ??
      true;

  int get openTerminals => terminals?.where((t) => t.isActive).length ?? 0;
  List<RouteSummary> get liveRoutes => [for (final r in routes ?? const <RouteSummary>[]) if (r.isActive) r];

  /// Drop-offs on [route] with no fare in force from stop 1.
  List<String> missingFares(RouteSummary route) {
    final inForce = {
      for (final f in fares[route.routeId] ?? const <Fare>[])
        if (f.fromStop == 1 && f.status == 'in_force') f.toStop
    };
    return [for (final s in route.stops.skip(1)) if (!inForce.contains(s.sequence)) s.name];
  }

  StepStatus of(SetupStep step) {
    const unknown = StepStatus(SetupState.todo, 'Could not be read; refresh to try again');
    switch (step) {
      case SetupStep.terminals:
        if (terminals == null) return unknown;
        final n = openTerminals;
        return n >= 2
            ? StepStatus(SetupState.done, '$n open')
            : StepStatus(SetupState.todo, n == 0 ? 'None yet · a route needs 2' : '1 open · a route needs 2');
      case SetupStep.route:
        if (routes == null) return unknown;
        final live = liveRoutes.length;
        if (live > 0) return StepStatus(SetupState.done, '$live in service');
        return openTerminals < 2
            ? const StepStatus(SetupState.blocked, 'Waits for two open terminals')
            : const StepStatus(SetupState.todo, 'Enter the stops in order');
      case SetupStep.fares:
        if (routes == null) return unknown;
        final live = liveRoutes;
        if (live.isEmpty) return const StepStatus(SetupState.blocked, 'Waits for a route');
        final missing = live.fold<int>(0, (n, r) => n + missingFares(r).length);
        return missing == 0
            ? const StepStatus(SetupState.done, 'Every drop-off has a fare')
            : StepStatus(SetupState.todo, '$missing drop-off${missing == 1 ? '' : 's'} without a fare');
      case SetupStep.operatorsVans:
        if (vans == null || operators == null) return unknown;
        final ready = vans!.where((v) =>
            v.validationStatus == 'validated' &&
            v.operationalStatus == 'active' &&
            operators!.any((o) => o.vanId == v.vanId && o.validationStatus == 'validated'));
        if (ready.isNotEmpty) return StepStatus(SetupState.done, '${ready.length} van${ready.length == 1 ? '' : 's'} ready');
        if (vans!.isEmpty) {
          return StepStatus(SetupState.todo, operators!.isEmpty ? 'No operator or van yet' : 'No van yet');
        }
        return const StepStatus(SetupState.todo, 'No validated van yet');
      case SetupStep.staff:
        if (crew == null) return unknown;
        final dispatcher = crew!.any((s) =>
            s.role == 'dispatcher' && s.validationStatus == 'validated' && s.employmentStatus == 'active');
        final cashier = crew!.any((s) => s.role == 'cashier' && s.employmentStatus == 'active');
        if (dispatcher && cashier) return const StepStatus(SetupState.done, 'Dispatcher and Cashier ready');
        return StepStatus(SetupState.todo, switch ((dispatcher, cashier)) {
          (false, false) => 'Needs a validated Dispatcher and a Cashier',
          (false, true) => 'Needs a validated Dispatcher',
          _ => 'Needs a Cashier',
        });
      case SetupStep.timetable:
        if (templates == null) return unknown;
        final n = templates!.where((t) => t.isActive).length;
        if (n > 0) return StepStatus(SetupState.done, '$n regular departure${n == 1 ? '' : 's'}');
        return liveRoutes.isEmpty
            ? const StepStatus(SetupState.blocked, 'Waits for a route')
            : const StepStatus(SetupState.todo, 'No departure yet');
      case SetupStep.phones:
        if (phones == null) return unknown;
        final n = phones!.where((p) => p.status != 'retired').length;
        return n > 0
            // Counted whether in the office or out with a van.
            ? StepStatus(SetupState.done, '$n phone${n == 1 ? '' : 's'} added')
            : const StepStatus(SetupState.todo, 'No phone yet');
      case SetupStep.rules:
        if (!sosNumbersSet) {
          return const StepStatus(SetupState.optional, 'Emergency texts are off: no SOS numbers set',
              warning: true);
        }
        return const StepStatus(SetupState.optional, 'Optional · a setting left unset is off');
    }
  }
}
