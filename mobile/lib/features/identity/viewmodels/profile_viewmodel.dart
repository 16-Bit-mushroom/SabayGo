import 'package:flutter/material.dart';
import '../../../core/domain/models/user_model.dart';
import '../../../core/data/repositories/user_repository.dart';

class ProfileViewModel extends ChangeNotifier {
  // 1. The Interface Contract
  final IUserRepository repository;
  
  UserModel? _currentUser;
  bool _isLoading = false;

  // 2. The Constructor (Notice the 'required this.repository' to fix main.dart)
  ProfileViewModel({required this.repository}) {
    _loadInitialUser();
  }

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;

  // Read: Fetch the seed data (or newly created user) from SQLite
  Future<void> _loadInitialUser() async {
    _isLoading = true;
    notifyListeners();

    // Pulling the mock user we seeded in database_helper.dart
    _currentUser = await repository.getUser('user_001'); 
    
    _isLoading = false;
    notifyListeners();
  }

  // Create: For the Sign Up Screen
  Future<void> registerUser(UserModel newUser) async {
    _isLoading = true;
    notifyListeners();

    await repository.createUser(newUser);
    _currentUser = newUser;
    
    _isLoading = false;
    notifyListeners();
  }

  // Update: For the Edit Profile Screen
  Future<void> saveProfileUpdates(Map<String, dynamic> updatedData) async {
    if (_currentUser == null) return;
    
    _isLoading = true;
    notifyListeners();

    final updatedUser = UserModel(
      id: _currentUser!.id,
      firstName: updatedData['firstName'],
      lastName: updatedData['lastName'],
      middleName: _currentUser!.middleName,
      email: updatedData['email'],
      phoneNumber: updatedData['phoneNumber'],
      emergencyContactName: updatedData['emergencyContactName'],
      emergencyContactPhone: updatedData['emergencyContactPhone'],
      accountType: _currentUser!.accountType,
      subscriptionTier: _currentUser!.subscriptionTier,
      rating: _currentUser!.rating,
      joinDate: _currentUser!.joinDate,
      totalTrips: _currentUser!.totalTrips,
      co2Saved: _currentUser!.co2Saved,
      availableVouchers: _currentUser!.availableVouchers,
    );

    await repository.updateUser(updatedUser);
    _currentUser = updatedUser;
    
    _isLoading = false;
    notifyListeners();
  }

  void signOut() {
    _currentUser = null;
    notifyListeners();
  }
}