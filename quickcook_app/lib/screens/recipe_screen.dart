import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/recipe.dart';
import '../services/api_service.dart';
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
  bool loadingFavorites = true;

  final TextEditingController searchController = TextEditingController();

  List<Recipe> allRecipes = [];
  List<Recipe> filteredRecipes = [];

  int currentPage = 1;
  bool hasMore = true;
  bool loadingMore = false;

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
    );

    setState(() {
      allRecipes.addAll(result["recipes"]);
      filteredRecipes = allRecipes;
      hasMore = result["hasMore"];
      loadingMore = false;
    });
  }

  /// CATEGORY FILTER
  Future<void> filterByCategory(String category) async {
    setState(() {
      selectedCategory = category;
      currentPage = 1;
      allRecipes.clear();
      filteredRecipes.clear();
      hasMore = true;
    });

    final result = await ApiService.matchRecipes(
      widget.ingredientIds,
      currentPage,
      category == "All" ? null : category,
    );

    setState(() {
      allRecipes = result["recipes"];
      filteredRecipes = result["recipes"];
      hasMore = result["hasMore"];
    });
  }

  /// IMAGE (OPTIMIZED + CACHED + STYLED)
  Widget recipeImage(String? imageUrl) {
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
          color: bgSoft,
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
    return Container(
      height: 220,
      width: double.infinity,
      decoration: const BoxDecoration(
        color: bgSoft,
        borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
      ),
      child: const Center(
        child: Icon(Icons.restaurant_menu_rounded, size: 64, color: textMuted),
      ),
    );
  }

  /// ⭐ RATING STARS
  Widget ratingStars(double? rating) {
    if (rating == null || rating == 0) {
      return const Text(
        "No ratings yet",
        style: TextStyle(
          fontSize: 13,
          color: textMuted,
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
          style: const TextStyle(
            color: textMain,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgSoft,
      appBar: AppBar(
        backgroundColor: surfaceWhite,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: textMain),
        centerTitle: false,
        title: const Text(
          "Matched Recipes",
          style: TextStyle(
            color: textMain,
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: -0.5,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: borderLight, height: 1),
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
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                  child: TextField(
                    controller: searchController,
                    style: const TextStyle(
                      color: textMain,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: "Search your matches...",
                      hintStyle: const TextStyle(
                        color: textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                      filled: true,
                      fillColor: surfaceWhite,
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: textMuted,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: borderLight),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: borderLight),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: primaryBrand,
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onChanged: filterRecipes,
                  ),
                ),

                /// CATEGORY FILTER PIPS
                SizedBox(
                  height: 48,
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
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: isSelected ? primaryBrand : surfaceWhite,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isSelected ? primaryBrand : borderLight,
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            category,
                            style: TextStyle(
                              color: isSelected ? Colors.white : textMuted,
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),

                /// RECIPE LIST
                Expanded(
                  child: filteredRecipes.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.search_off_rounded,
                                size: 48,
                                color: textMuted,
                              ),
                              SizedBox(height: 16),
                              Text(
                                "No recipes found matching this filter.",
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          itemCount: filteredRecipes.length + (hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            // Load More Button at the end
                            if (index == filteredRecipes.length) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  top: 16,
                                  bottom: 40,
                                ),
                                child: SizedBox(
                                  height: 56,
                                  child: OutlinedButton(
                                    onPressed: loadMore,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: textMain,
                                      side: const BorderSide(
                                        color: borderLight,
                                        width: 1.5,
                                      ),
                                      backgroundColor: surfaceWhite,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: loadingMore
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: primaryBrand,
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
                              );
                            }

                            final recipe = filteredRecipes[index];
                            final isSaved = savedRecipes.contains(recipe.id);

                            return GestureDetector(
                              onTap: () async {
                                await ApiService.logActivity(
                                  "view_recipe",
                                  recipe.id,
                                );
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        RecipeDetailScreen(recipeId: recipe.id),
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 24),
                                decoration: BoxDecoration(
                                  color: surfaceWhite,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(color: borderLight),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.03),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    recipeImage(recipe.imageUrl),
                                    Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Title & Category Row
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  recipe.name,
                                                  style: const TextStyle(
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.w900,
                                                    color: textMain,
                                                    letterSpacing: -0.5,
                                                    height: 1.2,
                                                  ),
                                                ),
                                              ),
                                              if (recipe.category != null) ...[
                                                const SizedBox(width: 16),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 6,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: primaryBrand
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    recipe.category!,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: primaryBrand,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),

                                          const SizedBox(height: 12),
                                          ratingStars(recipe.rating),
                                          const SizedBox(height: 24),

                                          // Ingredients snippet
                                          const Text(
                                            "Key Ingredients",
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: textMain,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          ...recipe.ingredients
                                              .take(4)
                                              .map(
                                                (ingredient) => Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        bottom: 6,
                                                      ),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Text(
                                                        "• ",
                                                        style: TextStyle(
                                                          color: primaryBrand,
                                                          fontWeight:
                                                              FontWeight.w900,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Text(
                                                          ingredient,
                                                          style:
                                                              const TextStyle(
                                                                color:
                                                                    textMuted,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                fontSize: 14,
                                                                height: 1.3,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                          if (recipe.ingredients.length > 4)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Text(
                                                "+ ${recipe.ingredients.length - 4} more ingredients...",
                                                style: const TextStyle(
                                                  color: textMuted,
                                                  fontStyle: FontStyle.italic,
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),

                                          const SizedBox(height: 32),

                                          // Action Button
                                          SizedBox(
                                            width: double.infinity,
                                            height: 56,
                                            child: ElevatedButton.icon(
                                              onPressed: isSaved
                                                  ? null
                                                  : () async {
                                                      await ApiService.addToFavorites(
                                                        recipe.id,
                                                      );
                                                      await ApiService.logActivity(
                                                        "favorite_recipe",
                                                        recipe.id,
                                                      );

                                                      setState(() {
                                                        savedRecipes.add(
                                                          recipe.id,
                                                        );
                                                      });

                                                      ScaffoldMessenger.of(
                                                        context,
                                                      ).showSnackBar(
                                                        SnackBar(
                                                          behavior:
                                                              SnackBarBehavior
                                                                  .floating,
                                                          backgroundColor:
                                                              darkSlate,
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          content: const Row(
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .favorite_rounded,
                                                                color:
                                                                    primaryBrand,
                                                                size: 20,
                                                              ),
                                                              SizedBox(
                                                                width: 12,
                                                              ),
                                                              Text(
                                                                "Saved to favorites",
                                                                style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      );
                                                    },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: isSaved
                                                    ? bgSoft
                                                    : primaryBrand,
                                                foregroundColor: isSaved
                                                    ? textMuted
                                                    : Colors.white,
                                                elevation: 0,
                                                disabledBackgroundColor: bgSoft,
                                                disabledForegroundColor:
                                                    textMuted,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                              ),
                                              icon: Icon(
                                                isSaved
                                                    ? Icons.favorite_rounded
                                                    : Icons
                                                          .favorite_border_rounded,
                                                size: 20,
                                              ),
                                              label: Text(
                                                isSaved
                                                    ? "Saved to Favorites"
                                                    : "Save to Favorites",
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
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
                            );
                          },
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
