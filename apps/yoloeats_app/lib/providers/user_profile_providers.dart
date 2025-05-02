// File: lib/providers/user_profile_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_profile.dart';
import '../data/local/user_profile_local_data_source.dart';
import '../data/remote/user_profile_api_service.dart'; // Import API Service
import '../data/repositories/user_profile_repository.dart';
import 'api_service_providers.dart'; // Import API Service Provider file

// Provider for the Local Data Source (remains the same)
final userProfileLocalDataSourceProvider = Provider<UserProfileLocalDataSource>(
      (ref) => UserProfileLocalDataSource(),
);

// Provider for the Repository Implementation (UPDATED)
// Now depends on both local data source and API service providers
final userProfileRepositoryProvider = Provider<UserProfileRepository>(
      (ref) {
    final localDataSource = ref.watch(userProfileLocalDataSourceProvider);
    // --- FIX: Watch and inject the API service provider ---
    final apiService = ref.watch(userProfileApiServiceProvider);
    return UserProfileRepositoryImpl(localDataSource, apiService); // Pass both
  },
);


// --- State Notifier for User Profile State (remains the same) ---
// (No changes needed here as it depends on the Repository abstraction)
class UserProfileNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  final UserProfileRepository _repository;

  UserProfileNotifier(this._repository) : super(const AsyncValue.loading()) {
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    state = const AsyncValue.loading();
    try {
      final profile = await _repository.getUserProfile();
      state = AsyncValue.data(profile);
    } catch (e, s) {
      print('Error loading profile: $e');
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    final previousState = state;
    state = AsyncValue.data(profile); // Optimistic update

    try {
      // Repository now handles local save + async remote sync attempt
      await _repository.saveUserProfile(profile);
    } catch (e, s) {
      print('Error saving profile (propagated from repository): $e');
      state = previousState; // Revert on error (likely local save failure)
    }
  }

  Future<void> deleteProfile() async {
    final previousState = state;
    state = const AsyncValue.loading();
    try {
      await _repository.deleteUserProfile(); // Call repo method
      state = const AsyncValue.data(null);
    } catch (e, s) {
      print('Error deleting profile: $e');
      state = previousState;
    }
  }

  Future<void> refreshProfile() async {
    await _loadProfile();
  }
}

// --- StateNotifierProvider (remains the same) ---
final userProfileProvider =
StateNotifierProvider<UserProfileNotifier, AsyncValue<UserProfile?>>((ref) {
  final repository = ref.watch(userProfileRepositoryProvider);
  return UserProfileNotifier(repository);
});