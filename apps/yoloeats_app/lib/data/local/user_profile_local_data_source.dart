import 'package:hive_flutter/hive_flutter.dart';
import '../../models/user_profile.dart';
import '../../main.dart';
import '../../models/allergen_info.dart';
import '../../main.dart' show userProfileBoxName, allergenListBoxName;

/// Key used to store the single user profile object in the Hive box.
const String _userProfileKey = 'currentUser';
const String _allergenListKey = 'fullList';

class UserProfileLocalDataSource {
  /// Retrieves the currently stored UserProfile from the Hive box.
  /// Returns null if no profile is found.
  UserProfile? getUserProfile() {
    try {
      final box = Hive.box<UserProfile>(userProfileBoxName);
      return box.get(_userProfileKey);
    } catch (e) {
      print('Error getting user profile from Hive: $e');
      return null;
    }
  }

  /// Saves the given UserProfile object to the Hive box, overwriting any existing one.
  Future<void> saveUserProfile(UserProfile profile) async {
    try {
      final box = Hive.box<UserProfile>(userProfileBoxName);
      await box.put(_userProfileKey, profile);
    } catch (e) {
      print('Error saving user profile to Hive: $e');
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

  /// Retrieves the list of allergens from the Hive box.
  /// Returns an empty list if not found or on error.
  List<AllergenInfo> getAllergens() {
    try {
      final box = Hive.box<List>(allergenListBoxName);
      final dynamicList = box.get(_allergenListKey);
      if (dynamicList != null) {
        return dynamicList.cast<AllergenInfo>().toList();
      }
      return [];
    } catch (e) {
      print('Error getting allergens from Hive: $e');
      return [];
    }
  }

  /// Saves the list of allergens to the Hive box.
  Future<void> saveAllergens(List<AllergenInfo> allergens) async {
    try {
      final box = Hive.box<List>(allergenListBoxName);
      await box.put(_allergenListKey, allergens);
    } catch (e) {
      print('Error saving allergens to Hive: $e');
    }
  }
}