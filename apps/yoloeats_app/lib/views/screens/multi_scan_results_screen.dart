import 'package:flutter/material.dart';

import 'product_detail_screen.dart';

class MultiScanResultsScreen extends StatelessWidget {
  final List<String> barcodes;

  const MultiScanResultsScreen({required this.barcodes, super.key});

  void _navigateToDetail(BuildContext context, String barcode) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailScreen(productIdentifier: barcode),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scanned Items (${barcodes.length})'),
      ),
      body: barcodes.isEmpty
          ? const Center(child: Text('No barcodes were scanned.'))
          : ListView.builder(
        itemCount: barcodes.length,
        itemBuilder: (context, index) {
          final barcode = barcodes[index];
          return ListTile(
            title: Text(barcode),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _navigateToDetail(context, barcode),
            // TODO: Future enhancement: Fetch product info here
            // leading: FutureBuilder<Product?>(...), // Or use Riverpod FutureProvider
            // subtitle: Text('Loading...'),
          );
        },
      ),
    );
  }
}