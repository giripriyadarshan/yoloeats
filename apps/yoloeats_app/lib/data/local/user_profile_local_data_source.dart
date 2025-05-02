// File: lib/data/local/user_profile_local_data_source.dart

import 'package:hive_flutter/hive_flutter.dart';

import '../../models/user_profile.dart'; // Import the UserProfile model
import '../../main.dart'; // Import main to access the box name constant

/// Key used to store the single user profile object in the Hive box.
const String _userProfileKey = 'currentUser';

class UserProfileLocalDataSource {
  /// Retrieves the currently stored UserProfile from the Hive box.
  /// Returns null if no profile is found.
  UserProfile? getUserProfile() {
    try {
      final box = Hive.box<UserProfile>(userProfileBoxName);
      // Hive's get is synchronous
      return box.get(_userProfileKey);
    } catch (e) {
      // Log error or handle cases where box might not be open (though it should be)
      print('Error getting user profile from Hive: $e');
      return null;
    }
  }

  /// Saves the given UserProfile object to the Hive box, overwriting any existing one.
  Future<void> saveUserProfile(UserProfile profile) async {
    try {
      final box = Hive.box<UserProfile>(userProfileBoxName);
      // Hive's put is asynchronous
      await box.put(_userProfileKey, profile);
    } catch (e) {
      // Log error or handle potential Hive errors
      print('Error saving user profile to Hive: $e');
      // Optionally rethrow or handle the error based on app requirements
      // throw Exception('Failed to save user profile');
    }
  }

  /// Deletes the stored UserProfile from the Hive box.
  Future<void> deleteUserProfile() async {
    try {
      final box = Hive.box<UserProfile>(userProfileBoxName);
      await box.delete(_userProfileKey);
    } catch (e) {
      print('Error deleting user profile from Hive: $e');
    }
  }
}