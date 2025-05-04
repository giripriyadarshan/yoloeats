import '../models/user_profile.dart';
import '../models/product_info.dart';
import '../models/check_result.dart';

class OfflineAllergyCheckerService {
  CheckResult checkProductSafetyOffline({
    required UserProfile userProfile,
    required ProductInfo productInfo,
  }) {
    print('Offline Service: Performing offline check for product ${productInfo.barcode}');
    final conflictingAllergens = <String>[];
    final conflictingDiets = <String>[];

    var status = SafetyStatus.safe;

    final userAllergensLower = userProfile.allergens.map((a) => a.toLowerCase()).toSet();

    final productAllergensLower = productInfo.explicitAllergens.map((a) => a.toLowerCase()).toSet();
    final productIngredientsLower = productInfo.ingredients.map((i) => i.toLowerCase()).toSet();

    final potentialAllergenicItems = productAllergensLower.union(productIngredientsLower);

    for (final item in potentialAllergenicItems) {
      if (userAllergensLower.contains(item)) {
        conflictingAllergens.add(item);
        status = SafetyStatus.unsafe;
        print('Offline Service: Allergen conflict found: $item');
      }
      // TODO: More sophisticated check? Ingredient mapping? Traces?
    }

    final userDietsLower = userProfile.dietaryPrefs.map((d) => d.toLowerCase()).toSet();
    final productFlagsLower = productInfo.dietaryFlags.map((f) => f.toLowerCase()).toSet();

    if (userDietsLower.contains('vegan')) {
      const nonVeganFlags = {'contains_milk', 'contains_eggs', 'contains_meat', 'contains_fish', 'contains_honey'};
      for (final flag in productFlagsLower) {
        if (nonVeganFlags.contains(flag)) {
          conflictingDiets.add(flag);
          status = SafetyStatus.unsafe;
          print('Offline Service: Diet conflict found (Vegan): $flag');
        }
      }
    }
    if (userDietsLower.contains('vegetarian')) {
      const nonVegetarianFlags = {'contains_meat', 'contains_fish'};
      for (final flag in productFlagsLower) {
        if (nonVegetarianFlags.contains(flag)) {
          if (!conflictingDiets.contains(flag)) conflictingDiets.add(flag);
          status = SafetyStatus.unsafe;
          print('Offline Service: Diet conflict found (Vegetarian): $flag');
        }
      }
    }
    // TODO: Add more comprehensive diet conflict rules

    print('Offline Service: Check complete. Status: $status');
    return CheckResult(
      status: status,
      conflictingAllergens: conflictingAllergens.toList(),
      conflictingDiets: conflictingDiets.toList(),
      traceAllergens: [],
      isOfflineResult: true,
      errorMessage: null,
    );
  }
}