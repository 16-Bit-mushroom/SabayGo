import '../../core/network/api_client.dart';

double _money(Object? v) => v == null ? 0 : double.parse(v.toString());
DateTime? _time(Object? v) => v == null ? null : DateTime.parse(v as String);

/// A van's daily statement (Tables 37-38, brief 2.1): what its trips
/// carried, A2Z's share of it, and what has been paid.
class Statement {
  const Statement({
    required this.remittanceId,
    required this.plateNumber,
    required this.operatorName,
    required this.ratePct,
    required this.verifiedIncome,
    required this.declaredIncome,
    required this.remittanceOwed,
    required this.heldShare,
    required this.settledAmount,
    required this.amountDue,
    required this.disputed,
    required this.status,
    required this.settledAt,
    required this.settlementRef,
    required this.recordedByName,
    required this.handedOverByName,
    required this.lines,
  });

  final String remittanceId;
  final String plateNumber;
  final String operatorName;
  final double ratePct;
  /// Paid through the app (V) and in cash to the Dispatcher (D).
  final double verifiedIncome;
  final double declaredIncome;
  final double remittanceOwed;
  /// A2Z's share of a trip that left before it was paid.
  final double heldShare;
  final double settledAmount;
  /// What the Cashier should receive now: the undisputed balance.
  final double amountDue;
  final double disputed;
  final String status; // open | settled
  final DateTime? settledAt;
  final String? settlementRef;
  final String? recordedByName;
  final String? handedOverByName;
  final List<StatementLine> lines;

  factory Statement.fromJson(Map<String, dynamic> j) => Statement(
        remittanceId: j['remittance_id'] as String,
        plateNumber: j['plate_number'] as String,
        operatorName: j['operator_name'] as String,
        ratePct: _money(j['rate_pct']),
        verifiedIncome: _money(j['verified_income']),
        declaredIncome: _money(j['declared_income']),
        remittanceOwed: _money(j['remittance_owed']),
        heldShare: _money(j['held_share']),
        settledAmount: _money(j['settled_amount']),
        amountDue: _money(j['amount_due']),
        disputed: _money(j['disputed']),
        status: j['status'] as String,
        settledAt: _time(j['settled_at']),
        settlementRef: j['settlement_ref'] as String?,
        recordedByName: j['recorded_by_name'] as String?,
        handedOverByName: j['handed_over_by_name'] as String?,
        lines: [for (final l in j['lines'] as List) StatementLine.fromJson(l as Map<String, dynamic>)],
      );
}

/// Passengers of one trip to one drop-off terminal at one fare.
class StatementLine {
  const StatementLine({
    required this.lineId,
    required this.tripId,
    required this.tripDeparture,
    required this.destination,
    required this.incomeGroup,
    required this.fare,
    required this.count,
    required this.gross,
    required this.share,
    required this.isTopUp,
  });

  final String lineId;
  final String tripId;
  final DateTime tripDeparture;
  final String destination;
  final String incomeGroup; // V | D
  final double fare;
  final int count;
  final double gross;
  final double share;
  final bool isTopUp;

  factory StatementLine.fromJson(Map<String, dynamic> j) => StatementLine(
        lineId: j['line_id'] as String,
        tripId: j['trip_id'] as String,
        tripDeparture: DateTime.parse(j['trip_departure'] as String),
        destination: (j['dest_terminal_name'] ?? 'No drop-off terminal') as String,
        incomeGroup: j['income_group'] as String,
        fare: _money(j['fare_per_passenger']),
        count: j['passenger_count'] as int,
        gross: _money(j['gross_fare']),
        share: _money(j['share_amount']),
        isTopUp: j['is_top_up'] as bool,
      );
}

