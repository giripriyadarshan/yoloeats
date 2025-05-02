import 'package:flutter_riverpod/flutter_riverpod.dart'; // Use flutter_riverpod

import '../models/user_profile.dart'; // Adjust import path if necessary
import '../data/local/user_profile_local_data_source.dart'; // Import local data source
import '../data/repositories/user_profile_repository.dart'; // Import repository

// Provider for the Local Data Source
final userProfileLocalDataSourceProvider = Provider<UserProfileLocalDataSource>(
      (ref) => UserProfileLocalDataSource(),
);

// Provider for the Repository Implementation
// It depends on the local data source provider
final userProfileRepositoryProvider = Provider<UserProfileRepository>(
      (ref) {
    final localDataSource = ref.watch(userProfileLocalDataSourceProvider);
    // If you add a remote data source later, watch its provider here too
    // final remoteDataSource = ref.watch(userProfileRemoteDataSourceProvider);
    return UserProfileRepositoryImpl(localDataSource /*, remoteDataSource */);
  },
);


// --- State Notifier for User Profile State ---

// Define the StateNotifier class
class UserProfileNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  final UserProfileRepository _repository;

  // Constructor: Pass repository, initialize state to loading, and load profile
  UserProfileNotifier(this._repository) : super(const AsyncValue.loading()) {
    _loadProfile(); // Load initially
  }

  // Method to load the profile from the repository
  Future<void> _loadProfile() async {
    state = const AsyncValue.loading(); // Set state to loading
    try {
      // Await the repository call
      final profile = await _repository.getUserProfile();
      // Set state to data if successful
      state = AsyncValue.data(profile);
    } catch (e, s) {
      // Set state to error if repository call fails
      print('Error loading profile: $e'); // Proper logging needed
      state = AsyncValue.error(e, s);
    }
  }

  // Method to save the profile
  Future<void> saveProfile(UserProfile profile) async {
    // Optimistic update: Update UI immediately assuming success
    final previousState = state; // Store previous state for potential revert
    state = AsyncValue.data(profile); // Update state optimistically

    try {
      // Attempt to save via repository
      await _repository.saveUserProfile(profile);
      // Optional: If save is successful, could reload or just keep optimistic state
      // Or maybe update state with profile returned from save if API returns it
    } catch (e, s) {
      // If save fails, revert state and set error
      print('Error saving profile: $e');
      state = previousState; // Revert to the state before the optimistic update
      // Optionally expose error state differently
      // state = AsyncValue.error('Failed to save profile: $e', s);
    }
  }

  // Method to delete the profile (optional)
  Future<void> deleteProfile() async {
    final previousState = state;
    state = const AsyncValue.loading(); // Indicate loading during deletion
    try {
      // Assuming repository has delete method that uses local source's delete
      if (_repository is UserProfileRepositoryImpl) { // Check if it's the impl to access delete
        await (_repository as UserProfileRepositoryImpl).deleteUserProfile();
      } else {
        throw UnimplementedError('Delete not supported by this repository type');
      }
      state = const AsyncValue.data(null); // Set state to null after deletion
    } catch (e, s) {
      print('Error deleting profile: $e');
      state = previousState; // Revert on error
      // Optionally expose error state
      // state = AsyncValue.error('Failed to delete profile: $e', s);
    }
  }

  // Method to manually refresh the profile state
  Future<void> refreshProfile() async {
    // Useful after a background sync or manual trigger
    await _loadProfile();
  }
}

// --- StateNotifierProvider ---

// Define the final provider that the UI will interact with
final userProfileProvider =
StateNotifierProvider<UserProfileNotifier, AsyncValue<UserProfile?>>((ref) {
  // Watch the repository provider
  final repository = ref.watch(userProfileRepositoryProvider);
  // Create and return the notifier instance, passing the repository
  return UserProfileNotifier(repository);
});