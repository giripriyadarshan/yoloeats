import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/tflite_service.dart';

final yoloDetectionsProvider = StateProvider<List<Recognition>>((ref) {
  return [];
});

final detectedBarcodeProvider = StateProvider<String?>((ref) {
  return null;
});