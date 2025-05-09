import '../../models/product.dart';
import '../../models/product_info.dart';
import '../remote/product_api_service.dart';
import '../local/product_local_data_source.dart';

abstract class ProductRepository {
  /// Gets full product details, checks cache first.
  /// Identifier is typically the barcode.
  Future<Product?> getProduct(String identifier);

  /// Searches products via API based on provided query parameters.
  Future<List<Product>> searchProducts({required Map<String, dynamic> queryParams});

  /// Fetches personalized product recommendations based on a product ID.
  Future<List<Product>> getRecommendations({required String productId});
}

class ProductRepositoryImpl implements ProductRepository {
  final ProductApiService _apiService;
  final ProductLocalDataSource _localDataSource;

  ProductRepositoryImpl(this._apiService, this._localDataSource);

  @override
  Future<Product?> getProduct(String identifier) async {
    // TODO: Add robust check if identifier is barcode vs internal ID
    final String barcode = identifier;
    print("Repository: Getting product detail for identifier: $identifier (using as barcode: $barcode)");

    try {
      final localProduct = await _localDataSource.getProductDetail(barcode);
      if (localProduct != null) {
        print("Repository: Full product detail loaded from Hive cache for $barcode.");
        return localProduct;
      }

      print("Repository: No local detail found, fetching from API for barcode: $barcode");
      final apiProduct = await _apiService.getProductByBarcode(barcode);

      if (apiProduct != null) {
        print("Repository: Product fetched from API for barcode $barcode, saving to Hive.");
        _localDataSource.saveProductDetail(apiProduct).catchError((e) {
          print("Repository: Error saving full product detail for $barcode: $e");
        });

        try {
          final productInfo = ProductInfo.fromProduct(apiProduct);
          _localDataSource.saveCachedProductInfo(productInfo).catchError((e) {
            print("Repository: Error saving product info snippet for $barcode: $e");
          });
        } catch (e) {
          print("Repository: Error converting Product to ProductInfo for $barcode: $e");
        }

        return apiProduct;
      } else {
        print("Repository: API returned no product for barcode: $barcode");
        return null;
      }
    } catch (e) {
      print("Repository: Error in getProduct for $identifier: $e");
      try {
        final localProduct = await _localDataSource.getProductDetail(barcode);
        if (localProduct != null) {
          print("Repository: API failed for $identifier, returning potentially stale detail from Hive.");
          return localProduct;
        }
      } catch (localError) {
        print("Repository: Error fetching local detail during API fallback for $identifier: $localError");
      }
      rethrow;
    }
  }

  @override
  Future<List<Product>> searchProducts({required Map<String, dynamic> queryParams}) async {
    print("Repository: Searching products with params: $queryParams");
    try {
      final results = await _apiService.searchProducts(queryParams: queryParams);
      // TODO: Potentially cache search results or individual products from results?
      print("Repository: Search returned ${results.length} products.");
      return results;
    } catch (e) {
      print("Repository: Error in searchProducts: $e");
      rethrow;
    }
  }

  @override
  Future<List<Product>> getRecommendations({required String productId}) async {
    print("Repository: Fetching recommendations for product $productId");
    try {
      return await _apiService.getRecommendations(productId: productId);
    } catch (e) {
      print("Repository: Error fetching recommendations for $productId: $e");
      rethrow;
    }
  }
}