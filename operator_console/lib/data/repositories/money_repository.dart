import '../../core/network/api_client.dart';

double _money(Object? v) => v == null ? 0 : double.parse(v.toString());
DateTime? _time(Object? v) => v == null ? null : DateTime.parse(v as String);

/// A van's daily statement (Tables 37-38, brief 2.1): what its trips
/// carried, the terminal fees it owes (A2Z's 15 %, the DCOTT ticket per
/// trip, the day's parking), what has been paid, and the operator's share.
class Statement {
  const Statement({
    required this.remittanceId,
    required this.plateNumber,
    required this.operatorName,
    required this.ratePct,
    required this.vanId,
    required this.bookedIncome,
    required this.walkUpIncome,
    required this.remittanceOwed,
    required this.dcottTicketFee,
    required this.dcottFees,
    required this.parkingFee,
    required this.terminalFeesOwed,
    required this.heldShare,
    required this.settledAmount,
    required this.amountDue,
    required this.disputed,
    required this.operatorShareOwed,
    required this.operatorShareGiven,
    required this.operatorShareGivenAt,
    required this.operatorShareRecordedByName,
    required this.operatorShareDifference,
    required this.operatorShareDiffers,
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
  final String vanId;
  final double ratePct;
  /// Reserved in the app (B) and listed as walk-ups (W); all of it cash.
  final double bookedIncome;
  final double walkUpIncome;
  /// A2Z's 15 % of the income.
  final double remittanceOwed;
  /// The ticket price, and the ticket times the van's trips.
  final double dcottTicketFee;
  final double dcottFees;
  final double parkingFee;
  /// The 15 %, the tickets and the parking together.
  final double terminalFeesOwed;
  /// A2Z's share of a trip that left before it was paid.
  final double heldShare;
  final double settledAmount;
  /// What the Cashier should receive now: the undisputed balance.
  final double amountDue;
  final double disputed;
  /// What is left of the cash for the operator, and what the Cashier
  /// recorded the Dispatcher handing over. A difference warns; it blocks
  /// nothing.
  final double operatorShareOwed;
  final double operatorShareGiven;
  final DateTime? operatorShareGivenAt;
  final String? operatorShareRecordedByName;
  /// Null until every trip's list is locked.
  final double? operatorShareDifference;
  final bool operatorShareDiffers;
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
        vanId: j['van_id'] as String,
        ratePct: _money(j['rate_pct']),
        bookedIncome: _money(j['booked_income']),
        walkUpIncome: _money(j['walk_up_income']),
        remittanceOwed: _money(j['remittance_owed']),
        dcottTicketFee: _money(j['dcott_ticket_fee']),
        dcottFees: _money(j['dcott_fees']),
        parkingFee: _money(j['parking_fee']),
        terminalFeesOwed: _money(j['terminal_fees_owed']),
        heldShare: _money(j['held_share']),
        settledAmount: _money(j['settled_amount']),
        amountDue: _money(j['amount_due']),
        disputed: _money(j['disputed']),
        operatorShareOwed: _money(j['operator_share_owed']),
        operatorShareGiven: _money(j['operator_share_given']),
        operatorShareGivenAt: _time(j['operator_share_given_at']),
        operatorShareRecordedByName: j['operator_share_recorded_by_name'] as String?,
        operatorShareDifference:
            j['operator_share_difference'] == null ? null : _money(j['operator_share_difference']),
        operatorShareDiffers: j['operator_share_differs'] as bool? ?? false,
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
  final String incomeGroup; // booked | walk_up
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

  /// Terminal fees handed over, with the operator's share the
  /// Dispatcher gave the operator in the same step.
  Future<void> pay(String remittanceId,
          {required String amount, String? reference, String? handedOverBy, String? operatorShare}) =>
      _api.post('/statements/$remittanceId/payments', body: {
        'amount': amount,
        if (reference != null && reference.isNotEmpty) 'reference': reference,
        if (handedOverBy != null) 'handed_over_by': handedOverBy,
        if (operatorShare != null && operatorShare.isNotEmpty) 'operator_share': operatorShare,
      });

  /// A difference in the operator's share, handed over after the payment.
  Future<void> recordOperatorShare(String remittanceId, String amount) =>
      _api.post('/statements/$remittanceId/operator-share', body: {'amount': amount});

  /// The day's parking for a van at the terminal with no trip. 409 when
  /// the van already has a statement today.
  Future<void> chargeParking(String vanId) => _api.post('/statements/parking', body: {'van_id': vanId});

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
