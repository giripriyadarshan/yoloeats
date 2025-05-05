import 'package:hive_flutter/hive_flutter.dart';
import '../../models/product_info.dart';
import '../../main.dart';
import '../../models/product.dart';
import '../../main.dart' show productCacheBoxName, productDetailBoxName;

class ProductLocalDataSource {
  Future<ProductInfo?> getCachedProductInfo(String barcode) async {
    try {
      final box = await Hive.openBox<ProductInfo>(productCacheBoxName);
      return box.get(barcode);
    } catch (e) {
      print('Error getting ProductInfo for $barcode from Hive: $e');
      return null;
    }
  }

  Future<void> saveCachedProductInfo(ProductInfo productInfo) async {
    try {
      final box = await Hive.openBox<ProductInfo>(productCacheBoxName);
      await box.put(productInfo.barcode, productInfo);
    } catch (e) {
      print('Error saving ProductInfo for ${productInfo.barcode} to Hive: $e');
    }
  }

  Future<void> clearProductInfoCache() async {
    try {
      final box = await Hive.openBox<ProductInfo>(productCacheBoxName);
      await box.clear();
      print('Product cache cleared.');
    } catch (e) {
      print('Error clearing product cache: $e');
    }
  }

  Future<Product?> getProductDetail(String barcode) async {
    try {
      final box = await Hive.openBox<Product>(productDetailBoxName);
      return box.get(barcode);
    } catch (e) {
      print('Error getting Product detail for $barcode from Hive: $e');
      return null;
    }
  }

  Future<void> saveProductDetail(Product product) async {
    if (product.code.isEmpty) {
      print('Error: Cannot save product detail to cache without a barcode.');
      return;
    }
    try {
      final box = await Hive.openBox<Product>(productDetailBoxName);
      await box.put(product.code, product); // Use barcode as key
      print('Saved full product detail for ${product.code} to cache.');
    } catch (e) {
      print('Error saving Product detail for ${product.code} to Hive: $e');
    }
  }

  Future<void> clearProductDetailCache() async {
    try {
      final box = await Hive.openBox<Product>(productDetailBoxName);
      await box.clear();
      print('Product detail cache cleared.');
    } catch (e) {
      print('Error clearing product detail cache: $e');
    }
  }
}