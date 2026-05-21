import 'package:flutter/material.dart';
import 'dart:async';

import '../models/recipe.dart';
import '../services/api_service.dart';
import '../widgets/recipe_image.dart';
import 'favorites_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'recipe_detail_screen.dart';
import 'chat_assistant_screen.dart';

class AllRecipesLandingScreen extends StatefulWidget {
  const AllRecipesLandingScreen({super.key});

  @override
  State<AllRecipesLandingScreen> createState() => _AllRecipesLandingScreenState();
}

class _AllRecipesLandingScreenState extends State<AllRecipesLandingScreen> {
  static const int _pageSize = 10;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Recipe> _items = [];
  List<Recipe> _localCatalog = [];
  String _selectedCategory = 'All';
  int _currentPage = 1;
  int _lastPage = 1;
  int _totalCatalog = 0;
  bool _loadingMore = false;
  bool _syncingWithServer = false;
  bool _hasMore = true;
  Timer? _searchDebounce;
  int _fetchToken = 0;

  String get _searchQuery => _searchController.text.trim();

  bool get _isSearchActive => _searchQuery.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    ApiService.recipesCatalogRevision.addListener(_onCatalogUpdated);
    _hydrateLocalCatalog();
    unawaited(ApiService.fetchRecipes());
    unawaited(_fetchPage(reset: true));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    ApiService.recipesCatalogRevision.removeListener(_onCatalogUpdated);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onCatalogUpdated() {
    _hydrateLocalCatalog(silent: true);
  }

  void _hydrateLocalCatalog({bool silent = false}) {
    final cached = ApiService.peekCachedRecipes();
    if (cached == null || cached.isEmpty) return;
    if (cached.length <= _localCatalog.length) return;
    _localCatalog = cached;
    if (!silent && mounted && !_isSearchActive) {
      setState(() {
        _totalCatalog = _localCatalog.length;
        if (_items.isEmpty) {
          _applyLocalBrowse(reset: true);
        }
      });
    }
  }

  bool _matchesQuery(Recipe recipe, String query) {
    final needle = query.toLowerCase();
    if (recipe.name.toLowerCase().contains(needle)) return true;
    final category = recipe.category?.toLowerCase() ?? '';
    if (category.contains(needle)) return true;
    for (final ingredient in recipe.ingredients) {
      if (ingredient.toLowerCase().contains(needle)) return true;
    }
    return false;
  }

  bool _matchesCategory(Recipe recipe) {
    if (_selectedCategory == 'All') return true;
    return (recipe.category ?? '').toLowerCase() ==
        _selectedCategory.toLowerCase();
  }

  List<Recipe> _filteredCatalog() {
    var list = _localCatalog.where(_matchesCategory);
    if (_searchQuery.isNotEmpty) {
      list = list.where((r) => _matchesQuery(r, _searchQuery));
    }
    return list.toList();
  }

  void _applyLocalBrowse({required bool reset}) {
    final filtered = _filteredCatalog();
    final page = reset ? 1 : _currentPage + 1;
    final start = (page - 1) * _pageSize;
    final slice = filtered.skip(start).take(_pageSize).toList();
    final lastPage = filtered.isEmpty
        ? 1
        : ((filtered.length + _pageSize - 1) ~/ _pageSize);

    setState(() {
      if (reset) {
        _items = slice;
      } else {
        final seen = _items.map((r) => r.id).toSet();
        _items.addAll(slice.where((r) => !seen.contains(r.id)));
      }
      _currentPage = page;
      _lastPage = lastPage;
      _totalCatalog = filtered.length;
      _hasMore = page < lastPage;
      _syncingWithServer = false;
      _loadingMore = false;
    });
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    final query = _searchQuery;

    if (query.isNotEmpty && _localCatalog.length >= 50) {
      _applyLocalBrowse(reset: true);
      setState(() => _syncingWithServer = true);
    } else if (query.isEmpty) {
      if (_localCatalog.length >= 50) {
        _applyLocalBrowse(reset: true);
      }
      setState(() => _syncingWithServer = false);
    }

    _searchDebounce = Timer(const Duration(milliseconds: 150), () {
      unawaited(_fetchPage(reset: true));
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _loadingMore || !_hasMore) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 360) {
      unawaited(_fetchPage());
    }
  }

