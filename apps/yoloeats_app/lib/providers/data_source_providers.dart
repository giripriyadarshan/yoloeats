import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/local/product_local_data_source.dart';
import '../data/local/user_profile_local_data_source.dart';

final userProfileLocalDataSourceProvider = Provider<UserProfileLocalDataSource>(
      (ref) => UserProfileLocalDataSource(),
);

final productLocalDataSourceProvider = Provider<ProductLocalDataSource>(
      (ref) => ProductLocalDataSource(),
);