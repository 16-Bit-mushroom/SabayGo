import 'package:flutter/material.dart';

import '../core/network/api_exception.dart';
import '../data/repositories/profile_repository.dart';
import '../models/passenger_moderl.dart';
import '../models/saved_destination_model.dart';

class ProfileViewModel extends ChangeNotifier {
  ProfileViewModel(this._repo);
  final ProfileRepository _repo;

  PassengerModel? currentUser;
  bool pushEnabled = true;
  bool tripUpdates = true;
  bool tailoredSchedules = true;
  List<SavedDestinationModel> savedDestinations = [];

  bool isLoading = false;
  String? error;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repo.me(),
        _repo.settings(),
        _repo.savedDestinations(),
      ]);
      currentUser = results[0] as PassengerModel;
      final settings = results[1] as NotificationSettings;
      pushEnabled = settings.pushEnabled;
      tripUpdates = settings.tripUpdates;
      tailoredSchedules = settings.tailoredSchedules;
      savedDestinations = results[2] as List<SavedDestinationModel>;
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Returns null on success, or a message to show on failure.
  Future<String?> updateProfile({
    required String firstName,
    required String lastName,
    String? phoneNumber,
    String? homeAddress,
    String? emergencyContactName,
    String? emergencyContactRelation,
    String? emergencyContactNumber,
    String? currentPassword,
    String? newPassword,
  }) async {
    try {
      currentUser = await _repo.updateProfile(
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
        homeAddress: homeAddress,
        emergencyContactName: emergencyContactName,
        emergencyContactRelation: emergencyContactRelation,
        emergencyContactNumber: emergencyContactNumber,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Returns null on success, or a message to show on failure.
  Future<String?> closeAccount(String password) async {
    try {
      await _repo.closeAccount(password);
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<void> toggleAllNotifications(bool value) async {
    final prior = (pushEnabled, tripUpdates, tailoredSchedules);
    pushEnabled = value;
    tripUpdates = value;
    tailoredSchedules = value;
    notifyListeners();
    try {
      await _repo.updateSettings(
        pushEnabled: value,
        tripUpdates: value,
        tailoredSchedules: value,
      );
    } on ApiException {
      pushEnabled = prior.$1;
      tripUpdates = prior.$2;
      tailoredSchedules = prior.$3;
      notifyListeners();
    }
  }

  Future<void> toggleSpecificNotification(String type, bool value) async {
    final prior = (pushEnabled, tripUpdates, tailoredSchedules);
    if (type == 'updates') tripUpdates = value;
    if (type == 'tailored') tailoredSchedules = value;
    if (!tripUpdates && !tailoredSchedules) {
      pushEnabled = false;
    } else if (value) {
      pushEnabled = true;
    }
    notifyListeners();
    try {
      await _repo.updateSettings(
        pushEnabled: pushEnabled,
        tripUpdates: tripUpdates,
        tailoredSchedules: tailoredSchedules,
      );
    } on ApiException {
      pushEnabled = prior.$1;
      tripUpdates = prior.$2;
      tailoredSchedules = prior.$3;
      notifyListeners();
    }
  }

  Future<String?> addSavedDestination({
    required String label,
    String? address,
  }) async {
    try {
      final created =
          await _repo.addSavedDestination(label: label, address: address);
      savedDestinations = [...savedDestinations, created];
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> removeSavedDestination(String destinationId) async {
    final prior = savedDestinations;
    savedDestinations =
        prior.where((d) => d.id != destinationId).toList();
    notifyListeners();
    try {
      await _repo.deleteSavedDestination(destinationId);
      return null;
    } on ApiException catch (e) {
      savedDestinations = prior;
      notifyListeners();
      return e.message;
    }
  }
}
