import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/search_providers.dart';
import '../../models/product.dart';
import 'product_detail_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _navigateToDetail(Product product) {
    if (product.code.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProductDetailScreen(productIdentifier: product.code),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product has no barcode to view details.'))
      );
    }

  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchNotifierProvider);
    final searchNotifier = ref.read(searchNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Products'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _textController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search by name, brand, category...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _textController.clear();
                    searchNotifier.clearSearch();
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              onChanged: searchNotifier.onSearchQueryChanged,
              onSubmitted: (query) => searchNotifier.onSearchQueryChanged(query),
            ),
          ),
          Expanded(
            child: _buildResults(searchState),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(SearchState searchState) {
    if (searchState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (searchState.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Error searching products:\n${searchState.error}',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    if (searchState.results.isEmpty) {
      if (searchState.currentQuery.isEmpty) {
        return const Center(child: Text('Enter a term above to search products.'));
      } else {
        return Center(
            child: Text(
                'No results found for "${searchState.currentQuery}".\nTry different keywords.'));
      }
    }

    return ListView.builder(
      itemCount: searchState.results.length,
      itemBuilder: (context, index) {
        final product = searchState.results[index];
        return ListTile(
          leading: SizedBox(
            width: 50,
            height: 50,
            child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                ? Image.network(
              product.imageUrl!,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(child: CircularProgressIndicator(strokeWidth: 2));
              },
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.broken_image, size: 30);
              },
            )
                : const Icon(Icons.image_not_supported, size: 30),
          ),
          title: Text(product.productName ?? 'Unknown Product'),
          subtitle: Text(product.brandsTags?.join(', ') ?? 'Unknown Brand'),
          onTap: () => _navigateToDetail(product), // Navigate on tap
          trailing: const Icon(Icons.chevron_right),
        );
      },
    );
  }
}