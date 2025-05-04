import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yoloeats_app/models/check_result.dart';
import 'package:yoloeats_app/providers/allergy_check_providers.dart';

class ProductDetailScreen extends ConsumerWidget {
  final String productIdentifier;

  const ProductDetailScreen({required this.productIdentifier, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkResultAsync = ref.watch(allergyCheckProvider(productIdentifier));

    return Scaffold(
      appBar: AppBar(
        title: Text('Product Check: $productIdentifier'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: checkResultAsync.when(
            // --- Loading State ---
            loading: () => const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 10),
                Text("Checking safety..."),
              ],
            ),
            // --- Error State ---
            error: (error, stackTrace) {
              print("Error in allergyCheckProvider: $error\n$stackTrace");
              String displayError = "Could not perform safety check.";
              if (error is CheckResult && error.status == SafetyStatus.error) {
                displayError = error.errorMessage ?? displayError;
              } else if (error is String) {
                displayError = error;
              }
              return Text(
                'Error: $displayError',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              );
            },
            // --- Data State ---
            data: (result) => _buildCheckResultDisplay(context, result),
          ),
        ),
      ),
    );
  }

  // Helper widget to display the check result details
  Widget _buildCheckResultDisplay(BuildContext context, CheckResult result) {
    IconData statusIcon;
    Color statusColor;
    String statusText;

    switch (result.status) {
      case SafetyStatus.safe:
        statusIcon = Icons.check_circle;
        statusColor = Colors.green;
        statusText = "Safe for You";
        break;
      case SafetyStatus.unsafe:
        statusIcon = Icons.dangerous;
        statusColor = Colors.red;
        statusText = "Unsafe!";
        break;
      case SafetyStatus.caution:
        statusIcon = Icons.warning_amber;
        statusColor = Colors.orange;
        statusText = "Use Caution";
        break;
      case SafetyStatus.offline:
        statusIcon = Icons.wifi_off;
        statusColor = Colors.blue;
        statusText = "Offline Check Result";
        break;
      case SafetyStatus.error:
        statusIcon = Icons.error_outline;
        statusColor = Colors.grey;
        statusText = "Check Failed";
        break;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(statusIcon, color: statusColor, size: 60),
        const SizedBox(height: 10),
        Text(
          statusText,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: statusColor),
          textAlign: TextAlign.center,
        ),
        if (result.isOfflineResult && result.status != SafetyStatus.error)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              "(Result based on locally cached data)",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blueGrey),
              textAlign: TextAlign.center,
            ),
          ),
        if (result.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              result.errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),

        // Display conflicts if any
        if (result.conflictingAllergens.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            "Conflicting Allergens Found:",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: statusColor),
          ),
          Text(result.conflictingAllergens.join(', ')),
        ],
        if (result.traceAllergens.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            "Potential Trace Allergens Found:",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: statusColor),
          ),
          Text(result.traceAllergens.join(', ')),
        ],
        if (result.conflictingDiets.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            "Dietary Conflicts Found:",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: statusColor),
          ),
          Text(result.conflictingDiets.join(', ')),
        ],
      ],
    );
  }
}