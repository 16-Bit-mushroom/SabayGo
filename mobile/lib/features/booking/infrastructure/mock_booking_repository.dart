import '../interfaces/i_booking_repository.dart';
import 'booking_dto.dart';

class MockBookingRepository implements IBookingRepository {
  @override
  Future<DriverMatchDTO> findRide(String pickupNode, String dropoffNode) async {
    // Simulate the NAHGM routing algorithm processing time
    await Future.delayed(const Duration(seconds: 2));

    // Return hardcoded data localized to your presentation
    return DriverMatchDTO(
      driverName: "Marcus Williams",
      vehicleModel: "Toyota Vios",
      plateNumber: "DVO-4892",
      vehicleColor: "Pearl White",
      rating: "4.9",
    );
  }
}