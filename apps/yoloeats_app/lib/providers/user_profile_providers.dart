import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';
import '../data/local/user_profile_local_data_source.dart';
import '../data/repositories/user_profile_repository.dart';
import 'api_service_providers.dart';
import '../models/allergen_info.dart';
import 'auth_providers.dart';

final userProfileLocalDataSourceProvider = Provider<UserProfileLocalDataSource>(
      (ref) => UserProfileLocalDataSource(),
);

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  final localDataSource = ref.watch(userProfileLocalDataSourceProvider);
  final apiService = ref.watch(userProfileApiServiceProvider);
  return UserProfileRepositoryImpl(localDataSource, apiService, ref);
});


class UserProfileNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  final UserProfileRepository _repository;
  final Ref _ref;

  bool _initialLoadAttempted = false;

  UserProfileNotifier(this._repository, this._ref) : super(const AsyncValue.loading()) {
    Future.microtask(_loadProfile);
  }

  Future<void> _loadProfile() async {
    if (state is AsyncLoading && _initialLoadAttempted) return;

    state = const AsyncValue.loading();
    _initialLoadAttempted = true;

    final userId = _ref.read(currentUserIdProvider);
    if (userId == null || userId.isEmpty) {
      print("UserProfileNotifier: Cannot load profile. User ID is null or empty.");
      state = const AsyncValue.data(null);
      return;
    }
    print("UserProfileNotifier: Loading profile for userId: $userId");

    try {
      final profile = await _repository.getUserProfile();

      if (mounted) {
        if (profile != null) {
          if (profile.userId == userId) {
            state = AsyncValue.data(profile);
            print("UserProfileNotifier: Profile loaded successfully for user ${profile.userId}");
          } else {
            print("UserProfileNotifier: Loaded profile's userId (${profile.userId}) does not match current userId ($userId). Setting state to null.");
            state = const AsyncValue.data(null);
            await _repository.deleteUserProfile();
          }
        } else {
          print("UserProfileNotifier: No profile found for userId $userId (repository returned null).");
          state = const AsyncValue.data(null);
        }
      }
    } catch (e, s) {
      print('UserProfileNotifier: Error loading profile for userId $userId: $e\n$s');
      if (mounted) {
        state = AsyncValue.error(e, s);
      }
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    final currentAppUserId = _ref.read(currentUserIdProvider);
    if (currentAppUserId == null || currentAppUserId.isEmpty) {
      print("UserProfileNotifier Error: Cannot save profile. User ID is null or empty.");
      state = AsyncValue.error(
        "Cannot save profile: No user identified.",
        StackTrace.current,
      );
      return;
    }

    final profileToSave = profile.copyWith(userId: currentAppUserId);
    print("UserProfileNotifier: Preparing to save profile for userId ${profileToSave.userId}. Data: ${profileToSave.username}, Allergens: ${profileToSave.allergens.length}");


    final previousState = state;
    state = AsyncValue.data(profileToSave);
    print("UserProfileNotifier: Optimistically updated state for userId ${profileToSave.userId}");

    try {
      await _repository.saveUserProfile(profileToSave);
      print("UserProfileNotifier: saveUserProfile call to repository completed for userId ${profileToSave.userId}.");
    } catch (e, s) {
      print('UserProfileNotifier: Error saving profile for userId ${profileToSave.userId}: $e\n$s');
      if (mounted) {
        state = previousState;
      }
    }
  }

  Future<void> deleteProfile() async {
    final userId = _ref.read(currentUserIdProvider);
    print("UserProfileNotifier: Attempting to delete profile for current userId: $userId");


    final previousState = state;
    state = const AsyncValue.loading();
    try {
      await _repository.deleteUserProfile();
      if (mounted) {
        state = const AsyncValue.data(null);
        print("UserProfileNotifier: Profile deleted.");
      }
    } catch (e, s) {
      print('UserProfileNotifier: Error deleting profile: $e\n$s');
      if (mounted) {
        state = previousState;
      }
    }
  }

  Future<void> refreshProfile() async {
    print("UserProfileNotifier: Refresh triggered.");
    _initialLoadAttempted = false;
    await _loadProfile();
  }
}

final userProfileProvider =
StateNotifierProvider<UserProfileNotifier, AsyncValue<UserProfile?>>((ref) {
  final repository = ref.watch(userProfileRepositoryProvider);
  return UserProfileNotifier(repository, ref);
});

final allergensProvider = FutureProvider<List<AllergenInfo>>((ref) async {
  final repository = ref.watch(userProfileRepositoryProvider);
  return repository.getAllergens();
});