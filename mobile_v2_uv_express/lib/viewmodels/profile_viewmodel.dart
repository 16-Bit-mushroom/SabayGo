import 'package:flutter/material.dart';
import 'package:mobile_v2_uv_express/models/passenger_moderl.dart';
import 'package:mobile_v2_uv_express/models/transit_node_model.dart';

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel() {
    _loadMockProfile();
  }

  late PassengerModel currentUser;

  // --- Notification Preferences State ---
  bool pushEnabled = true;
  bool promoNotifs = true;
  bool tripUpdates = true;
  bool tailoredSchedules = true;

  List<TransitNodeModel> savedDestinations = [];

  void _loadMockProfile() {
    currentUser = PassengerModel(
      id: 'p-8839',
      fullName: 'Sarah K. Dela Cruz',
      email: 'sarah.k@umindanao.edu.ph',
      phoneNumber: '+63 917 123 4567',
      address: 'Matina Crossing, Davao City',
      gender: 'Female',
      emergencyContactName: 'Maria Dela Cruz (Mother)',
      emergencyContactPhone: '+63 918 987 6543',
      trustRating: 4.9,
      avatarUrl: 'https://i.pravatar.cc/150?img=47', // Mock avatar
    );

    savedDestinations = [
      const TransitNodeModel(
        id: 'n2',
        name: 'Cotabato City Terminal',
        area: 'Cotabato City',
      ),
      const TransitNodeModel(
        id: 'n5',
        name: 'Tagum City Terminal',
        area: 'Tagum City',
      ),
    ];
  }

  // --- Actions ---
  void toggleAllNotifications(bool value) {
    pushEnabled = value;
    if (!value) {
      promoNotifs = false;
      tripUpdates = false;
      tailoredSchedules = false;
    } else {
      promoNotifs = true;
      tripUpdates = true;
      tailoredSchedules = true;
    }
    notifyListeners();
  }

  void toggleSpecificNotification(String type, bool value) {
    if (type == 'promo') promoNotifs = value;
    if (type == 'updates') tripUpdates = value;
    if (type == 'tailored') tailoredSchedules = value;

    // Auto-toggle master switch if all are turned off manually
    if (!promoNotifs && !tripUpdates && !tailoredSchedules) {
      pushEnabled = false;
    } else if (value) {
      pushEnabled = true;
    }
    notifyListeners();
  }

  void signOut() {
    // TODO: Clear auth token and route to Login Screen
  }
}
