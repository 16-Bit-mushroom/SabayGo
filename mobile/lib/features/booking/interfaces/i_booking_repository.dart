import '../infrastructure/booking_dto.dart';
import '../../../../core/domain/models/trip_model.dart';

abstract class IBookingRepository {
  // Phase 1: Mock matching a driver
  Future<DriverMatchDTO> findRide(String pickupNode, String dropoffNode);
  
  // Phase 2: Real SQLite persistence
  Future<void> saveTrip(TripModel trip);
  Future<List<TripModel>> getUserTrips(String passengerId);
}