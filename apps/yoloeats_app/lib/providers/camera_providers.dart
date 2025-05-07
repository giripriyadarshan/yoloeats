import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/tflite_service.dart';

final yoloDetectionsProvider = StateProvider<List<Recognition>>((ref) {
  return [];
});

final detectedBarcodeProvider = StateProvider<String?>((ref) {
  return null;
});

/// Toggles whether the camera screen is in multi-scan mode.
final multiScanModeProvider = StateProvider<bool>((ref) {
  print("Initializing multiScanModeProvider: false");
  return false;
});

/// Stores the list of unique barcodes collected during multi-scan mode.
final multiScanBarcodesProvider = StateProvider<List<String>>((ref) {
  print("Initializing multiScanBarcodesProvider: []");
  return [];
});