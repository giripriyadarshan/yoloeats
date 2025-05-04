import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'dart:io' show Platform;
import '../data/remote/user_profile_api_service.dart';
import '../data/remote/allergy_checker_api_service.dart';


final dioProvider = Provider<Dio>((ref) {
  String userProfileBaseUrl;
  String allergyCheckerBaseUrl;
  // TODO: Move base URLs to config/env
  const String userProfilePort = "8001";
  const String allergyCheckerPort = "8003";
  const String apiPrefix = "/api/v1";

  if (!kIsWeb && Platform.isAndroid) {
    const ip = 'http://10.0.2.2';
    userProfileBaseUrl = '$ip:$userProfilePort$apiPrefix';
    allergyCheckerBaseUrl = '$ip:$allergyCheckerPort$apiPrefix';
  } else {
    const ip = 'http://localhost';
    userProfileBaseUrl = '$ip:$userProfilePort$apiPrefix';
    allergyCheckerBaseUrl = '$ip:$allergyCheckerPort$apiPrefix';
  }

  final options = BaseOptions(
    baseUrl: allergyCheckerBaseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  );
  final dio = Dio(options);

  if (kDebugMode) {
    dio.interceptors.add(LogInterceptor(
        requestHeader: true, requestBody: true, responseHeader: false, responseBody: true));
  }
  return dio;
});

final userProfileApiServiceProvider = Provider<UserProfileApiService>((ref) {
  return UserProfileApiService(ref.watch(dioProvider));
});

final allergyCheckerApiServiceProvider = Provider<AllergyCheckerApiService>((ref) {
  return AllergyCheckerApiService(ref.watch(dioProvider));
});