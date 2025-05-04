import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/check_result.dart';
import 'repository_providers.dart';
import 'user_profile_providers.dart';

final allergyCheckProvider = FutureProvider.autoDispose
    .family<CheckResult, String>((ref, productIdentifier) async {
  final allergyRepository = ref.watch(allergyRepositoryProvider);

  final userProfileState = ref.watch(userProfileProvider);

  final String? userId = userProfileState.whenOrNull(data: (profile) => profile?.userId);

  if (userId == null) {
    print("Allergy Check Provider: Cannot perform check, user ID not available.");
    return CheckResult(
      status: SafetyStatus.error,
      isOfflineResult: false, // Or true? Doesn't really matter here
      errorMessage: "User profile not available.",
    );
  }

  print("Allergy Check Provider: Checking safety for user '$userId', product '$productIdentifier'");
  final result = await allergyRepository.checkProductSafety(
    productIdentifier: productIdentifier,
    userId: userId,
  );
  print("Allergy Check Provider: Check completed with status ${result.status}");
  return result;
});