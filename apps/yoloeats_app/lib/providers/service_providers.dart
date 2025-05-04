import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/offline_allergy_checker_service.dart';

final offlineAllergyCheckerServiceProvider = Provider<OfflineAllergyCheckerService>(
      (ref) => OfflineAllergyCheckerService(),
);