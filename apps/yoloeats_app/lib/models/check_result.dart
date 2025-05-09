import 'package:flutter/foundation.dart' show listEquals;
import 'package:equatable/equatable.dart';

enum SafetyStatus {
  safe,
  unsafe,
  caution,
  offline,
  error;

  /// Converts enum to lowercase string for JSON/API communication.
  String toJson() => name;

  /// Creates enum from lowercase string (case-insensitive).
  static SafetyStatus fromJson(String? json) {
    if (json == null) return SafetyStatus.error;
    switch (json.toLowerCase()) {
      case 'safe':
        return SafetyStatus.safe;
      case 'unsafe':
        return SafetyStatus.unsafe;
      case 'caution':
        return SafetyStatus.caution;
      case 'offline':
        return SafetyStatus.offline;
      case 'error':
      default:
        return SafetyStatus.error;
    }
  }
}

// Class holding the result of a safety check
class CheckResult extends Equatable {
  final SafetyStatus status;
  final List<String> conflictingAllergens;
  final List<String> conflictingDiets;
  final List<String> traceAllergens;
  final bool isOfflineResult;
  final String? errorMessage;

  const CheckResult({
    required this.status,
    List<String>? conflictingAllergens,
    List<String>? conflictingDiets,
    List<String>? traceAllergens,
    required this.isOfflineResult,
    this.errorMessage,
  })  : conflictingAllergens = conflictingAllergens ?? const [],
        conflictingDiets = conflictingDiets ?? const [],
        traceAllergens = traceAllergens ?? const [];

  factory CheckResult.fromJson(Map<String, dynamic> json) {
    return CheckResult(
      status: SafetyStatus.fromJson(json['status'] as String?),
      conflictingAllergens: (json['conflictingAllergens'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
          [],
      conflictingDiets: (json['conflictingDiets'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
          [],
      traceAllergens: (json['traceAllergens'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
          [],
      isOfflineResult: json['isOfflineResult'] as bool? ?? false,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.toJson(),
      'conflictingAllergens': conflictingAllergens,
      'conflictingDiets': conflictingDiets,
      'traceAllergens': traceAllergens,
      'isOfflineResult': isOfflineResult,
      if (errorMessage != null) 'errorMessage': errorMessage,
    };
  }

  @override
  List<Object?> get props => [
    status,
    conflictingAllergens,
    conflictingDiets,
    traceAllergens,
    isOfflineResult,
    errorMessage,
  ];
  
  @override
  bool? get stringify => true;
}