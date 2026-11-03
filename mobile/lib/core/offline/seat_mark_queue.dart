import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// A Mark as Paid or a Dispatcher cancel made while offline, waiting to
/// reach the server (brief rev 721, 2.1: both work offline).
///
/// Keyed on the booking: a second mark for the same seat replaces the
/// first, so the queue holds the Dispatcher's latest word on each seat.
/// Replaying is safe -- the server accepts a Paid mark on a seat already
/// paid and changes nothing -- and `at` is when the Dispatcher acted, so
/// a mark that syncs late keeps the moment the cash was handed over.
class PendingSeatMark {
  const PendingSeatMark({
    required this.bookingId,
    required this.tripId,
    required this.kind,
    required this.at,
    required this.label,
    this.reason,
  });

  final String bookingId;
  final String tripId;

  /// 'paid' or 'cancel'.
  final String kind;
  final DateTime at;

  /// The name or booking code, for the Dispatcher's screen while it waits.
  final String label;

  /// For a cancel: passenger_asked_dispatcher | forgot_to_cancel.
  final String? reason;

  bool get isPaid => kind == 'paid';

  Map<String, Object?> toMap() => {
        'booking_id': bookingId,
        'trip_id': tripId,
        'kind': kind,
        'at': at.toIso8601String(),
        'label': label,
        'reason': reason,
      };

  factory PendingSeatMark.fromMap(Map<String, Object?> m) => PendingSeatMark(
        bookingId: m['booking_id'] as String,
        tripId: m['trip_id'] as String,
        kind: m['kind'] as String,
        at: DateTime.parse(m['at'] as String),
        label: m['label'] as String,
        reason: m['reason'] as String?,
      );
}

/// On-device queue of [PendingSeatMark]s, beside the walk-in queue and
/// with the same rules: reads degrade to empty where there is no storage,
/// and [enqueue] throws there rather than drop a fare already taken.
class SeatMarkQueue {
  static bool get isSupported => !kIsWeb;

  Database? _db;

  Future<Database> _open() async {
    return _db ??= await openDatabase(
      join(await getDatabasesPath(), 'sabaygo_seat_marks.db'),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE pending_seat_marks (
          booking_id TEXT PRIMARY KEY,
          trip_id TEXT NOT NULL,
          kind TEXT NOT NULL,
          at TEXT NOT NULL,
          label TEXT NOT NULL,
          reason TEXT
        )
      '''),
    );
  }

  Future<void> enqueue(PendingSeatMark item) async {
    if (!isSupported) {
      throw UnsupportedError(
        'Offline marks need on-device storage, which this platform does not '
        'provide. Mark this seat from the Dispatcher handset.',
      );
    }
    final db = await _open();
    await db.insert('pending_seat_marks', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PendingSeatMark>> all() async {
    if (!isSupported) return const [];
    final db = await _open();
    final rows = await db.query('pending_seat_marks', orderBy: 'at ASC');
    return rows.map(PendingSeatMark.fromMap).toList();
  }

  Future<void> remove(String bookingId) async {
    if (!isSupported) return;
    final db = await _open();
    await db.delete('pending_seat_marks', where: 'booking_id = ?', whereArgs: [bookingId]);
  }
}
