import 'dart:async';

import 'package:flutter/material.dart';
import '../models/recipe.dart';
import '../services/api_service.dart';
import '../widgets/app_message.dart';
import '../widgets/recipe_image.dart';
import 'recipe_detail_screen.dart';

class RecipeScreen extends StatefulWidget {
  final List<Recipe> recipes;
  final List<int> ingredientIds;

  const RecipeScreen({
    super.key,
    required this.recipes,
    required this.ingredientIds,
  });

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  Set<int> savedRecipes = {};
  Set<int> savingFavoriteIds = {};
  bool loadingFavorites = true;

  final TextEditingController searchController = TextEditingController();

  List<Recipe> allRecipes = [];
  List<Recipe> filteredRecipes = [];

  /// Master "no-filter" superset used for instant client-side filtering. We
  /// fall back to network only when a filter combination has never been seen.
  List<Recipe> _baselineRecipes = [];

  /// Cache of recipe lists per filter signature so re-tapping a chip is
  /// truly instant on subsequent taps.
  final Map<String, List<Recipe>> _filterCache = {};
  final Map<String, bool> _filterHasMore = {};

  int currentPage = 1;
  bool hasMore = true;
  bool loadingMore = false;
  bool isApplyingFilters = false;
  bool _initialMatchPending = false;
  int _filterRequestToken = 0;

  String get _filterKey =>
      '$selectedCategory|$selectedDifficulty|${maxCookingTime ?? 0}';

  bool _matchesCurrentFilters(Recipe r) {
    if (selectedCategory != 'All' &&
        (r.category ?? '').toLowerCase() != selectedCategory.toLowerCase()) {
      return false;
    }
    if (selectedDifficulty != 'All' &&
        (r.difficulty ?? '').toLowerCase() !=
            selectedDifficulty.toLowerCase()) {
      return false;
    }
    if (maxCookingTime != null &&
        maxCookingTime! > 0 &&
        (r.cookingTimeMinutes ?? 0) > maxCookingTime!) {
      return false;
    }
    return true;
  }

  /// CATEGORY FILTER
  List<String> categories = [
    "All",
    "Breakfast",
    "Lunch",
    "Dinner",
    "Dessert",
    "Snack",
  ];

  String selectedCategory = "All";
  String selectedDifficulty = "All";
  int? maxCookingTime;
  String selectedSort = "Recommended";

