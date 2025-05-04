import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';

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

  @override
  List<Object?> get props => [
    barcode,
    name,
    ingredients,
    explicitAllergens,
    dietaryFlags,
  ];
}