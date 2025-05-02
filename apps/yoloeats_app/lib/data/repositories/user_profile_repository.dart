import '../../models/user_profile.dart';
import '../local/user_profile_local_data_source.dart';
import '../remote/user_profile_api_service.dart';

abstract class UserProfileRepository {
  Future<UserProfile?> getUserProfile();
  Future<void> saveUserProfile(UserProfile profile);
  Future<void> deleteUserProfile();
}

class UserProfileRepositoryImpl implements UserProfileRepository {
  final UserProfileLocalDataSource _localDataSource;
  final UserProfileApiService _apiService; // Add API service dependency

  UserProfileRepositoryImpl(this._localDataSource, this._apiService);

  @override
  Future<UserProfile?> getUserProfile() async {
    print("Repository: Getting user profile...");
    try {
      // 1. Try local cache first (synchronous call)
      final localProfile = _localDataSource.getUserProfile();
      if (localProfile != null) {
        print("Repository: Profile loaded from Hive cache.");
        return localProfile;
      }

      // 2. If no local data, fetch from API (asynchronous call)
      print("Repository: No local profile found, fetching from API...");
      final apiProfile = await _apiService.fetchProfile();

      // 3. If API fetch succeeds, save to local cache and return
      if (apiProfile != null) {
        print("Repository: Profile fetched from API, saving to Hive.");
        await _localDataSource.saveUserProfile(apiProfile);
        return apiProfile;
      } else {
        print("Repository: API returned no profile (404 or null).");
        return null;
      }
    } catch (e) {
      print("Repository: Error in getUserProfile: $e");
      // Fallback: Attempt to return stale local data on API error
      try {
        final localProfile = _localDataSource.getUserProfile();
        if (localProfile != null) {
          print("Repository: API failed, returning potentially stale profile from Hive.");
          return localProfile; // Return local data if API fails
        }
      } catch (localError) {
        print("Repository: Error fetching from local cache during API failure fallback: $localError");
      }
      // If API failed AND local fetch failed (or was null initially), indicate failure
      return null;
    }
  }

  @override
  Future<void> saveUserProfile(UserProfile profile) async {
    print("Repository: Saving user profile...");
    try {
      // 1. Save locally immediately for responsiveness
      await _localDataSource.saveUserProfile(profile);
      print("Repository: Profile saved locally to Hive.");

      // 2. Attempt to save to backend asynchronously
      _apiService.saveProfile(profile).then((updatedProfileFromApi) {
        print("Repository: Profile successfully synced with backend.");
        print("Repository: Updating local cache with synced data from backend.");
        _localDataSource.saveUserProfile(updatedProfileFromApi).catchError((localUpdateError) {
          print("Repository: Error updating local cache after successful API sync: $localUpdateError");
        });
      }).catchError((error) {
        print("Repository: Failed to sync profile with backend: $error");
        // TODO: Implement offline queueing mechanism here for robust sync.
      });
    } catch (e) {
      print("Repository: Error saving profile locally: $e");
      rethrow;
    }
  }

  @override
  Future<void> deleteUserProfile() async {
    print("Repository: Deleting user profile...");
    try {
      // 1. Delete locally first
      await _localDataSource.deleteUserProfile();
      print("Repository: Profile deleted locally from Hive.");

      // 2. Attempt to delete from backend asynchronously
      // TODO: Implement _apiService.deleteProfile() if backend supports it
      // _apiService.deleteProfile(profile.userId).then((_) { // Assuming userId is needed
      //    print("Repository: Profile successfully deleted on backend.");
      // }).catchError((error) {
      //    print("Repository: Failed to delete profile on backend: $error");
      //    // TODO: Implement offline queueing for deletion? Or just log?
      // });

    } catch (e) {
      print("Repository: Error deleting profile locally: $e");
      rethrow;
    }
  }
}