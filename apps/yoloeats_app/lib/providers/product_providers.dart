import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../data/repositories/product_repository.dart';
import 'api_service_providers.dart';
import 'data_source_providers.dart';

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  final apiService = ref.watch(productApiServiceProvider);
  final localDataSource = ref.watch(productLocalDataSourceProvider);

  return ProductRepositoryImpl(apiService, localDataSource);
});


final currentProductProvider = FutureProvider.autoDispose
    .family<Product?, String>((ref, productIdentifier) async {
  final repository = ref.watch(productRepositoryProvider);

  print("Provider: Fetching product for identifier: $productIdentifier");

  final product = await repository.getProduct(productIdentifier);

  return product;
});