  Future<void> _fetchPage({bool reset = false}) async {
    if (!reset && (_loadingMore || !_hasMore || _currentPage >= _lastPage)) {
      return;
    }

    final token = ++_fetchToken;
    final nextPage = reset ? 1 : _currentPage + 1;
    final query = _searchQuery;

    if (reset && query.isEmpty && _localCatalog.length >= 50) {
      _applyLocalBrowse(reset: true);
      setState(() => _syncingWithServer = false);
    } else if (reset) {
      setState(() {
        _loadingMore = true;
        _syncingWithServer = query.isNotEmpty;
      });
    } else {
      setState(() => _loadingMore = true);
    }

    try {
      final result = await ApiService.fetchRecipesBrowsePage(
        page: nextPage,
        perPage: _pageSize,
        category: _selectedCategory,
        q: query,
      );
      if (!mounted || token != _fetchToken) return;

      setState(() {
        if (reset) {
          _items = result.items;
        } else {
          final seen = _items.map((r) => r.id).toSet();
          _items.addAll(
            result.items.where((r) => !seen.contains(r.id)),
          );
        }
        _currentPage = result.currentPage;
        _lastPage = result.lastPage < 1 ? 1 : result.lastPage;
        _totalCatalog = result.total;
        _hasMore = _currentPage < _lastPage;
        _syncingWithServer = false;
      });
    } catch (_) {
      if (!mounted || token != _fetchToken) return;
      if (reset && (_localCatalog.length >= 50 || query.isNotEmpty)) {
        _applyLocalBrowse(reset: true);
      }
    } finally {
      if (mounted && token == _fetchToken) {
        setState(() {
          _loadingMore = false;
          _syncingWithServer = false;
        });
      }
    }
  }

  List<String> get _categoryOptions {
    final counts = <String, int>{};
    final source = _localCatalog.isNotEmpty ? _localCatalog : _items;
    for (final recipe in source) {
      final category = recipe.category?.trim();
      if (category == null || category.isEmpty) continue;
      counts[category] = (counts[category] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ['All', ...sorted.take(8).map((e) => e.key)];
  }

  void _openRecipe(Recipe recipe) {
    unawaited(ApiService.fetchRecipeDetail(recipe.id));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(
          recipeId: recipe.id,
          initialRecipe: recipe,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showSpinner = _loadingMore || _syncingWithServer;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Browse Recipes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.favorite_outline_rounded),
            tooltip: 'Favorites',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FavoritesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: 'Profile',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: 'Assistant',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatAssistantScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            tooltip: 'Logout',
            onPressed: () async {
              await ApiService.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _fetchPage(reset: true),
          child: _items.isEmpty && !showSpinner
              ? ListView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 140),
                    Center(
                      child: Text(
                        _isSearchActive
                            ? 'No recipes match your search.'
                            : 'No recipes found.',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                )
              : CustomScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                cs.primary.withValues(alpha: 0.16),
                                cs.primary.withValues(alpha: 0.07),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: cs.primary.withValues(alpha: 0.22)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Find your next favorite meal',
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _totalCatalog > 0
                                    ? '$_totalCatalog recipes in the catalog'
                                    : '${_items.length} recipes loaded',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText:
                                      'Search recipe or ingredient, e.g. adobo, pork...',
                                  prefixIcon: const Icon(Icons.search_rounded),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded),
                                          onPressed: () {
                                            _searchController.clear();
                                            if (_localCatalog.length >= 50) {
                                              _applyLocalBrowse(reset: true);
                                            }
                                            unawaited(_fetchPage(reset: true));
                                          },
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 42,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: _categoryOptions.length,
                          separatorBuilder: (_, index) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final category = _categoryOptions[index];
                            final selected = category == _selectedCategory;
                            return ChoiceChip(
                              label: Text(category),
                              selected: selected,
                              onSelected: (_) {
                                setState(() => _selectedCategory = category);
                                if (_localCatalog.length >= 50) {
                                  _applyLocalBrowse(reset: true);
                                }
                                unawaited(_fetchPage(reset: true));
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                        child: Row(
                          children: [
                            Text(
                              '${_items.length} shown'
                              '${_totalCatalog > 0 ? ' · $_totalCatalog total' : ''}',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            if (showSpinner && _items.isEmpty) ...[
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: cs.primary,
                                ),
                              ),
                            ],
                            const Spacer(),
                            Icon(Icons.workspace_premium_rounded, size: 16, color: cs.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Premium Browse',
                              style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final crossAxisCount =
                            constraints.crossAxisExtent >= 800 ? 3 : 2;
                        return SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                          sliver: SliverGrid(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final recipe = _items[index];
                                return _RecipeBrowseCard(
                                  recipe: recipe,
                                  onOpen: () => _openRecipe(recipe),
                                );
                              },
                              childCount: _items.length,
                            ),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: crossAxisCount == 3 ? 0.8 : 0.68,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RecipeBrowseCard extends StatelessWidget {
  final Recipe recipe;
  final VoidCallback onOpen;

  const _RecipeBrowseCard({required this.recipe, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onOpen,
      child: Ink(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 7,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RecipeImage(
                      recipeId: recipe.id,
                      imageUrl: recipe.imageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      memCacheWidth: 320,
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.28),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.90),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.open_in_new_rounded, size: 13, color: cs.primary),
                            const SizedBox(width: 4),
                            Text(
                              'Open',
                              style: TextStyle(
                                color: cs.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (recipe.category != null && recipe.category!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          recipe.category!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      recipe.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(Icons.bolt_rounded, size: 14, color: cs.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Tap to view details',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