/// An operator's dispute of a fare line or a driving flag (Table 39).
class Dispute {
  const Dispute({
    required this.disputeId,
    required this.tripId,
    required this.tripLabel,
    required this.plateNumber,
    required this.subject,
    required this.item,
    required this.lineId,
    required this.drivingEventId,
    required this.operatorStatement,
    required this.amountDisputed,
    required this.raisedByName,
    required this.raisedAt,
    required this.status,
    required this.outcome,
    required this.adjustedAmount,
    required this.decidedByName,
    required this.decidedAt,
    required this.decisionNote,
  });

  final String disputeId;
  final String tripId;
  final String tripLabel;
  final String? plateNumber;
  final String subject; // fare_line | driving_flag
  final String item;
  final String? lineId;
  final String? drivingEventId;
  final String operatorStatement;
  final double amountDisputed;
  final String raisedByName;
  final DateTime raisedAt;
  final String status; // open | resolved | withdrawn
  final String? outcome; // upheld | rejected | adjusted
  final double? adjustedAmount;
  final String? decidedByName;
  final DateTime? decidedAt;
  final String? decisionNote;

  factory Dispute.fromJson(Map<String, dynamic> j) => Dispute(
        disputeId: j['dispute_id'] as String,
        tripId: j['trip_id'] as String,
        tripLabel: j['trip_label'] as String,
        plateNumber: j['plate_number'] as String?,
        subject: j['subject'] as String,
        item: j['item'] as String,
        lineId: j['line_id'] as String?,
        drivingEventId: j['driving_event_id'] as String?,
        operatorStatement: j['operator_statement'] as String,
        amountDisputed: _money(j['amount_disputed']),
        raisedByName: j['raised_by_name'] as String,
        raisedAt: DateTime.parse(j['raised_at'] as String),
        status: j['status'] as String,
        outcome: j['outcome'] as String?,
        adjustedAmount: j['adjusted_amount'] == null ? null : _money(j['adjusted_amount']),
        decidedByName: j['decided_by_name'] as String?,
        decidedAt: _time(j['decided_at']),
        decisionNote: j['decision_note'] as String?,
      );
}

/// Statements, payments and disputes: the Cashier records, the Terminal
/// Manager decides (brief 3, separation of duties).
class MoneyRepository {
  MoneyRepository(this._api);
  final ApiClient _api;

  Future<List<Statement>> statements(String day) async => [
        for (final s in await _api.get('/statements', query: {'date': day}) as List)
          Statement.fromJson(s as Map<String, dynamic>)
      ];

  Future<void> pay(String remittanceId,
          {required String amount, String? reference, String? handedOverBy}) =>
      _api.post('/statements/$remittanceId/payments', body: {
        'amount': amount,
        if (reference != null && reference.isNotEmpty) 'reference': reference,
        if (handedOverBy != null) 'handed_over_by': handedOverBy,
      });

  Future<List<Dispute>> disputes({String? status, String? tripId}) async => [
        for (final d in await _api.get('/disputes', query: {
          if (status != null) 'status': status,
          if (tripId != null) 'trip_id': tripId,
        }) as List)
          Dispute.fromJson(d as Map<String, dynamic>)
      ];

  Future<void> disputeLine(String lineId, String statement) => _api.post('/disputes',
      body: {'subject': 'fare_line', 'line_id': lineId, 'operator_statement': statement});

  Future<void> disputeFlag(String drivingEventId, String statement) => _api.post('/disputes', body: {
        'subject': 'driving_flag',
        'driving_event_id': drivingEventId,
        'operator_statement': statement,
      });

  Future<void> withdraw(String disputeId, String? note) => _api.post(
      '/disputes/$disputeId/withdraw', body: {if (note != null && note.isNotEmpty) 'note': note});

  Future<void> decide(String disputeId,
          {required String outcome, required String note, String? adjustedAmount}) =>
      _api.post('/disputes/$disputeId/decide', body: {
        'outcome': outcome,
        'note': note,
        if (adjustedAmount != null) 'adjusted_amount': adjustedAmount,
      });
}
