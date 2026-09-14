import '../../core/network/api_client.dart';

/// A configurable cooperative policy row -- reschedule cutoff, advance
/// booking cap, geofence radius, hold TTL, variance threshold, and so on.
///
/// Existing trips are unaffected by an edit here: policy values are
/// snapshotted onto each trip at generation time, so a change here only
/// governs trips generated from this point forward.
class Policy {
  const Policy({
    required this.policyKey,
    required this.policyValue,
    required this.dataType,
    required this.description,
    required this.updatedAt,
  });

  final String policyKey;
  final String policyValue;
  final String dataType; // int | decimal | bool | string
  final String description;
  final DateTime updatedAt;

  factory Policy.fromJson(Map<String, dynamic> json) => Policy(
        policyKey: json['policy_key'] as String,
        policyValue: json['policy_value'] as String,
        dataType: json['data_type'] as String,
        description: json['description'] as String,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

class PolicyRepository {
  PolicyRepository(this._api);
  final ApiClient _api;

  Future<List<Policy>> list() async {
    final json = await _api.get('/config/policies');
    return (json as List).map((e) => Policy.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Policy> update(String policyKey, String value) async {
    final json = await _api.put('/config/policies/$policyKey', body: {
      'policy_value': value,
    });
    return Policy.fromJson(json as Map<String, dynamic>);
  }
}
