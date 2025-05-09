import 'package:dio/dio.dart';
import '../../models/user_profile.dart';
import '../../models/allergen_info.dart';

class UserProfileApiService {
  final Dio _dio;

  UserProfileApiService(this._dio);

  /// Fetches the user profile from the backend using the user's ID.
  /// [userId] The unique identifier for the user.
  /// Returns null if the profile is not found (404).
  /// Throws DioException for other network/server errors.
  Future<UserProfile?> fetchProfile(String userId) async {
    if (userId.isEmpty) {
      print('API Service Error: fetchProfile called with empty userId.');
      throw ArgumentError('userId cannot be empty');
    }
    final String endpoint = '/users/$userId/profile';
    print('API Service: Fetching profile for userId: $userId from $endpoint');

    try {
      final response = await _dio.get(endpoint);

      if (response.statusCode == 200 && response.data != null) {
        print('API Service: Profile fetched successfully for userId: $userId');
        if (response.data is Map<String, dynamic>) {
          return UserProfile.fromJson(response.data as Map<String, dynamic>);
        } else {
          print('API Service Error: Invalid response data format for userId: $userId. Expected Map, got ${response.data.runtimeType}');
          throw DioException(
            requestOptions: response.requestOptions,
            response: response,
            error: 'Invalid response format from server',
            type: DioExceptionType.badResponse,
          );
        }

      } else if (response.statusCode == 404) {
        print('API Service: Profile not found for userId: $userId (404)');
        return null;
      } else {
        print('API Service Error: Failed to fetch profile for userId: $userId. Status: ${response.statusCode}');
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: 'Failed to fetch profile: Status code ${response.statusCode}',
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      print('API Service: DioException fetching profile for userId: $userId - ${e.message}');
      if (e.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    } catch (e) {
      print('API Service: Unexpected error fetching profile for userId: $userId - $e');
      rethrow;
    }
  }

  /// Saves (creates or updates) the user profile on the backend for the specified user ID.
  /// [userId] The unique identifier for the user whose profile is being saved.
  /// [profile] The UserProfile object containing the data to save.
  /// Expects the backend to return the updated/created profile.
  /// Throws DioException on failure.
  Future<UserProfile> saveProfile(String userId, UserProfile profile) async {
    if (userId.isEmpty) {
      print('API Service Error: saveProfile called with empty userId.');
      throw ArgumentError('userId cannot be empty');
    }
    final profileToSave = profile.userId == userId ? profile : profile.copyWith(userId: userId);

    final String endpoint = '/users/$userId/profile';
    print('API Service: Saving profile for userId: $userId to $endpoint');

    try {
      final response = await _dio.put(
        endpoint,
        data: profileToSave.toJson(),
      );

      if (response.statusCode == 200 && response.data != null) {
        print('API Service: Profile saved successfully for userId: $userId');
        if (response.data is Map<String, dynamic>) {
          return UserProfile.fromJson(response.data as Map<String, dynamic>);
        } else {
          print('API Service Error: Invalid response data format after saving profile for userId: $userId. Expected Map, got ${response.data.runtimeType}');
          throw DioException(
            requestOptions: response.requestOptions,
            response: response,
            error: 'Invalid response format from server after save',
            type: DioExceptionType.badResponse,
          );
        }
      } else {
        print('API Service Error: Failed to save profile for userId: $userId. Status: ${response.statusCode}');
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: 'Failed to save profile: Status code ${response.statusCode}',
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      print('API Service: DioException saving profile for userId: $userId - ${e.message}');
      rethrow;
    } catch (e) {
      print('API Service: Unexpected error saving profile for userId: $userId - $e');
      rethrow;
    }
  }

  /// Fetches the globally defined list of allergens (not user-specific).
  /// This endpoint likely doesn't need a userId.
  Future<List<AllergenInfo>> fetchAllergens() async {
    const String endpoint = '/allergens';
    print("API Service: Fetching allergens from $endpoint");
    try {
      final response = await _dio.get(endpoint);

      if (response.statusCode == 200 && response.data is List) {
        final List<dynamic> jsonData = response.data as List;
        final allergens = jsonData
            .map((item) => AllergenInfo.fromJson(item as Map<String, dynamic>))
            .toList();
        print("API Service: Fetched ${allergens.length} allergens.");
        return allergens;
      } else {
        print('API Service Error: Failed to fetch allergens. Status: ${response.statusCode}, Data type: ${response.data?.runtimeType}');
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: 'Failed to fetch allergens: Status code ${response.statusCode} or invalid data type',
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      print('API Service: DioException fetching allergens: ${e.message}');
      rethrow;
    } catch (e) {
      print('API Service: Unexpected error fetching allergens: $e');
      rethrow;
    }
  }
}