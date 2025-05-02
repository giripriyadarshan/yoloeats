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
  high,
}

@HiveType(typeId: 0)
class UserProfile extends HiveObject
    with EquatableMixin {
  @HiveField(0)
  final String? userId;

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
    this.userId,
    this.username,
    this.email,
    List<String>? allergens,
    List<String>? dietaryPrefs,
    this.riskTolerance = RiskLevel.medium,
  })
      : allergens = allergens ?? [],
        dietaryPrefs = dietaryPrefs ?? [];

  @override
  List<Object?> get props =>
      [
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
    bool userIdChanged = userId != null && this.userId != userId;

    return UserProfile(
      userId: userIdChanged ? userId : (userId ?? this.userId),
      username: username ?? this.username,
      email: email ?? this.email,
      allergens: allergens ?? this.allergens,
      dietaryPrefs: dietaryPrefs ?? this.dietaryPrefs,
      riskTolerance: riskTolerance ?? this.riskTolerance,
    );
  }
}