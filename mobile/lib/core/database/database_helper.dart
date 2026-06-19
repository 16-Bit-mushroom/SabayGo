import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  // 1. Singleton Setup
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // 2. Database Connection Getter
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('sabaygo.db');
    return _database!;
  }

  // 3. Initialize the Database File
  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    // Increase version number if you ever change the schema
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  // 4. Schema Definition (Data Dictionary Translation)
  // 4. Schema Definition (Domain Aligned)
  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT NOT NULL';
    const textNullable = 'TEXT';
    const intType = 'INTEGER NOT NULL';
    const doubleType = 'REAL NOT NULL';

    // The Users Table (Updated to match Python Domain Models)
    await db.execute('''
CREATE TABLE users (
  id $idType,
  firstName $textType,
  lastName $textType,
  middleName $textNullable,
  email $textType,
  phoneNumber $textType,
  emergencyContactName $textType,
  emergencyContactPhone $textType,
  accountType $textType,
  subscriptionTier $textType,
  rating $doubleType,
  joinDate $textType,
  totalTrips $intType,
  co2Saved $textType,
  availableVouchers $intType
)
''');

    // Seed the database with our prototype Passenger
    await db.insert('users', {
      'id': 'user_001',
      'firstName': 'Juan',
      'lastName': 'Dela Cruz',
      'middleName': 'Santos',
      'email': 'juan@example.edu.ph', // Required .edu.ph by Python invariants
      'phoneNumber': '+639171234567',
      'emergencyContactName': 'Maria Dela Cruz',
      'emergencyContactPhone': '+639189876543',
      'accountType': 'Passenger',
      'subscriptionTier': 'Free',
      'rating': 4.8,
      'joinDate': 'October 2025',
      'totalTrips': 42,
      'co2Saved': '12.5 kg',
      'availableVouchers': 3,
    });

    // 2. NEW: The Trips Table
    await db.execute('''
      CREATE TABLE trips (
        id $idType,
        passengerId $textType,
        driverName $textType,
        origin $textType,
        destination $textType,
        status $textType,
        fare $doubleType,
        date $textType,
        rideType $textType
      )
    ''');
  }

  // Utility method to close the database
  Future close() async {
    final db = await instance.database;
    db.close();
  }
}