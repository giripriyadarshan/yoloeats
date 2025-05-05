import 'package:dio/dio.dart';
import '../../models/check_result.dart';

class AllergyCheckerApiService {
  final Dio _dio;

  AllergyCheckerApiService(this._dio);

  /// Calls the backend allergy checker service.
  /// Requires the user's ID and a product identifier (e.g., barcode).
  Future<CheckResult> checkProductSafetyOnline({
    required String productIdentifier,
    required String userId, // Added userId parameter
  }) async {
    final requestBody = {
      'productIdentifier': productIdentifier,
      'userId': userId,
    };
    print('API Service: Checking product safety online for user $userId, product $productIdentifier');

    try {
      final response = await _dio.post(
        '/check', // POST /api/v1/check (base URL is set in dioProvider)
        data: requestBody,
      );

      if (response.statusCode == 200) {
        print('API Service: Online check successful.');
        return CheckResult.fromJson(response.data as Map<String, dynamic>);
      } else {
        print('API Service: Online check failed with status ${response.statusCode}');
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: 'API Error: Status code ${response.statusCode}',
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      print('API Service: DioException during online check: $e');
      rethrow;
    } catch (e) {
      print('API Service: Unexpected error during online check: $e');
      throw Exception('Failed to perform online check: $e');
    }
  }
}