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
import '../utils/app_update_check.dart';
import '../widgets/app_message.dart';

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
  List<Recipe> activityRecipes = [];
  List<Recipe> trendingRecipes = [];
  List<String> recentSearches = [];
  List<String> suggestedKeywords = [];
  Map<String, dynamic> cookingInsights = {};
  List<Map<String, dynamic>> smartNotifications = [];

  final TextEditingController searchController = TextEditingController();
  Set<int> selectedIngredients = {};
  List<Map<String, dynamic>> comboSuggestions = [];
  bool cookNowOnly = false;

  bool isLoadingRecipes = false;
  bool isLoadingIngredients = true;
  bool isLoadingRecommendations = true;
  bool isLoadingRecent = false;
  bool isLoadingFeed = false;

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
    loadPersonalizedFeed();
    loadSearchAssist();
    loadSprint9Signals();
    ApiService.syncPendingActivities();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      promptAppUpdateIfNeeded(context);
    });
  }

  Future<void> loadSprint9Signals() async {
    try {
      final insights = await ApiService.fetchCookingInsights();
      final notes = await ApiService.fetchSmartNotifications();
      if (!mounted) return;
      setState(() {
        cookingInsights = Map<String, dynamic>.from(
          insights['data'] as Map? ?? <String, dynamic>{},
        );
        smartNotifications = notes;
      });
      if (notes.isNotEmpty) {
        final first = notes.first;
        final title = first['title']?.toString() ?? 'QuickCook update';
        final body = first['body']?.toString() ?? '';
        await NotificationService.maybeShowSmartMessage(
          title: title,
          body: body,
          key: (first['type']?.toString() ?? 'general').replaceAll(' ', '_'),
        );
      }
    } catch (_) {}
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
          String? firstImageFromList;
          final rawList = m['image_urls'];
          if (rawList is List) {
            for (final v in rawList) {
              final s = v?.toString().trim() ?? '';
              if (s.isNotEmpty) {
                firstImageFromList = s;
                break;
              }
            }
          }
          return Recipe(
            id: m['id'] is int
                ? m['id'] as int
                : int.tryParse(m['id'].toString()) ?? 0,
            name: m['name']?.toString() ?? 'Recipe',
            instructions: '',
            ingredients: const [],
            imageUrl:
                firstImageFromList ??
                m['imageUrl']?.toString() ??
                m['image_url']?.toString(),
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

  Future<void> loadRecommendations({bool force = false}) async {
    if (!force && recommendedRecipes.isNotEmpty) return;
    if (force) {
      ApiService.clearCache('recommendations');
    }
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

  Future<void> loadPersonalizedFeed() async {
    setState(() => isLoadingFeed = true);
    try {
      final raw = await ApiService.fetchPersonalizedHomeFeed();
      List<Recipe> parse(dynamic list) {
        if (list is! List) return [];
        return list
            .map((e) => Recipe.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
      if (!mounted) return;
      setState(() {
        activityRecipes = parse(raw['based_on_your_activity']);
        trendingRecipes = parse(raw['trending']);
        if (recommendedRecipes.isEmpty) {
          recommendedRecipes = parse(raw['recommended_for_you']);
        }
        isLoadingFeed = false;
      });
    } catch (_) {
      if (mounted) setState(() => isLoadingFeed = false);
    }
  }

  Future<void> loadSearchAssist() async {
    try {
      final history = await ApiService.fetchSearchHistory();
      final suggestions = await ApiService.fetchSearchSuggestions('');
      if (!mounted) return;
      setState(() {
        recentSearches = history;
        suggestedKeywords = ((suggestions['suggested_keywords'] as List?) ?? [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
      });
    } catch (_) {}
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
    await loadRecommendations(force: true);
    await loadPersonalizedFeed();
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
      if (!mounted) return;
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      _showSnackBar(msg.isEmpty ? 'Search failed.' : msg, isError: true);
    }
  }

  Future<void> _showMatchEmptyState(dynamic meta) async {
    String? message;
    List<dynamic>? suggestions;
    if (meta is Map) {
      message = meta['message']?.toString();
      final raw = meta['suggestions'];
      if (raw is List<dynamic>) suggestions = raw;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('No close matches'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message ??
                      'Try different ingredients or a broader category filter.',
                ),
                if (suggestions != null && suggestions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Popular picks to try',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  ...suggestions.map((item) {
                    final m = item is Map
                        ? Map<String, dynamic>.from(item)
                        : <String, dynamic>{};
                    final idRaw = m['id'];
                    final id = idRaw is int
                        ? idRaw
                        : int.tryParse(idRaw?.toString() ?? '') ?? 0;
                    final name = m['name']?.toString() ?? 'Recipe';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(name),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        Navigator.pop(ctx);
                        if (id > 0) navigateToDetail(id);
                      },
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> findRecipes() async {
    if (selectedIngredients.isEmpty) return;
    setState(() => isLoadingRecipes = true);
    try {
      List<Recipe> recipesList = const <Recipe>[];
      dynamic meta;
      if (cookNowOnly) {
        recipesList = await ApiService.fetchCookNowRecipes(selectedIngredients.toList());
        meta = {'message': 'Showing ready-to-cook recipes only.'};
      } else {
        final result = await ApiService.matchRecipes(
          selectedIngredients.toList(),
          1,
          null,
        );
        recipesList = List<Recipe>.from(result["recipes"] ?? const <Recipe>[]);
        meta = result['meta'];
      }
      List<String> unmatchedIngredients = const [];
      if (meta is Map) {
        final raw = meta['unmatched_ingredients'];
        if (raw is List) {
          unmatchedIngredients = raw
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }
      if (!mounted) return;
      setState(() => isLoadingRecipes = false);

      if (recipesList.isEmpty) {
        await _showMatchEmptyState(meta);
        return;
      }

      if (!context.mounted) return;
      if (unmatchedIngredients.isNotEmpty) {
        final preview = unmatchedIngredients.take(3).join(', ');
        final suffix = unmatchedIngredients.length > 3 ? ' and more' : '';
        _showSnackBar(
          'No recipes yet for: $preview$suffix. Showing available matches.',
        );
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
      final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      _showSnackBar(
        msg.isEmpty ? 'Could not load matching recipes.' : msg,
        isError: true,
      );
    }
  }

  Future<void> _refreshComboSuggestions() async {
    if (selectedIngredients.isEmpty) {
      if (!mounted) return;
      setState(() => comboSuggestions = []);
      return;
    }
    try {
      final data = await ApiService.fetchIngredientComboSuggestions(
        selectedIngredients.toList(),
      );
      if (!mounted) return;
      setState(() => comboSuggestions = data);
    } catch (_) {}
  }

  Future<void> _openAssistantChat() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _AssistantChatScreen(
          selectedIngredientIds: selectedIngredients.toList(),
          onOpenRecipe: navigateToDetail,
        ),
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    AppMessage.show(
      context,
      text: message,
      type: isError ? AppMessageType.error : AppMessageType.success,
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
                            await loadPersonalizedFeed();
                          },
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 24),
                                _buildHomeHero(),
                                const SizedBox(height: 18),

                                if (_isOffline)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 24,
                                      right: 24,
                                      bottom: 16,
                                    ),
                                    child: Material(
                                      color: cs.brightness == Brightness.dark
                                          ? const Color(0xFF3A2D09)
                                          : Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                      child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.wifi_off_rounded,
                                              color: cs.brightness == Brightness.dark
                                                  ? const Color(0xFFFFD166)
                                                  : Colors.amber.shade900,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                'You are offline. Showing cached recipes and ingredients when available.',
                                                style: TextStyle(
                                                  color: cs.brightness ==
                                                          Brightness.dark
                                                      ? const Color(0xFFFFE39A)
                                                      : Colors.amber.shade900,
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

                                if (cookingInsights.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 24),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: cs.surfaceContainerHigh,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: cs.outlineVariant),
                                      ),
                                      child: Text(
                                        (cookingInsights['habit_message']?.toString() ??
                                                'Personalized insights are ready.')
                                            .trim(),
                                        style: TextStyle(
                                          color: cs.onSurface,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                if (smartNotifications.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  _buildSmartNotificationsStrip(),
                                ],

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
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Row(
              children: List.generate(3, (i) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: i == 0 ? 0 : 6,
                      right: i == 2 ? 0 : 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 11,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: cs.outlineVariant),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 12,
                          width: 72,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
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
              itemBuilder: (context, index) {
                final r = recommendedRecipes[index];
                return _buildRecipeCard(
                  r,
                  index,
                  recommendedRecipes.length,
                  onRecipeTap: () {
                    ApiService.postRecommendationFeedback(r.id, 'click');
                    navigateToDetail(r.id);
                  },
                );
              },
            ),
          ),
        if (!isLoadingFeed && trendingRecipes.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildSectionHeader("Trending"),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: trendingRecipes.length,
              itemBuilder: (context, index) => _buildRecipeCard(
                trendingRecipes[index],
                index,
                trendingRecipes.length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHomeHero() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primary.withOpacity(0.18),
              cs.tertiary.withOpacity(0.13),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                Theme.of(context).brightness == Brightness.dark ? 0.28 : 0.05,
              ),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surface.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Icon(Icons.auto_awesome_rounded, color: cs.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Smart Cooking Dashboard",
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "Find recipes faster with personalized picks, pantry matching, and AI cooking help.",
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _heroPill(
                  icon: Icons.favorite_outline_rounded,
                  label: "${recommendedRecipes.length} recommendations",
                ),
                _heroPill(
                  icon: Icons.local_fire_department_outlined,
                  label: "${trendingRecipes.length} trending",
                ),
                _heroPill(
                  icon: Icons.history_rounded,
                  label: "${recentRecipes.length} recent",
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroPill({required IconData icon, required String label}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartNotificationsStrip() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        height: 96,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: smartNotifications.length,
          itemBuilder: (context, index) {
            final item = smartNotifications[index];
            final title = item['title']?.toString().trim();
            final body = item['body']?.toString().trim();
            return Container(
              width: 280,
              margin: EdgeInsets.only(
                right: index == smartNotifications.length - 1 ? 0 : 10,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.notifications_active_outlined, color: cs.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (title == null || title.isEmpty) ? 'QuickCook Update' : title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          (body == null || body.isEmpty) ? 'New suggestions are ready for you.' : body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12.5,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRecipeCard(
    Recipe recipe,
    int index,
    int total, {
    VoidCallback? onRecipeTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onRecipeTap ?? () => navigateToDetail(recipe.id),
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary.withOpacity(0.16),
                  cs.tertiary.withOpacity(0.12),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cs.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(
                    Theme.of(context).brightness == Brightness.dark ? 0.26 : 0.05,
                  ),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "What's in your kitchen?",
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _openAssistantChat,
                      tooltip: 'Open AI Assistant',
                      icon: Icon(Icons.smart_toy_outlined, color: cs.primary),
                      style: IconButton.styleFrom(
                        backgroundColor: cs.surface.withOpacity(0.85),
                        side: BorderSide(color: cs.outlineVariant),
                        padding: const EdgeInsets.all(10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  "Select ingredients to find a recipe.",
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _miniBadge(cs, Icons.auto_awesome_rounded, 'AI Assisted'),
                    _miniBadge(cs, Icons.speed_rounded, 'Fast Matching'),
                    _miniBadge(cs, Icons.tune_rounded, 'Smart Filters'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (selectedIngredients.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      "${selectedIngredients.length} selected",
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        selectedIngredients.clear();
                      });
                      _refreshComboSuggestions();
                    },
                    icon: const Icon(Icons.clear_all_rounded, size: 18),
                    label: const Text("Clear Selected"),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (selectedIngredients.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FilterChip(
                    label: const Text('Cook Now Mode'),
                    selected: cookNowOnly,
                    onSelected: (v) => setState(() => cookNowOnly = v),
                  ),
                  if (comboSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Try adding: ${comboSuggestions.take(3).map((e) => e['name']).join(', ')}',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          const SizedBox(height: 6),

          if (isSearching) ...[
            ...(searchResults['recipes'] as List? ?? []).map<Widget>(
              (item) => ListTile(
                tileColor: cs.surfaceContainerHigh,
                textColor: cs.onSurface,
                iconColor: cs.onSurfaceVariant,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                title: Text(item['name'] ?? 'Unknown Recipe'),
                trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                onTap: () => navigateToDetail(item['id']),
              ),
            ),
            ...(searchResults['ingredients'] as List? ?? []).map<Widget>(
              (item) => ListTile(
                tileColor: cs.surfaceContainerHigh,
                textColor: cs.onSurface,
                iconColor: cs.onSurfaceVariant,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                title: Text(item['name'] ?? 'Unknown Ingredient'),
                trailing: Icon(Icons.add_rounded, color: cs.primary),
                onTap: () {
                  setState(() {
                    selectedIngredients.add(item['id']);
                    isSearching = false;
                  });
                  _refreshComboSuggestions();
                },
              ),
            ),
          ],

          _buildSearchBar(),
          const SizedBox(height: 24),

          if (!isSearching)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 12,
                children: filteredIngredients
                    .map((i) => _buildIngredientChip(i))
                    .toList(),
              ),
            ),
          if (!isSearching &&
              (recentSearches.isNotEmpty || suggestedKeywords.isNotEmpty)) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  "Search Suggestions",
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...recentSearches.take(4).map(
                  (q) => ActionChip(
                    backgroundColor: cs.surfaceContainerHigh,
                    labelStyle: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(color: cs.outlineVariant),
                    label: Text(q),
                    onPressed: () {
                      searchController.text = q;
                      performGlobalSearch(q);
                    },
                  ),
                ),
                ...suggestedKeywords.take(6).map(
                  (q) => ActionChip(
                    backgroundColor: cs.surfaceContainerHigh,
                    labelStyle: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    side: BorderSide(color: cs.outlineVariant),
                    label: Text(q),
                    onPressed: () {
                      searchController.text = q;
                      performGlobalSearch(q);
                    },
                  ),
                ),
              ],
            ),
          ],
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
            ApiService.fetchSearchSuggestions(value).then((s) {
              if (!mounted) return;
              setState(() {
                suggestedKeywords = ((s['suggested_keywords'] as List?) ?? [])
                    .map((e) => e.toString())
                    .where((e) => e.isNotEmpty)
                    .toList();
              });
            });
          }
        });
      },
      decoration: InputDecoration(
        hintText: "Search ingredients...",
        hintStyle: TextStyle(color: cs.onSurfaceVariant),
        filled: true,
        fillColor: cs.surfaceContainerHigh,
        prefixIcon: Icon(Icons.search_rounded, color: cs.primary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: cs.primary, width: 1.8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      ),
    );
  }

  Widget _buildIngredientChip(Ingredient ingredient) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = selectedIngredients.contains(ingredient.id);
    return FilterChip(
      label: Text(
        ingredient.name,
        style: TextStyle(
          color: isSelected ? cs.onPrimary : cs.onSurface,
          fontWeight: FontWeight.w700,
        ),
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
        _refreshComboSuggestions();
      },
      selectedColor: cs.primary,
      checkmarkColor: cs.onPrimary,
      backgroundColor: cs.surfaceContainerHigh,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selectedIngredients.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                cookNowOnly
                    ? "Cook Now mode is on: only full ingredient matches."
                    : "Smart match mode: shows best available recipes.",
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: selectedIngredients.isEmpty || isLoadingRecipes
                      ? [cs.surfaceContainerHighest, cs.surfaceContainerHighest]
                      : [cs.primary, cs.secondary],
                ),
                boxShadow: [
                  if (!(selectedIngredients.isEmpty || isLoadingRecipes))
                    BoxShadow(
                      color: cs.primary.withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                ],
              ),
              child: ElevatedButton(
                onPressed: selectedIngredients.isEmpty || isLoadingRecipes
                    ? null
                    : findRecipes,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: cs.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: isLoadingRecipes
                    ? CircularProgressIndicator(color: cs.onPrimary)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 18,
                            color: selectedIngredients.isEmpty
                                ? cs.onSurfaceVariant
                                : cs.onPrimary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            selectedIngredients.isEmpty
                                ? "Select ingredients"
                                : "Find Recipes (${selectedIngredients.length})",
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: selectedIngredients.isEmpty
                                  ? cs.onSurfaceVariant
                                  : cs.onPrimary,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniBadge(ColorScheme cs, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantChatScreen extends StatefulWidget {
  final List<int> selectedIngredientIds;
  final Future<void> Function(int recipeId) onOpenRecipe;

  const _AssistantChatScreen({
    required this.selectedIngredientIds,
    required this.onOpenRecipe,
  });

  @override
  State<_AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<_AssistantChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _messages.add({
      'role': 'bot',
      'text':
          'Hi! I am your QuickCook assistant. Ask me about recipes, ingredients, substitutions, cook-now, and app features.',
      'suggestions': const <Map<String, dynamic>>[],
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _typing) return;
    _controller.clear();
    setState(() {
      _messages.add({
        'role': 'user',
        'text': text,
        'suggestions': const <Map<String, dynamic>>[],
      });
      _typing = true;
    });
    _scrollToBottom();

    try {
      final res = await ApiService.askCookingAssistant(
        message: text,
        ingredientIds: widget.selectedIngredientIds,
      );
      final reply = (res['reply']?.toString() ?? 'I am still learning that one.').trim();
      final rawSuggestions = res['suggestions'];
      List<Map<String, dynamic>> suggestions = const [];
      if (rawSuggestions is List) {
        suggestions = rawSuggestions
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((m) => (m['id']?.toString().isNotEmpty ?? false))
            .toList();
      }
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'bot',
          'text': reply.isEmpty ? 'I am still learning that one.' : reply,
          'suggestions': suggestions,
        });
        _typing = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'bot',
          'text': 'Sorry, I cannot answer that right now. Please try again.',
          'suggestions': const <Map<String, dynamic>>[],
        });
        _typing = false;
      });
      _scrollToBottom();
      debugPrint('assistant chat: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Cooking Assistant'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      backgroundColor: cs.surface,
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              itemCount: _messages.length + (_typing ? 1 : 0),
              itemBuilder: (context, index) {
                if (_typing && index == _messages.length) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Assistant is typing...',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  );
                }
                final m = _messages[index];
                final isUser = m['role'] == 'user';
                final suggestions = (m['suggestions'] as List?) ?? const [];
                return Column(
                  crossAxisAlignment:
                      isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 320),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isUser ? cs.primary : cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                          border: isUser
                              ? null
                              : Border.all(color: cs.outlineVariant),
                        ),
                        child: Text(
                          m['text']?.toString() ?? '',
                          style: TextStyle(
                            color: isUser ? cs.onPrimary : cs.onSurface,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                    if (!isUser && suggestions.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: suggestions.map((s) {
                          final id = int.tryParse(s['id']?.toString() ?? '') ?? 0;
                          final name = s['name']?.toString() ?? 'Recipe';
                          return ActionChip(
                            label: Text(name),
                            backgroundColor: cs.surfaceContainerHigh,
                            side: BorderSide(color: cs.outlineVariant),
                            onPressed: id <= 0
                                ? null
                                : () async {
                                    await widget.onOpenRecipe(id);
                                    if (!mounted) return;
                                    Navigator.pop(context);
                                  },
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: cs.outlineVariant)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onSubmitted: (_) => _sendMessage(),
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Ask about recipes, ingredients, substitutions...',
                        filled: true,
                        fillColor: cs.surfaceContainerHigh,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: _typing ? null : _sendMessage,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
