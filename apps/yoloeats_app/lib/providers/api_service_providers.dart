import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'dart:io' show Platform;

import '../data/remote/user_profile_api_service.dart';

final dioProvider = Provider<Dio>((ref) {
  // TODO: Move base URL to configuration/environment variables
  String baseUrl;
  const String userProfilePort = "8001";

  if (!kIsWeb && Platform.isAndroid) {
    // Android Emulator typically uses 10.0.2.2 to reach host machine's localhost
    baseUrl = 'http://10.0.2.2:$userProfilePort/api/v1';
  } else {
    // iOS Simulator, Desktop, Web usually use localhost or 127.0.0.1
    baseUrl = 'http://localhost:$userProfilePort/api/v1';
  }

  final options = BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  );
  final dio = Dio(options);


  if (kDebugMode) { // Only add in debug mode
    dio.interceptors.add(LogInterceptor(
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
    ));
  }

  return dio;
});

final userProfileApiServiceProvider = Provider<UserProfileApiService>((ref) {
  final dio = ref.watch(dioProvider);
  return UserProfileApiService(dio);
});