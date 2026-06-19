import '../../../../core/database/database_helper.dart';
import '../../../../core/domain/models/trip_model.dart';
import '../interfaces/i_booking_repository.dart';
import 'booking_dto.dart';

class SqliteBookingRepository implements IBookingRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // 1. MOCK LOGIC: We simulate finding a driver since SQLite can't do live matchmaking
  @override
  Future<DriverMatchDTO> findRide(String pickupNode, String dropoffNode) async {
    // Simulating network delay for realism
    await Future.delayed(const Duration(seconds: 2));

    return DriverMatchDTO(
      driverName: "Marcus Williams",
      driverRating: 4.9,
      vehiclePlate: "SBY 2026",
      vehicleModel: "Toyota Vios - Silver",
      etaMinutes: 5,
      fare: 180.00, // Standard solo flat rate
    );
  }

  // 2. REAL SQLITE LOGIC: Writing the trip to the device storage
  @override
  Future<void> saveTrip(TripModel trip) async {
    final db = await _dbHelper.database;
    await db.insert('trips', trip.toMap());
  }

  // 3. REAL SQLITE LOGIC: Fetching history for the Trips Tab
  @override
  Future<List<TripModel>> getUserTrips(String passengerId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'trips',
      where: 'passengerId = ?',
      whereArgs: [passengerId],
      orderBy: 'date DESC', // Shows newest trips at the top
    );

    return maps.map((map) => TripModel.fromMap(map)).toList();
  }
}