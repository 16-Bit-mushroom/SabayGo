import '../infrastructure/booking_dto.dart';

abstract class IBookingRepository {
  Future<DriverMatchDTO> findRide(String pickupNode, String dropoffNode);
}