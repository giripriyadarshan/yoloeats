import 'package:dio/dio.dart';
import 'package:yoloeats_app/models/user_profile.dart';
import '../../models/allergen_info.dart';

class UserProfileApiService {
  final Dio _dio;

  UserProfileApiService(this._dio);

  /// Fetches the user profile from the backend.
  /// Returns null if the profile is not found (404).
  /// Throws DioException for other network/server errors.
  Future<UserProfile?> fetchProfile() async {
    try {
      final response = await _dio.get('/profile'); // GET /api/v1/profile

      if (response.statusCode == 200) {
        return UserProfile.fromJson(response.data as Map<String, dynamic>);
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: 'Failed to fetch profile: Status code ${response.statusCode}',
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      print('DioException fetching profile: $e');
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    } catch (e) {
      print('Error fetching profile: $e');
      rethrow;
    }
  }

  /// Saves (creates or updates) the user profile on the backend.
  /// Expects the backend to return the updated/created profile.
  /// Throws DioException on failure.
  Future<UserProfile> saveProfile(UserProfile profile) async {
    try {
      // PUT /api/v1/profile - Send only relevant fields for update
      final payload = {
        if (profile.username != null) 'username': profile.username,
        if (profile.email != null) 'email': profile.email,
        'allergens': profile.allergens,
        'dietary_prefs': profile.dietaryPrefs,
        'risk_tolerance': profile.riskTolerance.toJson(),
      };

      final response = await _dio.put(
        '/profile',
        data: payload, // Use the filtered payload map
      );

      if (response.statusCode == 200) {
        // Backend returns the updated/created profile
        return UserProfile.fromJson(response.data as Map<String, dynamic>);
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: 'Failed to save profile: Status code ${response.statusCode}',
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      print('DioException saving profile: $e');
      rethrow;
    } catch (e) {
      print('Error saving profile: $e');
      rethrow;
    }
  }

  Future<List<AllergenInfo>> fetchAllergens() async {
    print("API Service: Fetching allergens...");
    try {
      final response = await _dio.get('/allergens'); // GET /api/v1/allergens

      if (response.statusCode == 200 && response.data is List) {
        final List<dynamic> jsonData = response.data as List;
        final allergens = jsonData
            .map((item) => AllergenInfo.fromJson(item as Map<String, dynamic>))
            .toList();
        print("API Service: Fetched ${allergens.length} allergens.");
        return allergens;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: 'Failed to fetch allergens: Status code ${response.statusCode}',
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      print('DioException fetching allergens: $e');
      rethrow;
    } catch (e) {
      print('Error fetching allergens: $e');
      rethrow;
    }
  }
}