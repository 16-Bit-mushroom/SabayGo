import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/repositories/dispatch_repository.dart';
import '../../data/repositories/messaging_repository.dart';
import '../../data/repositories/money_repository.dart';
import '../../data/repositories/oversight_repository.dart';
import '../design/components/actions.dart';

/// What waits in the sidebar: a decision under Reviews, one figure per
/// tab, and unread messages beside Messages.
///
/// Each figure is the list its own screen opens on, counted: automatic
/// starts not yet reviewed today, boardings not on a list today, open
/// driving flags today, open disputes, and the unread messages across the
/// office's conversations. A figure that fails to load is null and shows
/// no number -- never a zero, which would say "nothing to review" when the
/// truth is "could not ask". Polled like the today strip.
class ReviewCounts extends ChangeNotifier {
  ReviewCounts({
    required this.dispatch,
    required this.oversight,
    required this.money,
    required this.messaging,
    required this.manager,
  }) {
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  final DispatchRepository dispatch;
  final OversightRepository oversight;
  final MoneyRepository money;
  final MessagingRepository messaging;

  /// The Cashier is not shown Review Starts or Boarding Audit, so those
  /// are not asked for.
  final bool manager;

  Timer? _timer;
  int? starts;
  int? boardings;
  int? flags;
  int? disputes;

  /// Unread messages, for the Messages entry. Not part of [total].
  int? messages;

  /// The sum of what loaded, for the Reviews entry; null when nothing did.
  int? get total {
    final known = [starts, boardings, flags, disputes].whereType<int>();
    return known.isEmpty ? null : known.fold<int>(0, (a, b) => a + b);
  }

  Future<void> refresh() async {
    final today = isoDay(DateTime.now());
    Future<int?> attempt(Future<int> f) => f.then<int?>((v) => v).catchError((_) => null);
    final r = await Future.wait([
      manager
          ? attempt(dispatch.tripBoard(DateTime.now()).then((b) => b.where((t) => t.awaitsReview).length))
          : Future<int?>.value(null),
      manager
          ? attempt(oversight.boardingAudit(today).then((trips) => trips.fold<int>(
              0, (n, t) => n + t.unlisted.where((u) => u.resolution == 'pending').length)))
          : Future<int?>.value(null),
      attempt(oversight.drivingFlags(day: today, status: 'open').then((f) => f.length)),
      attempt(money.disputes(status: 'open').then((d) => d.length)),
      attempt(messaging.listConversations().then((c) => c.fold<int>(0, (n, x) => n + x.unreadCount))),
    ]);
    if (_timer == null) return;
    starts = r[0];
    boardings = r[1];
    flags = r[2];
    disputes = r[3];
    messages = r[4];
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
