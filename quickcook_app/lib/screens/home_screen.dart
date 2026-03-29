import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ FIXED: Added missing import
import 'dart:async';

import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../services/api_service.dart';
import '../services/connectivity_service.dart';
import '../services/notification_service.dart';

import 'login_screen.dart';
import 'recipe_screen.dart';
import 'favorites_screen.dart';
import 'recipe_detail_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // --- CORE STATE ---
  List<Ingredient> allIngredients = [];
  List<Ingredient> filteredIngredients = [];
  List<Recipe> recommendedRecipes = [];
  List<Recipe> recentRecipes = [];

  final TextEditingController searchController = TextEditingController();
  Set<int> selectedIngredients = {};

  bool isLoadingRecipes = false;
  bool isLoadingIngredients = true;
  bool isLoadingRecommendations = true;
  bool isLoadingRecent = false;

  // 🔥 GLOBAL SEARCH STATE
  bool isSearching = false;
  Timer? _debounce;
  Map<String, dynamic> searchResults = {
    "recipes": [],
    "ingredients": [],
    "categories": [],
  };

  bool _isOffline = false;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  @override
  void initState() {
    super.initState();
    _syncOfflineFlag();
    _connSub = Connectivity().onConnectivityChanged.listen((_) {
      _syncOfflineFlag();
    });
    loadIngredients();
    loadRecommendations();
    loadRecent();
  }

  Future<void> _syncOfflineFlag() async {
    final online = await ConnectivityService.isOnline;
    if (mounted) setState(() => _isOffline = !online);
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _debounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  // --- DATA LOADING LOGIC ---

  Future<void> loadRecent() async {
    final prefs = await SharedPreferences.getInstance();

    final snapRaw = prefs.getString('recently_viewed_snapshot');
    if (snapRaw != null) {
      try {
        final decoded = jsonDecode(snapRaw) as List<dynamic>;
        final fromSnap = decoded.map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          return Recipe(
            id: m['id'] is int
                ? m['id'] as int
                : int.tryParse(m['id'].toString()) ?? 0,
            name: m['name']?.toString() ?? 'Recipe',
            instructions: '',
            ingredients: const [],
            imageUrl: m['imageUrl']?.toString() ?? m['image_url']?.toString(),
            category: m['category']?.toString(),
          );
        }).toList();
        if (fromSnap.isNotEmpty && mounted) {
          setState(() => recentRecipes = fromSnap);
        }
      } catch (e) {
        debugPrint('recently_viewed_snapshot: $e');
      }
    }

    final recentIds = prefs.getStringList('recently_viewed') ?? [];
    if (recentIds.isEmpty) {
      if (mounted) setState(() => isLoadingRecent = false);
      return;
    }

    setState(() => isLoadingRecent = true);
    try {
      final ids = recentIds.map((id) => int.parse(id)).toList();
      final data = await ApiService.fetchRecentRecipes(ids);
      if (!mounted) return;
      if (data.isNotEmpty) {
        setState(() {
          recentRecipes = data;
          isLoadingRecent = false;
        });
      } else {
        setState(() => isLoadingRecent = false);
      }
    } catch (e) {
      debugPrint('loadRecent API: $e');
      if (mounted) setState(() => isLoadingRecent = false);
    }
  }

  Future<void> loadRecommendations() async {
    if (recommendedRecipes.isNotEmpty) return;
    try {
      final data = await ApiService.fetchRecommendedRecipes();
      if (!mounted) return;
      setState(() {
        recommendedRecipes = data;
        isLoadingRecommendations = false;
      });
      if (recommendedRecipes.isNotEmpty) {
        await NotificationService.maybeShowTrendingReminder(
          recommendedRecipes.first.name,
        );
      }
    } catch (e) {
      if (mounted) setState(() => isLoadingRecommendations = false);
    }
  }

  Future<void> loadIngredients() async {
    if (allIngredients.isNotEmpty) return;
    try {
      final data = await ApiService.fetchIngredients();
      if (!mounted) return;
      setState(() {
        allIngredients = data;
        filteredIngredients = allIngredients;
        isLoadingIngredients = false;
      });
    } catch (e) {
      if (mounted) setState(() => isLoadingIngredients = false);
    }
  }

  Future<void> navigateToDetail(int recipeId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RecipeDetailScreen(recipeId: recipeId)),
    );
    loadRecent();
  }

  void filterIngredients(String query) {
    if (query.isEmpty) {
      setState(() => filteredIngredients = allIngredients);
      return;
    }
    setState(() {
      filteredIngredients = allIngredients
          .where((i) => i.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  Future<void> performGlobalSearch(String query) async {
    try {
      final result = await ApiService.globalSearch(query);
      if (!mounted) return;
      setState(() {
        searchResults = {
          "recipes": result['recipes'] ?? [],
          "ingredients": result['ingredients'] ?? [],
          "categories": result['categories'] ?? [],
        };
        isSearching = true;
      });
    } catch (e) {
      debugPrint("Search error: $e");
    }
  }

  Future<void> findRecipes() async {
    if (selectedIngredients.isEmpty) return;
    setState(() => isLoadingRecipes = true);
    try {
      final result = await ApiService.matchRecipes(
        selectedIngredients.toList(),
        1,
        null,
      );
      final List<Recipe> recipesList = result["recipes"] ?? [];
      if (!mounted) return;
      setState(() => isLoadingRecipes = false);

      if (recipesList.isEmpty) {
        _showSnackBar("No matching recipes found.", isError: true);
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecipeScreen(
            recipes: recipesList,
            ingredientIds: selectedIngredients.toList(),
          ),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => isLoadingRecipes = false);
      _showSnackBar("Error connecting to server.", isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 400,
        backgroundColor: isError ? Colors.redAccent : cs.inverseSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          message,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: cs.onInverseSurface,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          "QuickCook",
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.favorite_outline_rounded, color: cs.onSurface),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FavoritesScreen()),
            ),
          ),
          IconButton(
            icon: Icon(Icons.person_outline_rounded, color: cs.onSurface),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            onPressed: () async {
              await ApiService.logout();
              if (!mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                Expanded(
                  child: isLoadingIngredients
                      ? Center(
                          child: CircularProgressIndicator(
                            color: cs.primary,
                          ),
                        )
                      : RefreshIndicator(
                          color: cs.primary,
                          onRefresh: () async {
                            await loadIngredients();
                            await loadRecommendations();
                            await loadRecent();
                          },
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 24),

                                if (_isOffline)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 24,
                                      right: 24,
                                      bottom: 16,
                                    ),
                                    child: Material(
                                      color: Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.wifi_off_rounded,
                                              color: Colors.amber.shade900,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                'You are offline. Showing cached recipes and ingredients when available.',
                                                style: TextStyle(
                                                  color: Colors.amber.shade900,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                // 🔥 FIXED: Added null-aware check to prevent crash
                                if (recentRecipes.isNotEmpty) ...[
                                  _buildSectionHeader("Jump Back In"),
                                  const SizedBox(height: 16),
                                  _buildRecentList(),
                                ],

                                _buildRecommendationsSection(),

                                const SizedBox(height: 16),
                                Divider(color: cs.outlineVariant, height: 1),
                                const SizedBox(height: 32),

                                _buildIngredientSelectionSection(),
                              ],
                            ),
                          ),
                        ),
                ),
                _buildBottomActionBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- WIDGET HELPERS ---

  // ✅ FIXED: Added missing method
  Widget _buildSectionHeader(String title) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ FIXED: Added missing method
  Widget _buildRecentList() {
    final cs = Theme.of(context).colorScheme;
    if (isLoadingRecent && recentRecipes.isEmpty) {
      return Center(child: CircularProgressIndicator(color: cs.primary));
    }
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: recentRecipes.length,
        itemBuilder: (context, index) {
          final recipe = recentRecipes[index];
          // Reuse your existing horizontal card logic here
          return GestureDetector(
            onTap: () => navigateToDetail(recipe.id),
            child: Container(
              width: 180,
              margin: EdgeInsets.only(
                left: index == 0 ? 24 : 8,
                right: 8,
                bottom: 16,
              ),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      child: recipe.imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: recipe.imageUrl!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              placeholder: (context, url) =>
                                  Container(color: cs.surfaceContainerLow),
                              errorWidget: (context, url, error) => Container(
                                color: cs.surfaceContainerLow,
                                child: Icon(Icons.restaurant, color: cs.onSurfaceVariant),
                              ),
                            )
                          : Icon(Icons.restaurant, color: cs.onSurfaceVariant),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      recipe.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecommendationsSection() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _buildSectionHeader("Recommended For You"),
        const SizedBox(height: 16),
        if (isLoadingRecommendations)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(color: cs.primary),
            ),
          )
        else if (recommendedRecipes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text(
                "Start viewing recipes to see recommendations!",
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          )
        else
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: recommendedRecipes.length,
              itemBuilder: (context, index) => _buildRecipeCard(
                recommendedRecipes[index],
                index,
                recommendedRecipes.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRecipeCard(Recipe recipe, int index, int total) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => navigateToDetail(recipe.id),
      child: Container(
        width: 180,
        margin: EdgeInsets.only(
          left: index == 0 ? 24 : 8,
          right: index == total - 1 ? 24 : 8,
          bottom: 16,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: recipe.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: recipe.imageUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (context, url) =>
                            Container(color: cs.surfaceContainerLow),
                        errorWidget: (context, url, error) => Container(
                          color: cs.surfaceContainerLow,
                          child: Icon(Icons.restaurant, color: cs.onSurfaceVariant),
                        ),
                      )
                    : Container(
                        color: cs.surfaceContainerLow,
                        child: Icon(Icons.restaurant, color: cs.onSurfaceVariant),
                      ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      recipe.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      recipe.category ?? "Recipe",
                      style: TextStyle(
                        color: cs.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
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

  Widget _buildIngredientSelectionSection() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "What's in your kitchen?",
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Select ingredients to find a recipe.",
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 24),

          if (isSearching) ...[
            ...(searchResults['recipes'] as List? ?? []).map<Widget>(
              (item) => ListTile(
                title: Text(item['name'] ?? 'Unknown Recipe'),
                onTap: () => navigateToDetail(item['id']),
              ),
            ),
            ...(searchResults['ingredients'] as List? ?? []).map<Widget>(
              (item) => ListTile(
                title: Text(item['name'] ?? 'Unknown Ingredient'),
                onTap: () {
                  setState(() {
                    selectedIngredients.add(item['id']);
                    isSearching = false;
                  });
                },
              ),
            ),
          ],

          _buildSearchBar(),
          const SizedBox(height: 24),

          if (!isSearching)
            Wrap(
              spacing: 10,
              runSpacing: 12,
              children: filteredIngredients
                  .map((i) => _buildIngredientChip(i))
                  .toList(),
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: searchController,
      style: TextStyle(color: cs.onSurface),
      onChanged: (value) {
        if (_debounce?.isActive ?? false) _debounce!.cancel();
        _debounce = Timer(const Duration(milliseconds: 400), () {
          if (value.isEmpty) {
            setState(() => isSearching = false);
            filterIngredients("");
          } else {
            performGlobalSearch(value);
          }
        });
      },
      decoration: InputDecoration(
        hintText: "Search ingredients...",
        hintStyle: TextStyle(color: cs.onSurfaceVariant),
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
      ),
    );
  }

  Widget _buildIngredientChip(Ingredient ingredient) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = selectedIngredients.contains(ingredient.id);
    return FilterChip(
      label: Text(
        ingredient.name,
        style: TextStyle(color: isSelected ? cs.primary : cs.onSurface),
      ),
      selected: isSelected,
      onSelected: (val) {
        setState(() {
          if (val) {
            selectedIngredients.add(ingredient.id);
          } else {
            selectedIngredients.remove(ingredient.id);
          }
        });
      },
      selectedColor: cs.primary.withOpacity(0.2),
      checkmarkColor: cs.primary,
      backgroundColor: cs.surfaceContainerHighest,
      side: BorderSide(color: cs.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _buildBottomActionBar() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 60,
        child: ElevatedButton(
          onPressed: selectedIngredients.isEmpty || isLoadingRecipes
              ? null
              : findRecipes,
          style: ElevatedButton.styleFrom(
            backgroundColor: cs.primary,
            foregroundColor: cs.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: isLoadingRecipes
              ? const CircularProgressIndicator(color: Colors.white)
              : Text(
                  selectedIngredients.isEmpty
                      ? "Select ingredients"
                      : "Find Recipes (${selectedIngredients.length})",
                ),
        ),
      ),
    );
  }
}
