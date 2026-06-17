import 'package:flutter/material.dart';

// 1. The Domain Entity (Matches your backend JSON structure)
class UserProfile {
  final String fullName;
  final String accountType;
  final String subscriptionTier;
  final double rating;
  final String joinDate;
  final int totalTrips;
  final String co2Saved;
  final int availableVouchers;

  UserProfile({
    required this.fullName,
    required this.accountType,
    required this.subscriptionTier,
    required this.rating,
    required this.joinDate,
    required this.totalTrips,
    required this.co2Saved,
    required this.availableVouchers,
  });
}

// 2. The ViewModel
class ProfileViewModel extends ChangeNotifier {
  bool isLoading = false;
  UserProfile? currentUser;

  ProfileViewModel() {
    _loadMockProfile();
  }

  // When your Python backend is ready, you swap this out for an HTTP GET request!
  Future<void> _loadMockProfile() async {
    isLoading = true;
    notifyListeners();

    // Simulating network delay
    await Future.delayed(const Duration(milliseconds: 800));

    currentUser = UserProfile(
      fullName: "Alex Johnson",
      accountType: "Passenger",
      subscriptionTier: "Free Plan",
      rating: 4.9,
      joinDate: "Jan 2024",
      totalTrips: 47,
      co2Saved: "18 kg",
      availableVouchers: 3,
    );

    isLoading = false;
    notifyListeners();
  }

  void signOut() {
    // Handle token clearing and state reset here
    debugPrint("Signing out...");
  }
}