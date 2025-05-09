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
      FocusScope.of(context).unfocus();
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

    print("SearchScreen build: isLoading=${searchState.isLoading}, results=${searchState.results.length}, error=${searchState.error}, query=${searchState.currentQuery}");


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
                    tooltip: "Clear Search",
                    onPressed: () {
                      _textController.clear();
                      searchNotifier.clearSearch();
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2.0),
                  )
              ),
              onChanged: searchNotifier.onSearchQueryChanged,
              onSubmitted: (query) => searchNotifier.onSearchQueryChanged(query),
              textInputAction: TextInputAction.search,
            ),
          ),
          Expanded(
            child: _buildResultsList(searchState),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(SearchState searchState) {
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

    if (searchState.results.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        itemCount: searchState.results.length,
        itemBuilder: (context, index) {
          final product = searchState.results[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4.0),
            child: ListTile(
              leading: SizedBox(
                width: 50,
                height: 50,
                child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: Image.network(
                    product.imageUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(child: CircularProgressIndicator(strokeWidth: 2, value: progress.expectedTotalBytes != null ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes! : null));
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(Icons.broken_image, size: 30, color: Colors.grey[400]);
                    },
                  ),
                )
                    : Icon(Icons.image_not_supported, size: 30, color: Colors.grey[400]),
              ),
              title: Text(product.productName ?? 'Unknown Product', style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(
                product.brandsTags.isNotEmpty ? product.brandsTags.join(', ') : 'Unknown Brand',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _navigateToDetail(product),
              trailing: const Icon(Icons.chevron_right),
              dense: true,
            ),
          );
        },
      );
    }

    if (searchState.currentQuery.isEmpty) {
      return const Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Enter a term above to search for products by name, brand, or category.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          )
      );
    } else {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'No products found matching "${searchState.currentQuery}".\nTry refining your search.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
  }
}