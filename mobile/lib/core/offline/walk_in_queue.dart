import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'pending_walk_in.dart';

/// On-device queue for walk-ins logged in a connectivity dead zone.
///
/// One table, keyed on `client_request_id` so `enqueue` is safe to call
/// again for the same submission without creating a second row.
class WalkInQueue {
  Database? _db;

  Future<Database> _open() async {
    return _db ??= await openDatabase(
      join(await getDatabasesPath(), 'sabaygo_walkin_queue.db'),
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE pending_walk_ins (
          client_request_id TEXT PRIMARY KEY,
          trip_id TEXT NOT NULL,
          boarding_stop INTEGER NOT NULL,
          alighting_stop INTEGER NOT NULL,
          name TEXT,
          phone TEXT,
          wants_receipt INTEGER NOT NULL,
          is_roadside_pickup INTEGER NOT NULL,
          pickup_landmark TEXT,
          fare_override REAL,
          fare_note TEXT,
          queued_at TEXT NOT NULL
        )
      '''),
    );
  }

  Future<void> enqueue(PendingWalkIn item) async {
    final db = await _open();
    await db.insert(
      'pending_walk_ins',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PendingWalkIn>> all() async {
    final db = await _open();
    final rows = await db.query('pending_walk_ins', orderBy: 'queued_at ASC');
    return rows.map(PendingWalkIn.fromMap).toList();
  }

  Future<int> countFor(String tripId) async {
    final db = await _open();
    final rows = await db.query(
      'pending_walk_ins',
      columns: ['client_request_id'],
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );
    return rows.length;
  }

  Future<void> remove(String clientRequestId) async {
    final db = await _open();
    await db.delete(
      'pending_walk_ins',
      where: 'client_request_id = ?',
      whereArgs: [clientRequestId],
    );
  }
}
