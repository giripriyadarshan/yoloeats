import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';
import 'product.dart';

part 'product_info.g.dart';

@HiveType(typeId: 3)
class ProductInfo extends HiveObject with EquatableMixin {
  @HiveField(0)
  final String barcode;

  @HiveField(1)
  final String? name;

  @HiveField(2)
  final List<String> ingredients;

  @HiveField(3)
  final List<String> explicitAllergens;

  @HiveField(4)
  final List<String> dietaryFlags;

  ProductInfo({
    required this.barcode,
    this.name,
    List<String>? ingredients,
    List<String>? explicitAllergens,
    List<String>? dietaryFlags,
  }) : ingredients = ingredients ?? [],
        explicitAllergens = explicitAllergens ?? [],
        dietaryFlags = dietaryFlags ?? [];

  factory ProductInfo.fromProduct(Product product) {
    final parsedIngredients = product.ingredientsText
        ?.split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList() ??
        [];

    return ProductInfo(
      barcode: product.code,
      name: product.productName,
      ingredients: parsedIngredients,
      explicitAllergens: product.tracesTags,
      dietaryFlags: product.labelsTags,
    );
  }

  @override
  List<Object?> get props => [
    barcode,
    name,
    ingredients,
    explicitAllergens,
    dietaryFlags,
  ];

  @override
  bool? get stringify => true;
}