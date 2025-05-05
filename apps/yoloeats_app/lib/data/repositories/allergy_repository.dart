import 'package:dio/dio.dart';
import '../../models/check_result.dart';
import '../remote/allergy_checker_api_service.dart';
import '../../services/offline_allergy_checker_service.dart';
import '../local/user_profile_local_data_source.dart';
import '../local/product_local_data_source.dart';

abstract class AllergyRepository {
  Future<CheckResult> checkProductSafety({
    required String productIdentifier,
    required String userId,
  });
}

class AllergyRepositoryImpl implements AllergyRepository {
  final AllergyCheckerApiService _apiService;
  final OfflineAllergyCheckerService _offlineService;
  final UserProfileLocalDataSource _userProfileLocalDataSource;
  final ProductLocalDataSource _productLocalDataSource;

  AllergyRepositoryImpl(
      this._apiService,
      this._offlineService,
      this._userProfileLocalDataSource,
      this._productLocalDataSource,
      );

  @override
  Future<CheckResult> checkProductSafety({
    required String productIdentifier,
    required String userId,
  }) async {
    try {
      print("Repository: Attempting online safety check for user $userId, product: $productIdentifier");
      final onlineResult = await _apiService.checkProductSafetyOnline(
        productIdentifier: productIdentifier,
        userId: userId,
      );
      print("Repository: Online check successful.");
      return onlineResult;
    } on DioException catch (e) {
      bool isNetworkError = e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.unknown;

      if (isNetworkError) {
        print("Repository: Online check failed due to network error ($e). Attempting offline check.");
        final userProfile = _userProfileLocalDataSource.getUserProfile();
        final productInfo = await _productLocalDataSource.getCachedProductInfo(productIdentifier);

        if (userProfile != null && productInfo != null) {
          print("Repository: Found local data for offline check.");
          return _offlineService.checkProductSafetyOffline(
            userProfile: userProfile,
            productInfo: productInfo,
          );
        } else {
          print("Repository: Offline check failed: Missing local user profile or product info.");
          return CheckResult(
            status: SafetyStatus.error,
            isOfflineResult: false,
            errorMessage: "Network offline and local data unavailable.",
          );
        }
      } else {
        print("Repository: Online check failed with API error: ${e.response?.statusCode ?? e.message}");
        return CheckResult(
          status: SafetyStatus.error,
          isOfflineResult: false,
          errorMessage: "Online check failed: ${e.response?.statusMessage ?? 'Server error'}",
        );
      }
    } catch (e) {
      print("Repository: Unexpected error during safety check: $e");
      return CheckResult(
        status: SafetyStatus.error,
        isOfflineResult: false,
        errorMessage: "An unexpected error occurred during check.",
      );
    }
  }
}