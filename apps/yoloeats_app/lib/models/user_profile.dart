import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';

part 'user_profile.g.dart';

@HiveType(typeId: 1)
enum RiskLevel {
  @HiveField(0)
  low,
  @HiveField(1)
  medium,
  @HiveField(2)
  high;

  /// Converts enum to lowercase string for JSON/API communication.
  String toJson() => name;

  /// Creates enum from lowercase string (case-insensitive).
  static RiskLevel fromJson(String? json) {
    if (json == null) return RiskLevel.medium;
    switch (json.toLowerCase()) {
      case 'low':
        return RiskLevel.low;
      case 'high':
        return RiskLevel.high;
      case 'medium':
      default:
        return RiskLevel.medium;
    }
  }
}

@HiveType(typeId: 0)
class UserProfile extends HiveObject with EquatableMixin {
  @HiveField(0)
  final String userId;

  @HiveField(1)
  final String? username;

  @HiveField(2)
  final String? email;

  @HiveField(3)
  final List<String> allergens;

  @HiveField(4)
  final List<String> dietaryPrefs;

  @HiveField(5)
  final RiskLevel riskTolerance;

  UserProfile({
    required this.userId,
    this.username,
    this.email,
    List<String>? allergens,
    List<String>? dietaryPrefs,
    this.riskTolerance = RiskLevel.medium,
  })  : allergens = allergens ?? [],
        dietaryPrefs = dietaryPrefs ?? [];

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    if (json['user_id'] == null) {
      throw FormatException("Missing required field 'user_id' in UserProfile JSON");
    }

    return UserProfile(
      userId: json['user_id'] as String,
      username: json['username'] as String?,
      email: json['email'] as String?,
      allergens: json['allergens'] == null
          ? []
          : List<String>.from(json['allergens'] as List),
      dietaryPrefs: json['dietary_prefs'] == null
          ? []
          : List<String>.from(json['dietary_prefs'] as List),
      riskTolerance: RiskLevel.fromJson(json['risk_tolerance'] as String?),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      if (username != null) 'username': username,
      if (email != null) 'email': email,
      'allergens': allergens,
      'dietary_prefs': dietaryPrefs,
      'risk_tolerance': riskTolerance.toJson(),
    };
  }


  @override
  List<Object?> get props => [
    userId,
    username,
    email,
    allergens,
    dietaryPrefs,
    riskTolerance,
  ];

  UserProfile copyWith({
    String? userId,
    String? username,
    String? email,
    List<String>? allergens,
    List<String>? dietaryPrefs,
    RiskLevel? riskTolerance,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      email: email ?? this.email,
      allergens: allergens ?? this.allergens,
      dietaryPrefs: dietaryPrefs ?? this.dietaryPrefs,
      riskTolerance: riskTolerance ?? this.riskTolerance,
    );
  }
}