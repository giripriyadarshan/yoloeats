import '../../models/user_profile.dart';
import '../local/user_profile_local_data_source.dart';

abstract class UserProfileRepository {
  Future<UserProfile?> getUserProfile();
  Future<void> saveUserProfile(UserProfile profile);
}

// Implementation using the local data source
class UserProfileRepositoryImpl implements UserProfileRepository {
  final UserProfileLocalDataSource _localDataSource;

  UserProfileRepositoryImpl(this._localDataSource);

  @override
  Future<UserProfile?> getUserProfile() async {
    try {
      final profile = _localDataSource.getUserProfile();
      return profile;
    } catch (e) {
      // Handle potential errors from local data source if necessary
      print('Error getting profile from local source: $e');
      rethrow; // Or return null / specific error
    }
  }

  @override
  Future<void> saveUserProfile(UserProfile profile) async {
    // For now, just save to local storage.
    // Later, could add logic to also save to a remote API.
    try {
      await _localDataSource.saveUserProfile(profile);
      // Optionally trigger remote sync after local save:
      // await _remoteDataSource.saveUserProfile(profile);
    } catch (e) {
      print('Error saving profile to local source: $e');
      rethrow; // Propagate error
    }
  }

  // Implement other methods like delete if needed
  Future<void> deleteUserProfile() async {
    try {
      await _localDataSource.deleteUserProfile();
      // Optionally trigger remote delete:
      // await _remoteDataSource.deleteUserProfile();
    } catch (e) {
      print('Error deleting profile from local source: $e');
      rethrow;
    }
  }
}