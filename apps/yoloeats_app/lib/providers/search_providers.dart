import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import '../models/product.dart';
import '../models/user_profile.dart';
import '../data/repositories/product_repository.dart';
import 'product_providers.dart';
import 'user_profile_providers.dart';

class SearchState extends Equatable {
  final bool isLoading;
  final List<Product> results;
  final String? error;
  final String currentQuery;

  const SearchState({
    required this.isLoading,
    required this.results,
    this.error,
    required this.currentQuery,
  });

  factory SearchState.initial() {
    return const SearchState(
      isLoading: false,
      results: [],
      error: null,
      currentQuery: '',
    );
  }

  SearchState copyWith({
    bool? isLoading,
    List<Product>? results,
    String? error,
    bool clearError = false,
    String? currentQuery,
  }) {
    return SearchState(
      isLoading: isLoading ?? this.isLoading,
      results: results ?? this.results,
      error: clearError ? null : error ?? this.error,
      currentQuery: currentQuery ?? this.currentQuery,
    );
  }

  @override
  List<Object?> get props => [isLoading, results, error, currentQuery];

  @override
  bool get stringify => true;
}


class SearchNotifier extends StateNotifier<SearchState> {
  final ProductRepository _productRepository;
  final UserProfile? _userProfile;
  Timer? _debounce;

  SearchNotifier(this._productRepository, this._userProfile) : super(SearchState.initial());

  void onSearchQueryChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final trimmedQuery = query.trim();
      if (trimmedQuery == state.currentQuery && state.results.isNotEmpty && !state.isLoading) {
        print("Search skipped: Query '$trimmedQuery' hasn't changed.");
        return;
      }

      if (trimmedQuery.isEmpty) {
        state = SearchState.initial();
        print("Search query cleared.");
      } else {
        print("Debounced search triggered for: '$trimmedQuery'");
        _performSearch(trimmedQuery);
      }
    });
  }

  Future<void> _performSearch(String query) async {
    state = SearchState.initial().copyWith(isLoading: true, currentQuery: query);

    try {
      final Map<String, dynamic> queryParams = {'q': query};

      if (_userProfile != null) {
        if (_userProfile!.allergens.isNotEmpty) {
          queryParams['allergens'] = _userProfile!.allergens;
          print("Adding allergens to search: ${_userProfile!.allergens}");
        }
        if (_userProfile!.dietaryPrefs.isNotEmpty) {
          queryParams['diets'] = _userProfile!.dietaryPrefs;
          print("Adding diets to search: ${_userProfile!.dietaryPrefs}");
        }
      } else {
        print("User profile not available, searching without personalization.");
      }

      print("Performing search with queryParams: $queryParams");
      final results = await _productRepository.searchProducts(queryParams: queryParams);
      print("Search successful, received ${results.length} results.");
      if (state.currentQuery == query) {
        state = state.copyWith(isLoading: false, results: results, clearError: true);
      } else {
        print("Search results ignored: Query changed during fetch.");
      }
    } catch (e, stackTrace) {
      print("Search failed for query '$query': $e\n$stackTrace");
      if (state.currentQuery == query) {
        state = state.copyWith(isLoading: false, error: e.toString(), results: []);
      } else {
        print("Search error ignored: Query changed during fetch.");
      }
    }
  }

  void clearSearch() {
    _debounce?.cancel();
    state = SearchState.initial();
    print("Search cleared manually.");
  }


  @override
  void dispose() {
    print("Disposing SearchNotifier");
    _debounce?.cancel();
    super.dispose();
  }
}

final searchNotifierProvider = StateNotifierProvider.autoDispose<SearchNotifier, SearchState>((ref) {
  print("Creating SearchNotifier instance");
  final productRepository = ref.watch(productRepositoryProvider);
  final userProfileAsyncValue = ref.watch(userProfileProvider);
  final userProfile = userProfileAsyncValue.asData?.value;

  final notifier = SearchNotifier(productRepository, userProfile);
  ref.onDispose(() => print("Disposing searchNotifierProvider"));
  return notifier;
});