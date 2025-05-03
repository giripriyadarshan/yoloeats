import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';
import '../data/local/user_profile_local_data_source.dart';
import '../data/repositories/user_profile_repository.dart';
import 'api_service_providers.dart';
import '../models/allergen_info.dart';

final userProfileLocalDataSourceProvider = Provider<UserProfileLocalDataSource>(
      (ref) => UserProfileLocalDataSource(),
);

final userProfileRepositoryProvider = Provider<UserProfileRepository>(
      (ref) {
    final localDataSource = ref.watch(userProfileLocalDataSourceProvider);
    final apiService = ref.watch(userProfileApiServiceProvider);
    return UserProfileRepositoryImpl(localDataSource, apiService);
  },
);


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
    state = AsyncValue.data(profile);

    try {
      await _repository.saveUserProfile(profile);
    } catch (e, s) {
      print('Error saving profile (propagated from repository): $e');
      state = previousState;
    }
  }

  Future<void> deleteProfile() async {
    final previousState = state;
    state = const AsyncValue.loading();
    try {
      await _repository.deleteUserProfile();
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

final userProfileProvider =
StateNotifierProvider<UserProfileNotifier, AsyncValue<UserProfile?>>((ref) {
  final repository = ref.watch(userProfileRepositoryProvider);
  return UserProfileNotifier(repository);
});

final allergensProvider = FutureProvider<List<AllergenInfo>>((ref) async {
  final repository = ref.watch(userProfileRepositoryProvider);
  return repository.getAllergens();
});