  // --- MODERN TEAL & ZINC PALETTE ---
  static const Color primaryBrand = Color(0xFFC2410C);
  static const Color warningAmber = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    allRecipes = widget.recipes;
    filteredRecipes = widget.recipes;
    _baselineRecipes = widget.recipes;
    // Seed the cache so the default ("All") chip is instant from the start.
    _filterCache['All|All|0'] = widget.recipes;
    loadFavorites();
    // If the screen was opened with an empty seed (instant-navigation path
    // from Home), kick off the actual /match-recipes fetch in the background.
    // The grid stays mounted; results stream in when the API responds.
    if (widget.recipes.isEmpty) {
      _initialMatchPending = true;
      _silentRefreshCurrentFilter('All|All|0').whenComplete(() {
        if (mounted) setState(() => _initialMatchPending = false);
      });
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadFavorites() async {
    try {
      final favorites = await ApiService.fetchFavoriteIds();
      if (!mounted) return;
      setState(() {
        savedRecipes = favorites;
        loadingFavorites = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingFavorites = false;
      });
    }
  }

  /// SEARCH FILTER
  void filterRecipes(String query) {
    final results = allRecipes.where((recipe) {
      return recipe.name.toLowerCase().contains(query.toLowerCase());
    }).toList();

    setState(() {
      filteredRecipes = _sortRecipes(results);
    });
  }

  List<Recipe> _sortRecipes(List<Recipe> input) {
    final list = List<Recipe>.from(input);
    switch (selectedSort) {
      case 'Fastest':
        list.sort((a, b) => (a.cookingTimeMinutes ?? 999).compareTo(b.cookingTimeMinutes ?? 999));
        break;
      case 'Top Rated':
        list.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
        break;
      case 'A-Z':
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      default:
        break;
    }
    return list;
  }

  /// LOAD MORE RECIPES
  Future<void> loadMore() async {
    if (!hasMore || loadingMore) return;

    setState(() {
      loadingMore = true;
    });

    currentPage++;

    final result = await ApiService.matchRecipes(
      widget.ingredientIds,
      currentPage,
      selectedCategory == "All" ? null : selectedCategory,
      difficulty: selectedDifficulty == "All" ? null : selectedDifficulty,
      maxCookingTime: maxCookingTime,
    );

    setState(() {
      allRecipes.addAll(result["recipes"]);
      filteredRecipes = allRecipes;
      hasMore = result["hasMore"];
      loadingMore = false;
    });
  }

  /// Applies the currently selected filter combination immediately, using
  /// (in priority order):
  ///   1) the cached server result for this exact combo, OR
  ///   2) a client-side filter of the baseline list
  ///
  /// Then fires a silent server refresh so the cache stays accurate. The
  /// previous code awaited the network on every chip tap, which is what was
  /// making chip changes feel slow.
  void _applyFiltersInstant() {
    final key = _filterKey;
    final cached = _filterCache[key];
    final List<Recipe> next = cached ??
        _baselineRecipes.where(_matchesCurrentFilters).toList();

    setState(() {
      currentPage = 1;
      allRecipes = List<Recipe>.from(next);
      filteredRecipes = _sortRecipes(allRecipes);
      hasMore = _filterHasMore[key] ?? (cached == null);
      isApplyingFilters = false;
    });

    unawaited(_silentRefreshCurrentFilter(key));
  }

  Future<void> _silentRefreshCurrentFilter(String key) async {
    final requestToken = ++_filterRequestToken;
    try {
      final result = await ApiService.matchRecipes(
        widget.ingredientIds,
        1,
        selectedCategory == "All" ? null : selectedCategory,
        difficulty: selectedDifficulty == "All" ? null : selectedDifficulty,
        maxCookingTime: maxCookingTime,
      );
      if (!mounted || requestToken != _filterRequestToken) return;
      final fresh = List<Recipe>.from(result["recipes"] ?? const <Recipe>[]);
      _filterCache[key] = fresh;
      _filterHasMore[key] = result["hasMore"] == true;
      // Keep an unfiltered superset so other chips can also filter instantly.
      if (key == 'All|All|0') {
        _baselineRecipes = fresh;
      }
      // Only swap the visible list if the user hasn't navigated to a different
      // filter while we were fetching.
      if (key != _filterKey) return;
      // If lists are identical content-wise, skip rebuild to avoid flicker.
      if (_recipeListsEqual(fresh, allRecipes)) return;
      setState(() {
        allRecipes = fresh;
        filteredRecipes = _sortRecipes(allRecipes);
        hasMore = _filterHasMore[key] == true;
      });
    } catch (_) {
      // Keep current cards on-screen — silent refresh, never block the UI.
    }
  }

  bool _recipeListsEqual(List<Recipe> a, List<Recipe> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  /// CATEGORY FILTER
  void filterByCategory(String category) {
    setState(() => selectedCategory = category);
    _applyFiltersInstant();
  }

  void filterByDifficulty(String difficulty) {
    setState(() => selectedDifficulty = difficulty);
    _applyFiltersInstant();
  }

  void filterByMaxCookingTime(int? minutes) {
    setState(() => maxCookingTime = minutes);
    _applyFiltersInstant();
  }

  void updateSort(String sort) {
    setState(() {
      selectedSort = sort;
      filteredRecipes = _sortRecipes(filteredRecipes);
    });
  }

  /// ⭐ RATING STARS
  Widget ratingStars(double? rating) {
    final cs = Theme.of(context).colorScheme;
    if (rating == null || rating == 0) {
      return Text(
        "No ratings yet",
        style: TextStyle(
          fontSize: 13,
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Row(
      children: [
        ...List.generate(5, (index) {
          return Icon(
            index < rating.round()
                ? Icons.star_rounded
                : Icons.star_border_rounded,
            size: 18,
            color: warningAmber,
          );
        }),
        const SizedBox(width: 8),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _metaChip(String text, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, size: 12, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRecipeDetail(Recipe recipe) async {
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            RecipeDetailScreen(recipeId: recipe.id, initialRecipe: recipe),
      ),
    );
    // Don't block navigation on analytics calls.
    unawaited(ApiService.logActivity("view_recipe", recipe.id));
  }

  Future<void> _saveRecipeToFavorites(Recipe recipe) async {
    if (savedRecipes.contains(recipe.id) || savingFavoriteIds.contains(recipe.id)) return;
    setState(() {
      savingFavoriteIds.add(recipe.id);
      // Optimistic update for instant UI feedback.
      savedRecipes.add(recipe.id);
    });
    try {
      await ApiService.addToFavorites(recipe.id);
      unawaited(ApiService.postRecommendationFeedback(recipe.id, 'save'));
      unawaited(ApiService.logActivity("favorite_recipe", recipe.id));
      if (!mounted) return;
      AppMessage.show(
        context,
        text: "Saved to favorites",
        type: AppMessageType.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        savedRecipes.remove(recipe.id);
      });
      AppMessage.show(
        context,
        text: e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''),
        type: AppMessageType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          savingFavoriteIds.remove(recipe.id);
        });
      }
    }
  }

  Widget _buildMatchedRecipeGridCard(Recipe recipe) {
    final cs = Theme.of(context).colorScheme;
    final isSaved = savedRecipes.contains(recipe.id);
    final isSaving = savingFavoriteIds.contains(recipe.id);
    return GestureDetector(
      onTap: () => _openRecipeDetail(recipe),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha:
                Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.05,
              ),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                child: RecipeImage(
                  recipeId: recipe.id,
                  imageUrl: recipe.imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  memCacheWidth: 320,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (recipe.category != null && recipe.category!.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          recipe.category!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    if (recipe.category != null && recipe.category!.trim().isNotEmpty)
                      const SizedBox(height: 6),
                    SizedBox(
                      height: 34,
                      child: Text(
                        recipe.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (recipe.cookingTimeMinutes != null || recipe.difficulty != null)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (recipe.difficulty != null)
                            Expanded(
                              child: _metaChip(
                                recipe.difficulty!.toUpperCase(),
                                Icons.speed_rounded,
                              ),
                            ),
                          if (recipe.difficulty != null &&
                              recipe.cookingTimeMinutes != null)
                            const SizedBox(width: 6),
                          if (recipe.cookingTimeMinutes != null)
                            Expanded(
                              child: _metaChip(
                                '${recipe.cookingTimeMinutes} min',
                                Icons.timer_outlined,
                              ),
                            ),
                        ],
                      ),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 36,
                      child: ElevatedButton.icon(
                        onPressed: (isSaved || isSaving)
                            ? null
                            : () => _saveRecipeToFavorites(recipe),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isSaved ? cs.surfaceContainerLow : cs.primary,
                          foregroundColor: isSaved ? cs.onSurfaceVariant : cs.onPrimary,
                          disabledBackgroundColor: cs.surfaceContainerLow,
                          disabledForegroundColor: cs.onSurfaceVariant,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: Icon(
                          isSaved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 16,
                        ),
                        label: Text(
                          isSaved ? 'Saved' : 'Save',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
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

  Widget _compactFilterDropdown<T>({
    required ColorScheme cs,
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: child,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: cs.onSurface),
        centerTitle: false,
        title: Text(
          "Matched Recipes",
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: -0.5,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: cs.outlineVariant, height: 1),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 800,
            ), // 🌿 WEB RESPONSIVE
            child: Column(
              children: [
                /// SEARCH FIELD
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
                  child: TextField(
                    controller: searchController,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: "Search your matches...",
                      hintStyle: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      filled: true,
                      fillColor: cs.surfaceContainerHigh,
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: cs.onSurfaceVariant,
                        size: 22,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: primaryBrand,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                    ),
                    onChanged: filterRecipes,
                  ),
                ),

                /// CATEGORY FILTER PIPS
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      final isSelected = selectedCategory == category;

                      return GestureDetector(
                        onTap: () => filterByCategory(category),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? primaryBrand : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isSelected ? primaryBrand : cs.outlineVariant,
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            category,
                            style: TextStyle(
                              color: isSelected ? Colors.white : cs.onSurfaceVariant,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _compactFilterDropdown(
                          cs: cs,
                          label: 'Difficulty',
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              isDense: true,
                              value: selectedDifficulty,
                              borderRadius: BorderRadius.circular(12),
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              items: const [
                                DropdownMenuItem(value: 'All', child: Text('All')),
                                DropdownMenuItem(value: 'easy', child: Text('Easy')),
                                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                                DropdownMenuItem(value: 'hard', child: Text('Hard')),
                              ],
                              onChanged: (v) {
                                if (v != null) filterByDifficulty(v);
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _compactFilterDropdown(
                          cs: cs,
                          label: 'Max time',
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int?>(
                              isExpanded: true,
                              isDense: true,
                              value: maxCookingTime,
                              borderRadius: BorderRadius.circular(12),
                              hint: Text(
                                'Any',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              items: const [
                                DropdownMenuItem<int?>(value: null, child: Text('Any')),
                                DropdownMenuItem<int?>(value: 20, child: Text('≤ 20 min')),
                                DropdownMenuItem<int?>(value: 30, child: Text('≤ 30 min')),
                                DropdownMenuItem<int?>(value: 45, child: Text('≤ 45 min')),
                                DropdownMenuItem<int?>(value: 60, child: Text('≤ 60 min')),
                              ],
                              onChanged: (v) => filterByMaxCookingTime(v),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _compactFilterDropdown(
                          cs: cs,
                          label: 'Sort',
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              isDense: true,
                              value: selectedSort,
                              borderRadius: BorderRadius.circular(12),
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Recommended', child: Text('Recommended')),
                                DropdownMenuItem(value: 'Top Rated', child: Text('Top Rated')),
                                DropdownMenuItem(value: 'Fastest', child: Text('Fastest')),
                                DropdownMenuItem(value: 'A-Z', child: Text('A-Z')),
                              ],
                              onChanged: (v) {
                                if (v != null) updateSort(v);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                if (isApplyingFilters)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      borderRadius: BorderRadius.circular(999),
                      color: cs.primary,
                      backgroundColor: cs.surfaceContainerHigh,
                    ),
                  ),
                if (isApplyingFilters) const SizedBox(height: 8),

                /// RECIPE GRID
                Expanded(
                  child: filteredRecipes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_initialMatchPending) ...[
                                const SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: primaryBrand,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  "Searching for recipes…",
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ] else ...[
                                Icon(
                                  Icons.search_off_rounded,
                                  size: 48,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  "No recipes found matching this filter.",
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final gridCount = constraints.maxWidth >= 760 ? 3 : 2;
                                  return GridView.builder(
                                physics: const BouncingScrollPhysics(),
                                cacheExtent: 600,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                itemCount: filteredRecipes.length,
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: gridCount,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: gridCount == 3 ? 0.72 : 0.58,
                                ),
                                itemBuilder: (context, index) {
                                  return _buildMatchedRecipeGridCard(filteredRecipes[index]);
                                },
                              );
                                },
                              ),
                            ),
                            if (hasMore)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: OutlinedButton(
                                    onPressed: loadingMore ? null : loadMore,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: cs.onSurface,
                                      side: BorderSide(
                                        color: cs.outlineVariant,
                                        width: 1.5,
                                      ),
                                      backgroundColor: cs.surfaceContainerHigh,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: loadingMore
                                        ? SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.4,
                                              color: cs.primary,
                                            ),
                                          )
                                        : const Text(
                                            "Load More Recipes",
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 15,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
