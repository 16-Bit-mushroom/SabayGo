import '../../core/network/api_client.dart';
import '../../models/passenger_moderl.dart';
import '../../models/saved_destination_model.dart';

class NotificationSettings {
  const NotificationSettings({
    required this.pushEnabled,
    required this.tripUpdates,
    required this.tailoredSchedules,
  });

  final bool pushEnabled;
  final bool tripUpdates;
  final bool tailoredSchedules;

  factory NotificationSettings.fromApi(Map<String, dynamic> j) =>
      NotificationSettings(
        pushEnabled: j['push_enabled'] as bool,
        tripUpdates: j['trip_updates'] as bool,
        tailoredSchedules: j['tailored_schedules'] as bool,
      );
}

class ProfileRepository {
  ProfileRepository(this._api);
  final ApiClient _api;

  Future<PassengerModel> me() async {
    final json = await _api.get('/auth/me');
    return PassengerModel.fromApi(json as Map<String, dynamic>);
  }

  /// Any field left null is unchanged server-side. Only send
  /// [currentPassword]/[newPassword] together, to change the password.
  Future<PassengerModel> updateProfile({
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? homeAddress,
    String? emergencyContactName,
    String? emergencyContactRelation,
    String? emergencyContactNumber,
    String? currentPassword,
    String? newPassword,
  }) async {
    final json = await _api.patch('/auth/me', body: {
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (homeAddress != null) 'home_address': homeAddress,
      if (emergencyContactName != null)
        'emergency_contact_name': emergencyContactName,
      if (emergencyContactRelation != null)
        'emergency_contact_relation': emergencyContactRelation,
      if (emergencyContactNumber != null)
        'emergency_contact_number': emergencyContactNumber,
      if (currentPassword != null) 'current_password': currentPassword,
      if (newPassword != null) 'new_password': newPassword,
    });
    return PassengerModel.fromApi(json as Map<String, dynamic>);
  }

  Future<void> closeAccount(String password) =>
      _api.post('/auth/me/close', body: {'password': password});

  Future<NotificationSettings> settings() async {
    final json = await _api.get('/users/me/settings');
    return NotificationSettings.fromApi(json as Map<String, dynamic>);
  }

  Future<NotificationSettings> updateSettings({
    bool? pushEnabled,
    bool? tripUpdates,
    bool? tailoredSchedules,
  }) async {
    final json = await _api.patch('/users/me/settings', body: {
      if (pushEnabled != null) 'push_enabled': pushEnabled,
      if (tripUpdates != null) 'trip_updates': tripUpdates,
      if (tailoredSchedules != null) 'tailored_schedules': tailoredSchedules,
    });
    return NotificationSettings.fromApi(json as Map<String, dynamic>);
  }

  Future<List<SavedDestinationModel>> savedDestinations() async {
    final json = await _api.get('/users/me/saved-destinations') as List;
    return json
        .map((e) => SavedDestinationModel.fromApi(e as Map<String, dynamic>))
        .toList();
  }

  Future<SavedDestinationModel> addSavedDestination({
    required String label,
    String? address,
  }) async {
    final json = await _api.post('/users/me/saved-destinations', body: {
      'label': label,
      if (address != null && address.isNotEmpty) 'address': address,
    });
    return SavedDestinationModel.fromApi(json as Map<String, dynamic>);
  }

  Future<void> deleteSavedDestination(String destinationId) =>
      _api.delete('/users/me/saved-destinations/$destinationId');
}
