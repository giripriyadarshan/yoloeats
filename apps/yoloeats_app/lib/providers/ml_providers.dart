import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/tflite_service.dart';

final tfliteServiceProvider = Provider.autoDispose<TFLiteService>((ref) {
  final service = TFLiteService();

  ref.onDispose(() {
    service.closeModel();
  });

  return service;
});
