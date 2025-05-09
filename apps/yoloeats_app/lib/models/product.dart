import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';

part 'product.g.dart'; // For Hive generation

// Use next available typeId (0: UserProfile, 1: RiskLevel, 2: AllergenInfo, 3: ProductInfo)
@HiveType(typeId: 4)
class Product extends Equatable {
  @HiveField(0)
  final String id; // From MongoDB ObjectId as String (_id)

  @HiveField(1)
  final String code; // Barcode

  @HiveField(2)
  final String? productName;

  @HiveField(3)
  final List<String> brandsTags;

  @HiveField(4)
  final String? quantity;

  @HiveField(5)
  final String? imageUrl;

  @HiveField(6)
  final String? ingredientsText;

  @HiveField(7)
  final List<String> categoriesTags;

  @HiveField(8)
  final List<String> labelsTags; // e.g., organic, gluten-free

  @HiveField(9)
  final String? nutritionGradeFr; // Nutri-Score

  @HiveField(10)
  final List<String> tracesTags; // Explicit may-contain traces

  // Add other relevant fields from backend model as needed
  // e.g., generic_name, countries_tags, image_small_url, etc.

  const Product({
    required this.id,
    required this.code,
    this.productName,
    List<String>? brandsTags,
    this.quantity,
    this.imageUrl,
    this.ingredientsText,
    List<String>? categoriesTags,
    List<String>? labelsTags,
    this.nutritionGradeFr,
    List<String>? tracesTags,
  })  : brandsTags = brandsTags ?? const [],
        categoriesTags = categoriesTags ?? const [],
        labelsTags = labelsTags ?? const [],
        tracesTags = tracesTags ?? const [];

  factory Product.fromJson(Map<String, dynamic> json) {
    // Helper function to safely parse list of strings
    List<String> parseStringList(dynamic listData) {
      if (listData is List) {
        return listData.map((item) => item.toString()).toList();
      }
      return [];
    }

    return Product(
      // Map backend field names (potentially snake_case or specific names) to Dart fields
      id: json['id'] as String? ?? json['_id'] as String? ?? '', // Handle both 'id' and '_id'
      code: json['code'] as String? ?? '', // Assume code is mandatory from backend too
      productName: json['productName'] as String? ?? json['product_name'] as String?, // Handle camel/snake case
      brandsTags: parseStringList(json['brandsTags'] ?? json['brands_tags']),
      quantity: json['quantity'] as String?,
      imageUrl: json['imageUrl'] as String? ?? json['image_url'] as String?,
      ingredientsText: json['ingredientsText'] as String? ?? json['ingredients_text'] as String?,
      categoriesTags: parseStringList(json['categoriesTags'] ?? json['categories_tags']),
      labelsTags: parseStringList(json['labelsTags'] ?? json['labels_tags']),
      nutritionGradeFr: json['nutritionGradeFr'] as String? ?? json['nutrition_grade_fr'] as String?,
      tracesTags: parseStringList(json['tracesTags'] ?? json['traces_tags']),
      // Map other fields...
    );
  }

  // toJson might be useful for saving updates or caching, but primarily needed for Hive here
  // No need for toJson for API calls if updates use a different payload struct

  @override
  List<Object?> get props => [
    id,
    code,
    productName,
    brandsTags,
    quantity,
    imageUrl,
    ingredientsText,
    categoriesTags,
    labelsTags,
    nutritionGradeFr,
    tracesTags,
  ];

  @override
  bool? get stringify => true;
}