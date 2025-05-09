import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Holds the current user's identifier.
/// Initially null, will be populated with the device ID.
final currentUserIdProvider = StateProvider<String?>((ref) {
  print("currentUserIdProvider initialized with null");
  return null;
});

/// Asynchronously retrieves the platform-specific device ID.
/// For Android: Uses 'id' (unique per device instance).
/// For iOS: Uses 'identifierForVendor' (unique per app-vendor on device).
/// Returns null if the platform is not supported or an error occurs.
Future<String?> _getDeviceId() async {
  DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
  String? deviceId;

  try {
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      deviceId = androidInfo.id;
      print("Retrieved Android Device ID: $deviceId");
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      deviceId = iosInfo.identifierForVendor;
      print("Retrieved iOS IdentifierForVendor: $deviceId");
    } else {
      print("Unsupported platform for device ID retrieval: ${Platform.operatingSystem}");
    }
  } catch (e) {
    print("Failed to get device info: $e");
  }

  return deviceId;
}


/// Initializes the [currentUserIdProvider] by fetching the device ID.
/// Should be called once during app startup before accessing the provider's state.
/// Takes a [ProviderContainer] or [Ref] to update the provider state.
Future<void> initializeCurrentUserId(dynamic ref) async {
  print("Attempting to initialize Current User ID...");
  final deviceId = await _getDeviceId();
  if (deviceId != null) {
    if (ref is ProviderContainer) {
      ref.read(currentUserIdProvider.notifier).state = deviceId;
    } else if (ref is Ref) { // Handle WidgetRef, ProviderRef etc.
      ref.read(currentUserIdProvider.notifier).state = deviceId;
    } else {
      print("Error: initializeCurrentUserId requires a ProviderContainer or Ref.");
      return;
    }
    print("Current User ID Provider initialized with: $deviceId");
  } else {
    print("Could not initialize User ID: Device ID was null.");

  }
}