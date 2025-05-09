import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/check_result.dart';
import '../../providers/product_providers.dart';
import '../../providers/allergy_check_providers.dart';
import '../widgets/recommendations_bottom_sheet.dart';

class ProductDetailScreen extends ConsumerWidget {
  final String productIdentifier;

  const ProductDetailScreen({required this.productIdentifier, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productAsync = ref.watch(currentProductProvider(productIdentifier));
    final checkResultAsync = ref.watch(allergyCheckProvider(productIdentifier));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(currentProductProvider(productIdentifier));
              ref.invalidate(allergyCheckProvider(productIdentifier));
            },
            tooltip: 'Refresh Product & Safety Check',
          )
        ],
      ),
      body: productAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) {
          print("Error loading product details: $error\n$stackTrace");
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Could not load product details for "$productIdentifier".\nPlease try again later.\nError: $error',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          );
        },
        data: (product) {
          if (product == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Product with identifier "$productIdentifier" not found.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final showRecommendationsButton = checkResultAsync.maybeWhen(
            data: (result) => result.status == SafetyStatus.unsafe || result.status == SafetyStatus.caution,
            orElse: () => false,
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSafetyHeader(context, checkResultAsync),
                const SizedBox(height: 16),

                if (showRecommendationsButton) ...[
                  Center(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.recommend_outlined),
                      label: const Text('Find Safe Alternatives'),
                      onPressed: () {
                        if (product != null && product.id.isNotEmpty) {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                            ),
                            builder: (BuildContext modalContext) {
                              return RecommendationsBottomSheet(productId: product.id);
                            },
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Cannot fetch recommendations: Product ID is missing or product data is unavailable.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[100],
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                if (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                  Center(
                    child: Image.network(
                      product.imageUrl!,
                      height: 200,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const SizedBox(
                            height: 200,
                            child: Center(child: CircularProgressIndicator()));
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const SizedBox(
                            height: 200,
                            child: Center(child: Icon(Icons.broken_image, size: 40)));
                      },
                    ),
                  )
                else
                  const SizedBox(
                      height: 200,
                      child: Center(child: Icon(Icons.image_not_supported, size: 40))),
                const SizedBox(height: 16),

                Text(
                  product.productName ?? 'N/A',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),

                if (product.brandsTags.isNotEmpty)
                  Text(
                    'Brand: ${product.brandsTags.join(', ')}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),

                if (product.quantity != null && product.quantity!.isNotEmpty)
                  Text(
                    'Quantity: ${product.quantity}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),

                if (product.nutritionGradeFr != null && product.nutritionGradeFr!.isNotEmpty)
                  Text(
                    'Nutri-Score: ${product.nutritionGradeFr!.toUpperCase()}',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                const Divider(height: 32),

                Text('Ingredients:', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(product.ingredientsText?.isNotEmpty ?? false
                    ? product.ingredientsText!
                    : 'Not available'),
                const Divider(height: 32),

                if (product.categoriesTags.isNotEmpty) ...[
                  Text('Categories:', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: product.categoriesTags.map((tag) => Chip(label: Text(tag))).toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                if (product.labelsTags.isNotEmpty) ...[
                  Text('Labels:', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: product.labelsTags.map((tag) => Chip(label: Text(tag))).toList(),
                  ),
                ],

                if (product.tracesTags.isNotEmpty) ...[
                  const Divider(height: 32),
                  Text('May Contain (Traces):', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8.0,
                    runSpacing: 4.0,
                    children: product.tracesTags.map((tag) => Chip(
                      label: Text(tag),
                      backgroundColor: Colors.orange[50],
                    )).toList(),
                  ),
                ],


                const Divider(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSafetyHeader(BuildContext context, AsyncValue<CheckResult> checkResultAsync) {
    return Card(
      elevation: 2,
      color: checkResultAsync.maybeWhen(
        data: (result) {
          switch (result.status) {
            case SafetyStatus.safe: return Colors.green[50];
            case SafetyStatus.unsafe: return Colors.red[50];
            case SafetyStatus.caution: return Colors.orange[50];
            case SafetyStatus.offline: return Colors.blue[50];
            case SafetyStatus.error: return Colors.grey[100];
          }
        },
        orElse: () => Colors.grey[100],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: checkResultAsync.when(
          loading: () => const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 10),
              Text('Checking safety...'),
            ],
          ),
          error: (error, stack) {
            print("Error in safety check provider: $error\n$stack");
            String displayError = "Safety check failed";
            if (error is CheckResult && error.status == SafetyStatus.error) {
              displayError = error.errorMessage ?? displayError;
            } else {
              displayError = error.toString().split('\n').first;
            }
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 24),
                const SizedBox(width: 10),
                Expanded(child: Text(displayError, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ],
            );
          },
          data: (result) {
            IconData statusIcon;
            Color statusColor;
            String statusText;
            switch (result.status) {
              case SafetyStatus.safe:
                statusIcon = Icons.check_circle; statusColor = Colors.green; statusText = "Safe for You"; break;
              case SafetyStatus.unsafe:
                statusIcon = Icons.dangerous; statusColor = Colors.red; statusText = "Unsafe!"; break;
              case SafetyStatus.caution:
                statusIcon = Icons.warning_amber; statusColor = Colors.orange; statusText = "Use Caution"; break;
              case SafetyStatus.offline:
                statusIcon = Icons.wifi_off; statusColor = Colors.blue; statusText = "Offline Result"; break;
              case SafetyStatus.error:
                statusIcon = Icons.error_outline; statusColor = Colors.grey; statusText = "Check Failed"; break;
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(statusIcon, color: statusColor, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        statusText,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: statusColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (result.isOfflineResult && result.status != SafetyStatus.error)
                      Tooltip(message: "Result based on locally cached data", child: Icon(Icons.cloud_off, size: 18, color: Colors.blueGrey))
                  ],
                ),
                if (result.errorMessage != null && result.status == SafetyStatus.error)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(result.errorMessage!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                if (result.conflictingAllergens.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text("Conflicts with Allergens: ${result.conflictingAllergens.join(', ')}", style: TextStyle(color: statusColor)),
                  ),
                if (result.traceAllergens.isNotEmpty && (result.status == SafetyStatus.caution || result.status == SafetyStatus.unsafe))
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text("Potential Trace Allergens: ${result.traceAllergens.join(', ')}", style: TextStyle(color: statusColor)),
                  ),
                if (result.conflictingDiets.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text("Conflicts with Diets: ${result.conflictingDiets.join(', ')}", style: TextStyle(color: statusColor)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

}