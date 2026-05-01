import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/recipe.dart';
import '../services/api_service.dart';
import '../widgets/app_message.dart';
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

  int currentPage = 1;
  bool hasMore = true;
  bool loadingMore = false;
  bool isApplyingFilters = false;
  int _filterRequestToken = 0;

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

  // --- MODERN TEAL & ZINC PALETTE ---
  static const Color primaryBrand = Color(0xFF0D9488);
  static const Color darkSlate = Color(0xFF18181B);
  static const Color bgSoft = Color(0xFFF4F4F5);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE4E4E7);
  static const Color textMain = Color(0xFF27272A);
  static const Color textMuted = Color(0xFF71717A);
  static const Color warningAmber = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    allRecipes = widget.recipes;
    filteredRecipes = widget.recipes;
    loadFavorites();
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
      filteredRecipes = results;
    });
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

  Future<void> _reloadFiltersFromServer() async {
    final requestToken = ++_filterRequestToken;
    setState(() => isApplyingFilters = true);
    try {
      final result = await ApiService.matchRecipes(
        widget.ingredientIds,
        1,
        selectedCategory == "All" ? null : selectedCategory,
        difficulty: selectedDifficulty == "All" ? null : selectedDifficulty,
        maxCookingTime: maxCookingTime,
      );
      if (!mounted || requestToken != _filterRequestToken) return;
      setState(() {
        currentPage = 1;
        allRecipes = List<Recipe>.from(result["recipes"] ?? const <Recipe>[]);
        filteredRecipes = allRecipes;
        hasMore = result["hasMore"] == true;
      });
    } catch (_) {
      // Keep current cards on-screen to avoid perceived "blank loading" on filter taps.
    } finally {
      if (mounted && requestToken == _filterRequestToken) {
        setState(() => isApplyingFilters = false);
      }
    }
  }

  /// CATEGORY FILTER
  Future<void> filterByCategory(String category) async {
    setState(() {
      selectedCategory = category;
    });
    await _reloadFiltersFromServer();
  }

  Future<void> filterByDifficulty(String difficulty) async {
    setState(() {
      selectedDifficulty = difficulty;
    });
    await _reloadFiltersFromServer();
  }

  Future<void> filterByMaxCookingTime(int? minutes) async {
    setState(() {
      maxCookingTime = minutes;
    });
    await _reloadFiltersFromServer();
  }

  /// IMAGE (OPTIMIZED + CACHED + STYLED)
  Widget recipeImage(String? imageUrl) {
    final cs = Theme.of(context).colorScheme;
    if (imageUrl == null || imageUrl.isEmpty) {
      return placeholderImage();
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        height: 220,
        width: double.infinity,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          height: 220,
          color: cs.surfaceContainerLow,
          child: const Center(
            child: CircularProgressIndicator(color: primaryBrand),
          ),
        ),
        errorWidget: (context, url, error) {
          return placeholderImage();
        },
      ),
    );
  }

  Widget placeholderImage() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
      ),
      child: Center(
        child: Icon(Icons.restaurant_menu_rounded, size: 64, color: cs.onSurfaceVariant),
      ),
    );
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
        builder: (_) => RecipeDetailScreen(recipeId: recipe.id),
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
      if (!context.mounted) return;
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
              color: Colors.black.withOpacity(
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
                child: recipe.imageUrl != null && recipe.imageUrl!.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: recipe.imageUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (context, url) => Container(
                          color: cs.surfaceContainerLow,
                          child: Center(
                            child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: cs.surfaceContainerLow,
                          child: Icon(
                            Icons.restaurant_menu_rounded,
                            size: 40,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Container(
                        color: cs.surfaceContainerLow,
                        child: Icon(
                          Icons.restaurant_menu_rounded,
                          size: 40,
                          color: cs.onSurfaceVariant,
                        ),
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
                          color: cs.primary.withOpacity(0.12),
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
                              Icon(
                                Icons.search_off_rounded,
                                size: 48,
                                color: cs.onSurfaceVariant,
                              ),
                              SizedBox(height: 16),
                              Text(
                                "No recipes found matching this filter.",
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: GridView.builder(
                                physics: const BouncingScrollPhysics(),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                itemCount: filteredRecipes.length,
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                  // Slightly wider vs height: compact cards; content uses Spacer so Save aligns.
                                  childAspectRatio: 0.66,
                                ),
                                itemBuilder: (context, index) {
                                  return _buildMatchedRecipeGridCard(filteredRecipes[index]);
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
