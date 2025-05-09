import 'package:dio/dio.dart';
import '../../models/product.dart';

class ProductApiService {
  final Dio _dio;

  ProductApiService(this._dio);

  /// Fetches a product by its barcode from the backend.
  Future<Product?> getProductByBarcode(String barcode) async {
    print('API Service: Fetching product by barcode: $barcode');
    try {
      final response = await _dio.get('/products/barcode/$barcode');

      if (response.statusCode == 200) {
        if (response.data != null) {
          return Product.fromJson(response.data as Map<String, dynamic>);
        } else {
          print('API Service: Product found for barcode $barcode but response data is null.');
          return null;
        }
      } else if (response.statusCode == 404) {
        print('API Service: Product not found for barcode $barcode (404)');
        return null;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: 'Failed to fetch product by barcode: Status ${response.statusCode}',
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        print('API Service: Product not found for barcode $barcode (Dio 404)');
        return null;
      }
      print('API Service: DioException fetching product by barcode $barcode: $e');
      rethrow;
    } catch (e) {
      print('API Service: Unexpected error fetching product by barcode $barcode: $e');
      throw Exception("Failed to get product by barcode: $e");
    }
  }

  /// Fetches a product by its MongoDB ObjectId (_id) from the backend.
  Future<Product?> getProductById(String id) async {
    print('API Service: Fetching product by ID: $id');
    try {
      final response = await _dio.get('/products/$id');

      if (response.statusCode == 200) {
        if (response.data != null) {
          return Product.fromJson(response.data as Map<String, dynamic>);
        } else {
          print('API Service: Product found for ID $id but response data is null.');
          return null;
        }
      } else if (response.statusCode == 404) {
        print('API Service: Product not found for ID $id (404)');
        return null;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: 'Failed to fetch product by ID: Status ${response.statusCode}',
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        print('API Service: Product not found for ID $id (Dio 404)');
        return null;
      }
      print('API Service: DioException fetching product by ID $id: $e');
      rethrow;
    } catch (e) {
      print('API Service: Unexpected error fetching product by ID $id: $e');
      throw Exception("Failed to get product by ID: $e");
    }
  }

  /// Searches for products based on query parameters.
  /// Expects queryParams like {'q': 'search term', 'allergens': 'milk,nuts', 'diets': 'vegan'}
  Future<List<Product>> searchProducts({required Map<String, dynamic> queryParams}) async {
    print('API Service: Searching products with params: $queryParams');
    try {
      // Note: Dio automatically handles encoding query parameters, including lists.
      // If the backend expects comma-separated strings for lists, ensure the calling code
      // formats the map values correctly before passing them here.
      // Example: queryParams['allergens'] = userAllergens.join(',');
      final response = await _dio.get('/products/search', queryParameters: queryParams);

      if (response.statusCode == 200) {
        final List<dynamic>? jsonData = response.data as List<dynamic>?;
        if (jsonData != null) {
          return jsonData
              .map((item) => Product.fromJson(item as Map<String, dynamic>))
              .toList();
        } else {
          print('API Service: Product search returned 200 but data is null or not a list.');
          return [];
        }
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: "Failed to search products: Status Code ${response.statusCode}",
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      print('API Service: DioException searching products: $e');
      rethrow;
    } catch (e) {
      print('API Service: Unexpected error searching products: $e');
      throw Exception("Failed to search products: $e");
    }
  }


  /// Fetches personalized product recommendations based on a given product ID.
  Future<List<Product>> getRecommendations({required String productId}) async {
    print('API Service: Fetching recommendations for product ID: $productId');
    try {
      final response = await _dio.get('/products/$productId/recommendations');

      if (response.statusCode == 200) {
        final List<dynamic>? jsonData = response.data as List<dynamic>?;
        if (jsonData != null) {
          return jsonData
              .map((item) => Product.fromJson(item as Map<String, dynamic>))
              .toList();
        } else {
          print('API Service: Recommendations fetch returned 200 but data is null or not a list.');
          return [];
        }
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: "Failed to load recommendations: Status Code ${response.statusCode}",
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      print('API Service: DioException fetching recommendations for $productId: $e');
      rethrow;
    } catch (e) {
      print('API Service: Unexpected error fetching recommendations for $productId: $e');
      throw Exception("Failed to get recommendations: $e");
    }
  }

}