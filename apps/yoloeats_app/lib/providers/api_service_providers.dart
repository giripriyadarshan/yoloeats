import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'dart:io' show Platform;
import '../data/remote/user_profile_api_service.dart';
import '../data/remote/allergy_checker_api_service.dart';
import '../data/remote/product_api_service.dart';

// --- Configuration (TODO: Move to separate config/env file) ---
const String _userProfilePort = "8001";
const String _productCatalogPort = "8002";
const String _allergyCheckerPort = "8003";
const String _apiPrefix = "/api/v1";

String _getBaseUrl(String port) {
  if (!kIsWeb && Platform.isAndroid) {
    return 'http://100.87.156.48:$port$_apiPrefix';
  } else {
    return 'http://localhost:$port$_apiPrefix';
  }
}


BaseOptions _createBaseOptions(String port) => BaseOptions(
  baseUrl: _getBaseUrl(port),
  connectTimeout: const Duration(seconds: 8),
  receiveTimeout: const Duration(seconds: 8),
);

final _userProfileDioProvider = Provider<Dio>((ref) {
  final dio = Dio(_createBaseOptions(_userProfilePort));
  if (kDebugMode) dio.interceptors.add(LogInterceptor(responseBody: true));
  return dio;
});

final _productApiDioProvider = Provider<Dio>((ref) {
  final dio = Dio(_createBaseOptions(_productCatalogPort));
  if (kDebugMode) dio.interceptors.add(LogInterceptor(responseBody: true));
  return dio;
});

final _allergyCheckerDioProvider = Provider<Dio>((ref) {
  final dio = Dio(_createBaseOptions(_allergyCheckerPort));
  if (kDebugMode) dio.interceptors.add(LogInterceptor(responseBody: true));
  return dio;
});

final userProfileApiServiceProvider = Provider<UserProfileApiService>((ref) {
  return UserProfileApiService(ref.watch(_userProfileDioProvider));
});

final allergyCheckerApiServiceProvider = Provider<AllergyCheckerApiService>((ref) {
  return AllergyCheckerApiService(ref.watch(_allergyCheckerDioProvider));
});

final productApiServiceProvider = Provider<ProductApiService>((ref) {
  return ProductApiService(ref.watch(_productApiDioProvider));
});