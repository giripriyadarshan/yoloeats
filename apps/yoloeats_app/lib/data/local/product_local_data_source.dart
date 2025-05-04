import 'package:hive_flutter/hive_flutter.dart';
import '../../models/product_info.dart';
import '../../main.dart';

class ProductLocalDataSource {
  /// Retrieves cached ProductInfo using the barcode as the key.
  /// Returns null if not found.
  Future<ProductInfo?> getProductInfo(String barcode) async {
    try {
      final box = await Hive.openBox<ProductInfo>(productCacheBoxName);
      return box.get(barcode);
    } catch (e) {
      print('Error getting product info for barcode $barcode from Hive: $e');
      return null;
    }
  }

  /// Saves ProductInfo to the cache using its barcode as the key.
  Future<void> saveProductInfo(ProductInfo product) async {
    try {
      final box = await Hive.openBox<ProductInfo>(productCacheBoxName);
      await box.put(product.barcode, product);
    } catch (e) {
      print('Error saving product info for barcode ${product.barcode} to Hive: $e');
    }
  }

  /// Clears the entire product cache box.
  Future<void> clearProductCache() async {
    try {
      final box = await Hive.openBox<ProductInfo>(productCacheBoxName);
      await box.clear();
      print('Product cache cleared.');
    } catch (e) {
      print('Error clearing product cache: $e');
    }
  }
}