import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/user_profile.dart';
import '../../models/allergen_info.dart';
import '../local/user_profile_local_data_source.dart';
import '../remote/user_profile_api_service.dart';
import '../../providers/auth_providers.dart';

abstract class UserProfileRepository {
  Future<UserProfile?> getUserProfile();
  Future<void> saveUserProfile(UserProfile profile);
  Future<void> deleteUserProfile();
  Future<List<AllergenInfo>> getAllergens();
}

class UserProfileRepositoryImpl implements UserProfileRepository {
  final UserProfileLocalDataSource _localDataSource;
  final UserProfileApiService _apiService;
  final Ref _ref;

  UserProfileRepositoryImpl(this._localDataSource, this._apiService, this._ref);

  @override
  Future<UserProfile?> getUserProfile() async {
    print("Repository: Getting user profile...");

    final userId = _ref.read(currentUserIdProvider);
    if (userId == null || userId.isEmpty) {
      print("Repository Error: Cannot get user profile. User ID is null or empty.");
      return null;
    }
    print("Repository: Using userId: $userId");

    try {
      final localProfile = _localDataSource.getUserProfile();
      if (localProfile != null && localProfile.userId == userId) {
        print("Repository: Profile for userId $userId loaded from Hive cache.");
        return localProfile;
      } else if (localProfile != null && localProfile.userId != userId) {
        print("Repository: Stale profile found in cache (different userId), ignoring.");
      }

      print("Repository: No valid local profile found for userId $userId, fetching from API...");
      final apiProfile = await _apiService.fetchProfile(userId); // Pass userId here

      if (apiProfile != null) {
        print("Repository: Profile fetched from API for userId $userId, saving to Hive.");
        await _localDataSource.saveUserProfile(apiProfile);
        return apiProfile;
      } else {
        print("Repository: API returned no profile for userId $userId (404 or null).");
        if (localProfile != null) {
          await _localDataSource.deleteUserProfile();
          print("Repository: Deleted stale local profile after API returned null.");
        }
        return null;
      }
    } catch (e, stackTrace) {
      print("Repository: Error in getUserProfile for userId $userId: $e");
      print("Repository StackTrace: $stackTrace");
      try {
        final localProfile = _localDataSource.getUserProfile();
        if (localProfile != null && localProfile.userId == userId) {
          print("Repository: API failed for userId $userId, returning potentially stale profile from Hive.");
          return localProfile;
        }
      } catch (localError) {
        print("Repository: Error fetching from local cache during API failure fallback for userId $userId: $localError");
      }
      return null;
    }
  }

  @override
  Future<void> saveUserProfile(UserProfile profile) async {
    final String userId = profile.userId;
    if (userId.isEmpty) {
      print("Repository Error: Cannot save profile. Profile object has empty userId.");
      throw ArgumentError('Profile to save must have a non-empty userId');
    }
    print("Repository: Saving user profile for userId: $userId...");

    try {
      await _localDataSource.saveUserProfile(profile);
      print("Repository: Profile for userId $userId saved locally to Hive.");

      _apiService.saveProfile(userId, profile).then((updatedProfileFromApi) {
        print("Repository: Profile for userId $userId successfully synced with backend.");
        _localDataSource.saveUserProfile(updatedProfileFromApi).catchError((localUpdateError) {
          print("Repository: Error updating local cache for userId $userId after successful API sync: $localUpdateError");
        });
      }).catchError((error, stackTrace) {
        print("Repository: Failed to sync profile for userId $userId with backend: $error");
        print("Repository Save StackTrace: $stackTrace");
        // TODO: Implement offline queueing mechanism here for robust sync.
        // For now, the local save has already happened.
      });
    } catch (e, stackTrace) {
      print("Repository: Error saving profile locally for userId $userId: $e");
      print("Repository Save Local StackTrace: $stackTrace");
      rethrow;
    }
  }

  @override
  Future<void> deleteUserProfile() async {
    final userId = _ref.read(currentUserIdProvider);
    if (userId == null || userId.isEmpty) {
      print("Repository Error: Cannot delete user profile. User ID is null or empty.");
      return;
    }
    print("Repository: Deleting user profile for userId: $userId...");

    try {
      await _localDataSource.deleteUserProfile();
      print("Repository: Profile deleted locally from Hive for key 'currentUser'.");

      // TODO: Implement _apiService.deleteProfile(userId)

    } catch (e, stackTrace) {
      print("Repository: Error deleting profile locally for userId $userId: $e");
      print("Repository Delete StackTrace: $stackTrace");
      rethrow;
    }
  }

  @override
  Future<List<AllergenInfo>> getAllergens() async {
    print("Repository: Getting global allergens list...");
    try {
      final localAllergens = _localDataSource.getAllergens();
      if (localAllergens.isNotEmpty) {
        print("Repository: Allergens loaded from Hive cache.");
        // TODO: Add staleness check? Fetch in background?
        return localAllergens;
      }

      print("Repository: No local allergens found, fetching from API...");
      final apiAllergens = await _apiService.fetchAllergens();

      if (apiAllergens.isNotEmpty) {
        print("Repository: Allergens fetched from API, saving to Hive.");
        _localDataSource.saveAllergens(apiAllergens).catchError((e) {
          print("Repository: Error saving allergens locally after API fetch: $e");
        });
      }
      return apiAllergens;

    } catch (e, stackTrace) {
      print("Repository: Error in getAllergens: $e");
      print("Repository Allergens StackTrace: $stackTrace");
      try {
        final localAllergens = _localDataSource.getAllergens();
        if (localAllergens.isNotEmpty) {
          print("Repository: API failed for allergens, returning potentially stale list from Hive.");
          return localAllergens;
        }
      } catch (localError) {
        print("Repository: Error fetching local allergens during API fallback: $localError");
      }
      return [];
    }
  }
}