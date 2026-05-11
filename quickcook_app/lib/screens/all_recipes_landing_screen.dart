import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';

import '../models/recipe.dart';
import '../services/api_service.dart';
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
  final TextEditingController _searchController = TextEditingController();

  List<Recipe> _allRecipes = [];
  List<Recipe> _visibleRecipes = [];
  String _selectedCategory = 'All';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecipes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecipes({bool force = false}) async {
    try {
      final data = await ApiService.fetchRecipes(forceRefresh: force);
      if (!mounted) return;
      setState(() {
        _allRecipes = data;
        _loading = false;
      });
      _applyFilters();
      unawaited(_warmBrowseImageCache(data));
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _warmBrowseImageCache(List<Recipe> recipes) async {
    final ctx = context;
    if (!ctx.mounted) return;
    for (final recipe in recipes.take(12)) {
      final url = recipe.thumbnailUrl;
      if (url == null || url.isEmpty) continue;
      try {
        await precacheImage(
          CachedNetworkImageProvider(url, maxWidth: 320),
          ctx,
        );
      } catch (_) {}
    }
  }

  void _openRecipe(Recipe recipe) {
    // Warm detail API + full image without blocking navigation.
    unawaited(ApiService.fetchRecipeDetail(recipe.id));
    final full = recipe.imageUrl;
    if (full != null && full.isNotEmpty) {
      unawaited(
        precacheImage(
          CachedNetworkImageProvider(full, maxWidth: 1080),
          context,
        ).catchError((_) {}),
      );
    }
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

  List<String> get _categoryOptions {
    final counts = <String, int>{};
    for (final recipe in _allRecipes) {
      final category = recipe.category?.trim();
      if (category == null || category.isEmpty) continue;
      counts[category] = (counts[category] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ['All', ...sorted.take(8).map((e) => e.key)];
  }

  void _applyFilters() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      _visibleRecipes = _allRecipes
          .where((r) {
            final matchesSearch = q.isEmpty || r.name.toLowerCase().contains(q);
            final matchesCategory = _selectedCategory == 'All' ||
                (r.category?.toLowerCase() == _selectedCategory.toLowerCase());
            return matchesSearch && matchesCategory;
          })
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
          onRefresh: () => _loadRecipes(force: true),
          child: _loading
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 180),
                    Center(child: CircularProgressIndicator(color: cs.primary)),
                  ],
                )
              : _visibleRecipes.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 140),
                        Icon(
                          Icons.search_off_rounded,
                          size: 46,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            'No recipes found.',
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    )
                  : CustomScrollView(
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
                                    '${_allRecipes.length} recipes curated for your kitchen',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _searchController,
                                    onChanged: (_) => _applyFilters(),
                                    decoration: const InputDecoration(
                                      hintText: 'Search recipes, e.g. adobo...',
                                      prefixIcon: Icon(Icons.search_rounded),
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
                                    _applyFilters();
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
                                  '${_visibleRecipes.length} recipes',
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
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
                                    final recipe = _visibleRecipes[index];
                                    return _RecipeBrowseCard(
                                      recipe: recipe,
                                      onOpen: () => _openRecipe(recipe),
                                    );
                                  },
                                  childCount: _visibleRecipes.length,
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
    final image = recipe.thumbnailUrl;
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
                child: image != null && image.isNotEmpty
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: image,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            memCacheWidth: 320,
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
                                color: cs.onSurfaceVariant,
                                size: 38,
                              ),
                            ),
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
                      )
                    : Container(
                        color: cs.surfaceContainerLow,
                        child: Icon(
                          Icons.restaurant_menu_rounded,
                          color: cs.onSurfaceVariant,
                          size: 38,
                        ),
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
