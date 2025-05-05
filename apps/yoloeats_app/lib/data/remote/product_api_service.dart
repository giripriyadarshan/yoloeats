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
        return Product.fromJson(response.data as Map<String, dynamic>);
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
      rethrow;
    }
  }

  /// Fetches a product by its MongoDB ObjectId (_id) from the backend.
  Future<Product?> getProductById(String id) async {
    print('API Service: Fetching product by ID: $id');
    try {
      final response = await _dio.get('/products/$id');

      if (response.statusCode == 200) {
        return Product.fromJson(response.data as Map<String, dynamic>);
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
      rethrow;
    }
  }

  /// Searches for products based on query parameters.
  Future<List<Product>> searchProducts(Map<String, dynamic> queryParams) async {
    print('API Service: Searching products with params: $queryParams');
    try {
      final response = await _dio.get(
        '/products/search',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data is List) {
        final List<dynamic> jsonData = response.data as List;
        final products = jsonData
            .map((item) => Product.fromJson(item as Map<String, dynamic>))
            .toList();
        print('API Service: Search returned ${products.length} products.');
        return products;
      } else {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: 'Failed to search products: Status ${response.statusCode}',
          type: DioExceptionType.badResponse,
        );
      }
    } on DioException catch (e) {
      print('API Service: DioException searching products: $e');
      rethrow;
    } catch (e) {
      print('API Service: Unexpected error searching products: $e');
      rethrow;
    }
  }
}