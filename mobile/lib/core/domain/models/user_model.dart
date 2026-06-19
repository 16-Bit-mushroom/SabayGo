class UserModel {
  final String id;
  final String firstName;
  final String lastName;
  final String? middleName;
  final String email;
  final String phoneNumber;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String accountType;
  final String subscriptionTier;
  final double rating;
  final String joinDate;
  final int totalTrips;
  final String co2Saved;
  final int availableVouchers;

  UserModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.middleName,
    required this.email,
    required this.phoneNumber,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.accountType,
    required this.subscriptionTier,
    required this.rating,
    required this.joinDate,
    required this.totalTrips,
    required this.co2Saved,
    required this.availableVouchers,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'],
      firstName: map['firstName'],
      lastName: map['lastName'],
      middleName: map['middleName'],
      email: map['email'],
      phoneNumber: map['phoneNumber'],
      emergencyContactName: map['emergencyContactName'],
      emergencyContactPhone: map['emergencyContactPhone'],
      accountType: map['accountType'],
      subscriptionTier: map['subscriptionTier'],
      rating: map['rating'],
      joinDate: map['joinDate'],
      totalTrips: map['totalTrips'],
      co2Saved: map['co2Saved'],
      availableVouchers: map['availableVouchers'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'middleName': middleName,
      'email': email,
      'phoneNumber': phoneNumber,
      'emergencyContactName': emergencyContactName,
      'emergencyContactPhone': emergencyContactPhone,
      'accountType': accountType,
      'subscriptionTier': subscriptionTier,
      'rating': rating,
      'joinDate': joinDate,
      'totalTrips': totalTrips,
      'co2Saved': co2Saved,
      'availableVouchers': availableVouchers,
    };
  }

  String get fullName => "$firstName ${middleName != null ? '$middleName ' : ''}$lastName".trim();
}