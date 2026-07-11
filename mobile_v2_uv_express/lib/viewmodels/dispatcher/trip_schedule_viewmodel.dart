import 'package:flutter/material.dart';
import '../../models/van_model.dart';
import '../../models/uv_trip_model.dart';
import '../../models/transit_node_model.dart';

class TripScheduleViewModel extends ChangeNotifier {
  TripScheduleViewModel() {
    _loadMockData();
  }

  List<VanModel> fleetVans = [];
  List<UvTripModel> postedSchedules = [];

  // --- Core Compliance Logic ---
  // Only returns vans that are active AND registered for BOTH the origin and destination
  List<VanModel> getAvailableVansForRoute(String originId, String destinationId) {
    return fleetVans.where((van) {
      final isRegistered = van.registeredRouteNodeIds.contains(originId) && 
                           van.registeredRouteNodeIds.contains(destinationId);
      return isRegistered && van.status == VanStatus.active;
    }).toList();
  }

  void _loadMockData() {
    // Note: Node IDs must match your TransitNodeModel IDs (n1=Davao, n2=Cotabato, n5=Tagum)
    fleetVans = [
      VanModel(
        id: 'v1',
        plateNumber: 'ABC-1234',
        registeredRouteNodeIds: ['n1', 'n2'], // Davao <-> Cotabato ONLY
        status: VanStatus.active,
      ),
      VanModel(
        id: 'v2',
        plateNumber: 'XYZ-9876',
        registeredRouteNodeIds: ['n1', 'n5'], // Davao <-> Tagum ONLY
        status: VanStatus.active,
      ),
      VanModel(
        id: 'v3',
        plateNumber: 'DEF-5678',
        registeredRouteNodeIds: ['n1', 'n2', 'n5'], // Multi-stop franchise
        status: VanStatus.maintenance,
      ),
    ];

    // We will populate postedSchedules when we build the "Create Schedule" form
    notifyListeners();
  }
}