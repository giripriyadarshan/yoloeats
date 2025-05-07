// lib/views/widgets/recommendations_bottom_sheet.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/product_providers.dart';
import '../../models/product.dart';
import '../screens/product_detail_screen.dart'; // Import detail screen for navigation

class RecommendationsBottomSheet extends ConsumerWidget {
  final String productId; // The ID of the original product

  const RecommendationsBottomSheet({required this.productId, super.key});

  void _navigateToDetail(BuildContext context, Product product) {
    // Close the bottom sheet first
    Navigator.pop(context);
    // Navigate to the new product's detail screen
    // Use push, not pushReplacement, to allow going back
    if (product.code.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProductDetailScreen(productIdentifier: product.code),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected product has no barcode to view details.'))
      );
    }
  }


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the recommendations provider using the passed productId
    final recommendationsAsync = ref.watch(recommendationsProvider(productId));

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'Suggested Alternatives',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Divider(height: 20),

          // Content based on provider state
          Expanded(
            child: recommendationsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) {
                print("Error loading recommendations: $err\n$stack");
                return Center(
                  child: Text(
                    'Could not load recommendations.\n${err.toString()}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                );
              },
              data: (recommendations) {
                if (recommendations.isEmpty) {
                  return const Center(child: Text('No alternative recommendations found.'));
                }

                // Display list of recommendations
                return ListView.builder(
                  itemCount: recommendations.length,
                  itemBuilder: (context, index) {
                    final product = recommendations[index];
                    return ListTile(
                      leading: SizedBox(
                        width: 40, height: 40, // Smaller image for list
                        child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                            ? Image.network(
                          product.imageUrl!,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) =>
                          progress == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 1)),
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 24),
                        )
                            : const Icon(Icons.image_not_supported, size: 24),
                      ),
                      title: Text(product.productName ?? 'Unknown Product', maxLines: 1, overflow: TextOverflow.ellipsis,),
                      subtitle: Text(product.brandsTags.join(', ') ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_right, size: 18,),
                      onTap: () => _navigateToDetail(context, product), // Navigate on tap
                    );
                  },
                );
              },
            ),
          ),

          // Optional: Close button
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              child: const Text('Close'),
              onPressed: () => Navigator.pop(context),
            ),
          )
        ],
      ),
    );
  }
}