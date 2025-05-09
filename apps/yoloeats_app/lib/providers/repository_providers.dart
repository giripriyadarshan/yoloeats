import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/user_profile_repository.dart';
import '../data/repositories/allergy_repository.dart';
import 'api_service_providers.dart';
import 'data_source_providers.dart';
import 'service_providers.dart';

final userProfileRepositoryProvider = Provider<UserProfileRepository>(
      (ref) {
    final localDataSource = ref.watch(userProfileLocalDataSourceProvider);
    final apiService = ref.watch(userProfileApiServiceProvider);
    return UserProfileRepositoryImpl(localDataSource, apiService, ref);
  },
);

final allergyRepositoryProvider = Provider<AllergyRepository>(
      (ref) {
    final apiService = ref.watch(allergyCheckerApiServiceProvider);
    final offlineService = ref.watch(offlineAllergyCheckerServiceProvider);
    final userProfileLocalDataSource = ref.watch(userProfileLocalDataSourceProvider);
    final productLocalDataSource = ref.watch(productLocalDataSourceProvider);

    return AllergyRepositoryImpl(
      apiService,
      offlineService,
      userProfileLocalDataSource,
      productLocalDataSource,
    );
  },
);