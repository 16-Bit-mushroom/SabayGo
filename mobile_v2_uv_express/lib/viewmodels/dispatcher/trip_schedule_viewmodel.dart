import 'package:flutter/material.dart';
import '../../models/driver_model.dart';
import '../../models/van_model.dart';
import '../../models/uv_trip_model.dart';
import '../../models/transit_node_model.dart';

class TripScheduleViewModel extends ChangeNotifier {
  TripScheduleViewModel() {
    _loadMockData();
  }

  List<VanModel> fleetVans = [];
  List<UvTripModel> postedSchedules = [];
  List<DriverModel> crewDrivers = [];

  // --- CRUD Operations for Fleet (Vans) ---
  void saveVan(VanModel van) {
    final existingIndex = fleetVans.indexWhere((v) => v.id == van.id);
    if (existingIndex >= 0) {
      fleetVans[existingIndex] = van; // Update
    } else {
      fleetVans.add(van); // Create
    }
    notifyListeners();
  }

  void deleteVan(String vanId) {
    fleetVans.removeWhere((v) => v.id == vanId);
    notifyListeners();
  }

  void toggleVanStatus(String vanId, VanStatus newStatus) {
    final index = fleetVans.indexWhere((v) => v.id == vanId);
    if (index >= 0) {
      fleetVans[index] = fleetVans[index].copyWith(status: newStatus);
      notifyListeners();
    }
  }

  // --- CRUD Operations for Crew (Drivers) ---
  void saveDriver(DriverModel driver) {
    final existingIndex = crewDrivers.indexWhere((d) => d.id == driver.id);
    if (existingIndex >= 0) {
      crewDrivers[existingIndex] = driver; // Update
    } else {
      crewDrivers.add(driver); // Create
    }
    notifyListeners();
  }

  void deleteDriver(String driverId) {
    crewDrivers.removeWhere((d) => d.id == driverId);
    notifyListeners();
  }

  // --- Core Compliance Logic ---
  List<VanModel> getAvailableVansForRoute(
    String originId,
    String destinationId,
  ) {
    return fleetVans.where((van) {
      final isRegistered =
          van.registeredRouteNodeIds.contains(originId) &&
          van.registeredRouteNodeIds.contains(destinationId);
      return isRegistered && van.status == VanStatus.active;
    }).toList();
  }

  void _loadMockData() {
    // 1. Load Vans
    fleetVans = [
      VanModel(
        id: 'v1',
        plateNumber: 'ABC-1234',
        cpcNumber: '14523-DVO',
        cpcCaseNumber: '23-01450',
        brand: 'Toyota',
        model: 'Hiace Commuter',
        color: 'White',
        registeredRouteNodeIds: ['n1', 'n2'],
        status: VanStatus.active,
      ),
      VanModel(
        id: 'v2',
        plateNumber: 'XYZ-9876',
        cpcNumber: '88321-DVO',
        cpcCaseNumber: '21-08832',
        brand: 'Nissan',
        model: 'Urvan NV350',
        color: 'Silver',
        registeredRouteNodeIds: ['n1', 'n5'],
        status: VanStatus.active,
      ),
    ];

    // 2. Load Drivers
    // ... inside _loadMockData() ...
    crewDrivers = [
      DriverModel(
        id: 'd1',
        fullName: 'Ricardo Dalisay',
        contactNumber: '0917-123-4567',
        professionalLicenseNo: 'N01-12-345678',
        licenseExpiryDate: DateTime.now().add(const Duration(days: 365 * 2)),
        cttmoIdNo: 'CTTMO-2025-0142',
        status: DriverStatus.active,
        cttmoIdPhotoUrl:
            'https://via.placeholder.com/300x200.png?text=CTTMO+ID', // Mock ID photo
      ),
      DriverModel(
        id: 'd2',
        fullName: 'Juan Luna',
        contactNumber: '0918-987-6543',
        professionalLicenseNo: 'K02-98-765432',
        licenseExpiryDate: DateTime.now().add(const Duration(days: 120)),
        cttmoIdNo: 'CTTMO-2024-8891',
        status: DriverStatus.active,
        // d2 has no photo uploaded yet to test the empty state
      ),
    ];

    notifyListeners();
  }
}
