import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../models/admin_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import 'api_host_config.dart';
import 'connectivity_service.dart';
import 'offline_cache_service.dart';
import 'performance_reporter.dart';
import 'app_logger.dart';
import '../utils/recipe_image_resolver.dart';

class ApiService {
  static String? token;
  /// Longer in debug so slow Docker / first cold requests do not look like "cannot connect".
  static Duration get _httpTimeout =>
      kDebugMode ? const Duration(seconds: 20) : const Duration(seconds: 8);
  static SharedPreferences? _prefs;
  static String? _authToken;

  static Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  static final Map<String, dynamic> _cache = {};
  static Future<List<Recipe>>? _recipesInFlight;
  static Future<List<Recipe>>? _recommendationsInFlight;
  static DateTime? _recipesFetchedAt;
  static const Duration _recipesCacheTtl = Duration(minutes: 2);

  static Future<Uint8List> _prepareRecipeImageBytes(XFile file) async {
    final original = await file.readAsBytes();
    if (kIsWeb || original.lengthInBytes <= 1024 * 1024) return original;
    try {
      final compressed = await FlutterImageCompress.compressWithList(
        original,
        minWidth: 1280,
        minHeight: 1280,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      if (compressed.isNotEmpty && compressed.lengthInBytes < original.lengthInBytes) {
        return compressed;
      }
    } catch (_) {}
    return original;
  }

  static String? _readErrorMessage(String body) {
    try {
      final data = jsonDecode(body);
      if (data is Map<String, dynamic>) {
        if (data['message'] != null) return data['message'].toString();
        final errs = data['errors'];
        if (errs is Map && errs.isNotEmpty) {
          final first = errs.values.first;
          if (first is List && first.isNotEmpty) return first.first.toString();
          return first.toString();
        }
      }
    } catch (_) {}
    return null;
  }
  /// See [ApiHostConfig] — emulator uses 10.0.0.2; physical phone uses saved Wi‑Fi IP.
  static String get baseUrl {
    final url = ApiHostConfig.current;
    if (url.isNotEmpty) return url;
    return 'http://127.0.0.1:8001/api';
  }

  static Future<String?> getToken() async {
    if (_authToken != null) return _authToken;
    final prefs = await _getPrefs();
    _authToken = prefs.getString('token');
    return _authToken;
  }

  static void clearCache(String key) {
    _cache.remove(key);
  }

  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await _getPrefs();
    _authToken ??= prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer ${_authToken ?? ''}',
    };
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/login"),
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
        },
        body: jsonEncode({"email": email, "password": password}),
      )
          .timeout(_httpTimeout);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final prefs = await _getPrefs();
        await prefs.setString('token', data['token']);
        _authToken = data['token']?.toString();

        if (data['user'] != null && data['user']['role'] != null) {
          await prefs.setString('role', data['user']['role']);
        }
        return {"success": true, "data": data};
      } else {
        // 🌿 SMART ERROR HANDLING: Grabs the exact error from Laravel
        String errorMsg = "Login failed. Please try again.";

        if (data['errors'] != null && data['errors'] is Map) {
          // Extracts specific validation errors (e.g., "Email not found")
          final firstErrorKey = data['errors'].keys.first;
          errorMsg = data['errors'][firstErrorKey][0];
        } else if (data['message'] != null) {
          // Extracts custom error messages (e.g., "Incorrect password")
          errorMsg = data['message'];
        } else if (data['error'] != null) {
          errorMsg = data['error'];
        }

        return {"success": false, "message": errorMsg};
      }
    } catch (e) {
      await AppLogger.logApiError(endpoint: 'POST /login', error: e);
      final hint = ApiHostConfig.requiresManualHost
          ? ' Enter your PC\'s Wi‑Fi IP under Server host (e.g. 192.168.1.10).'
          : '';
      return {
        "success": false,
        "message": "Cannot connect to server.$hint",
      };
    }
  }

  static Future<String?> register(
    String name,
    String email,
    String password,
  ) async {
    try {
      final response = await http
          .post(
        Uri.parse("$baseUrl/register"),
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
        },
        body: jsonEncode({"name": name, "email": email, "password": password}),
      )
          .timeout(_httpTimeout);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final prefs = await _getPrefs();
        await prefs.setString('token', data['token']);
        _authToken = data['token']?.toString();
        return null; // Return null means SUCCESS (no errors)
      } else {
        // 🌿 SMART ERROR HANDLING: Grabs the exact error from Laravel
        String errorMsg = "Registration failed. Please try again.";

        if (data['errors'] != null && data['errors'] is Map) {
          final firstErrorKey = data['errors'].keys.first;
          errorMsg =
              data['errors'][firstErrorKey][0]; // Gets the first validation error
        } else if (data['message'] != null) {
          errorMsg = data['message'];
        }

        return errorMsg; // Return the exact error text
      }
    } catch (e) {
      await AppLogger.logApiError(endpoint: 'POST /register', error: e);
      return "Cannot connect to server.";
    }
  }

  static Future<void> logout() async {
    try {
      await http
          .post(Uri.parse("$baseUrl/logout"), headers: await _getHeaders())
          .timeout(_httpTimeout);
    } catch (e) {
      await AppLogger.logApiError(endpoint: 'POST /logout', error: e);
    }
    final prefs = await _getPrefs();
    await prefs.remove('token');
    _authToken = null;
  }

  /// Returns ingredients ASAP using this priority:
  ///   1) in-memory cache
  ///   2) bundled asset (instant — no network)
  ///   3) offline JSON cache
  ///   4) live API
  ///
  /// When asset/offline is used, a background API refresh fires so the next
  /// open uses the latest data.
  static Future<List<Ingredient>> fetchIngredients() async {
    if (_cache.containsKey('ingredients')) {
      return _cache['ingredients'] as List<Ingredient>;
    }

    Future<List<Ingredient>?> tryAsset() async {
      try {
        final raw = await rootBundle.loadString('assets/data/ingredients.json');
        final data = jsonDecode(raw) as List<dynamic>;
        return data.map((e) => Ingredient.fromJson(e)).toList();
      } catch (_) {
        return null;
      }
    }

    Future<List<Ingredient>?> tryOffline() async {
      final raw = await OfflineCacheService.loadIngredientsJson();
      if (raw == null || raw.isEmpty) return null;
      try {
        final data = jsonDecode(raw) as List<dynamic>;
        return data.map((e) => Ingredient.fromJson(e)).toList();
      } catch (_) {
        return null;
      }
    }

    final fast = await tryOffline() ?? await tryAsset();
    if (fast != null) {
      _cache['ingredients'] = fast;
      // Refresh from network in the background so the next session is fresh.
      unawaited(_refreshIngredientsFromApi());
      return fast;
    }

    return _refreshIngredientsFromApi(forceReturn: true);
  }

  static Future<List<Ingredient>> _refreshIngredientsFromApi(
      {bool forceReturn = false}) async {
    final sw = Stopwatch()..start();
    try {
      final online = await ConnectivityService.isOnline;
      if (!online) {
        if (forceReturn) {
          throw Exception('Offline and no cached ingredients');
        }
        return _cache['ingredients'] as List<Ingredient>? ?? <Ingredient>[];
      }
      final response = await http
          .get(Uri.parse("$baseUrl/ingredients"),
              headers: {"Accept": "application/json"})
          .timeout(_httpTimeout);
      sw.stop();
      await PerformanceReporter.onApiCall('GET /ingredients', sw.elapsedMilliseconds);
      if (response.statusCode == 200) {
        await OfflineCacheService.saveIngredientsJson(response.body);
        final data = jsonDecode(response.body) as List<dynamic>;
        final result = data.map((e) => Ingredient.fromJson(e)).toList();
        _cache['ingredients'] = result;
        return result;
      }
      if (forceReturn) {
        throw Exception('Failed to load ingredients (status ${response.statusCode})');
      }
      return _cache['ingredients'] as List<Ingredient>? ?? <Ingredient>[];
    } catch (e) {
      sw.stop();
      await AppLogger.logApiError(endpoint: 'GET /ingredients', error: e);
      if (forceReturn) rethrow;
      return _cache['ingredients'] as List<Ingredient>? ?? <Ingredient>[];
    }
  }

  // In-memory cache for /match-recipes results so re-tapping the same
  // ingredient combo or filter is instant after the first hit.
  static final Map<String, Map<String, dynamic>> _matchCache = {};
  static String _matchKey(List<int> ids, int page, String? category,
      String? difficulty, int? maxCookingTime) {
    final sorted = List<int>.from(ids)..sort();
    return '${sorted.join(",")}|p=$page|c=${category ?? ""}|d=${difficulty ?? ""}|t=${maxCookingTime ?? 0}';
  }

  /// Synchronous accessor: returns cached match results if we have them, else
  /// `null`. Used by `home_screen.findRecipes()` to navigate instantly.
  static Map<String, dynamic>? cachedMatchRecipes(
    List<int> ingredientIds, {
    int page = 1,
    String? category,
    String? difficulty,
    int? maxCookingTime,
  }) {
    final key = _matchKey(
        ingredientIds, page, category, difficulty, maxCookingTime);
    return _matchCache[key];
  }

  static Future<Map<String, dynamic>> matchRecipes(
    List<int> ingredientIds,
    int page,
    String? category, {
    String? difficulty,
    int? maxCookingTime,
    bool useCache = true,
  }) async {
    final key = _matchKey(
        ingredientIds, page, category, difficulty, maxCookingTime);
    if (useCache && _matchCache.containsKey(key)) {
      // Refresh in background so the next session is fresh.
      unawaited(_fetchMatchFromApi(
          key, ingredientIds, page, category, difficulty, maxCookingTime));
      return _matchCache[key]!;
    }
    return _fetchMatchFromApi(
        key, ingredientIds, page, category, difficulty, maxCookingTime);
  }

  static Future<Map<String, dynamic>> _fetchMatchFromApi(
    String key,
    List<int> ingredientIds,
    int page,
    String? category,
    String? difficulty,
    int? maxCookingTime,
  ) async {
    final body = {
      "ingredient_ids": ingredientIds,
      if (category != null) "category": category,
      if (difficulty != null && difficulty.isNotEmpty) "difficulty": difficulty,
      if (maxCookingTime != null && maxCookingTime > 0)
        "max_cooking_time": maxCookingTime,
    };
    final response = await http
        .post(
      Uri.parse("$baseUrl/match-recipes?page=$page"),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    )
        .timeout(_httpTimeout);
    if (response.statusCode != 200) {
      throw Exception(
        _readErrorMessage(response.body) ?? 'Could not load matching recipes.',
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final List data = json["data"] ?? [];
    final recipes = data.map<Recipe>((e) => Recipe.fromJson(e)).toList();
    int? pageNum(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    final cp = pageNum(json['current_page']);
    final lp = pageNum(json['last_page']);
    final hasMore = cp != null && lp != null
        ? cp < lp
        : json['next_page_url'] != null;
    final result = <String, dynamic>{
      "recipes": recipes,
      "hasMore": hasMore,
      if (json['meta'] != null) "meta": json['meta'],
    };
    _matchCache[key] = result;
    return result;
  }

  /// Sprint 8 — boosts recommendation ranking from real usage (click / save).
  static Future<void> postRecommendationFeedback(
    int recipeId,
    String signal,
  ) async {
    assert(signal == 'click' || signal == 'save');
    final response = await http.post(
      Uri.parse('$baseUrl/recommendation-feedback'),
      headers: await _getHeaders(),
      body: jsonEncode({'recipe_id': recipeId, 'signal': signal}),
    );
    if (response.statusCode != 200) {
      debugPrint(
        'recommendation-feedback failed: ${response.statusCode} ${response.body}',
      );
    }
  }

  // Per-recipe in-flight dedup so simultaneous widgets asking for the same
  // recipe issue ONE network request, not N.
  static final Map<int, Future<Recipe>> _recipeDetailInFlight = {};

  /// Synchronous accessor used by `RecipeDetailScreen` to render instantly
  /// when we already have the recipe in memory.
  static Recipe? cachedRecipeDetail(int id) {
    final cached = _cache['recipe_$id'];
    return cached is Recipe ? cached : null;
  }

  static Future<Recipe> fetchRecipeDetail(int id) async {
    final key = 'recipe_$id';

    if (_cache.containsKey(key)) {
      return _cache[key];
    }

    // Stale-while-revalidate from disk cache — return immediately, refresh in BG.
    final offline = await OfflineCacheService.loadRecipeDetailJson(id);
    if (offline != null && offline.isNotEmpty) {
      try {
        final result = Recipe.fromJson(jsonDecode(offline));
        _cache[key] = result;
        unawaited(_refreshRecipeDetailFromApi(id));
        return result;
      } catch (_) {/* fall through */}
    }

    // Coalesce concurrent calls for the same id into a single HTTP fetch.
    final existing = _recipeDetailInFlight[id];
    if (existing != null) return existing;

    final future = _refreshRecipeDetailFromApi(id, throwOnError: true);
    _recipeDetailInFlight[id] = future;
    try {
      return await future;
    } finally {
      _recipeDetailInFlight.remove(id);
    }
  }

  static Future<Recipe> _refreshRecipeDetailFromApi(int id,
      {bool throwOnError = false}) async {
    final key = 'recipe_$id';
    try {
      final online = await ConnectivityService.isOnline;
      if (!online) {
        if (throwOnError) throw Exception('Offline and no cached recipe $id');
        return _cache[key] as Recipe;
      }
      final response = await http
          .get(Uri.parse("$baseUrl/recipes/$id"), headers: await _getHeaders())
          .timeout(_httpTimeout);
      if (response.statusCode == 200) {
        await OfflineCacheService.saveRecipeDetailJson(id, response.body);
        final result = Recipe.fromJson(jsonDecode(response.body));
        _cache[key] = result;
        return result;
      }
      if (throwOnError) {
        throw Exception('Failed to load recipe (status ${response.statusCode})');
      }
      return _cache[key] as Recipe;
    } catch (e) {
      if (throwOnError) {
        await AppLogger.logApiError(endpoint: 'GET /recipes/$id', error: e);
        rethrow;
      }
      return _cache[key] as Recipe;
    }
  }

  /// Stale-while-revalidate: returns the cached/offline favorites list
  /// immediately, then refreshes from the API in the background. Callers can
  /// pass [forceRefresh] to bypass the cache.
  static Future<List<Recipe>> fetchFavorite({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache['favorites'] is List<Recipe>) {
      unawaited(_refreshFavoritesFromApi());
      return _cache['favorites'] as List<Recipe>;
    }
    if (!forceRefresh) {
      final raw = await OfflineCacheService.loadFavoritesJson();
      if (raw != null && raw.isNotEmpty) {
        try {
          final List data = jsonDecode(raw);
          final result =
              data.map((e) => Recipe.fromJson(e['recipe'])).toList();
          _cache['favorites'] = result;
          unawaited(_refreshFavoritesFromApi());
          return result;
        } catch (_) {/* ignore parse errors, fall through to API */}
      }
    }
    return _refreshFavoritesFromApi(throwOnError: true);
  }

  static Future<List<Recipe>> _refreshFavoritesFromApi(
      {bool throwOnError = false}) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/favorites"), headers: await _getHeaders())
          .timeout(_httpTimeout);
      if (response.statusCode == 200) {
        await OfflineCacheService.saveFavoritesJson(response.body);
        final List data = jsonDecode(response.body);
        final result = data.map((e) => Recipe.fromJson(e['recipe'])).toList();
        _cache['favorites'] = result;
        return result;
      }
      if (throwOnError) {
        throw Exception('Failed to load favorites (status ${response.statusCode})');
      }
      return _cache['favorites'] as List<Recipe>? ?? <Recipe>[];
    } catch (e) {
      if (throwOnError) {
        await AppLogger.logApiError(endpoint: 'GET /favorites', error: e);
        rethrow;
      }
      return _cache['favorites'] as List<Recipe>? ?? <Recipe>[];
    }
  }

  static Future<Set<int>> fetchFavoriteIds() async {
    final response = await http
        .get(
      Uri.parse("$baseUrl/favorites"),
      headers: await _getHeaders(),
    )
        .timeout(_httpTimeout);
    if (response.statusCode == 200) {
      List data = jsonDecode(response.body);
      return data.map<int>((e) => e['recipe']['id'] as int).toSet();
    }
    throw Exception("Failed to fetch favorites");
  }

  static Future<void> addToFavorites(int recipeId) async {
    final response = await http
        .post(
      Uri.parse("$baseUrl/favorites"),
      headers: await _getHeaders(),
      body: jsonEncode({"recipe_id": recipeId}),
    )
        .timeout(_httpTimeout);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        _readErrorMessage(response.body) ?? 'Failed to add favorite',
      );
    }
    _cache.remove('favorites');
    unawaited(_refreshFavoritesFromApi());
  }

  static Future<void> removeFavorite(int recipeId) async {
    final response = await http
        .delete(
      Uri.parse("$baseUrl/favorites/$recipeId"),
      headers: await _getHeaders(),
    )
        .timeout(_httpTimeout);
    if (response.statusCode != 200) {
      throw Exception("Failed to remove favorite");
    }
    _cache.remove('favorites');
    unawaited(_refreshFavoritesFromApi());
  }

  static Future<AdminStats> fetchAdminStats({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache['admin_stats'] is AdminStats) {
      unawaited(_refreshAdminStats());
      return _cache['admin_stats'] as AdminStats;
    }
    return _refreshAdminStats(throwOnError: true);
  }

  static Future<AdminStats> _refreshAdminStats({bool throwOnError = false}) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/admin/stats'), headers: await _getHeaders())
          .timeout(_httpTimeout);
      if (response.statusCode == 200) {
        final stats = AdminStats.fromJson(jsonDecode(response.body)['data']);
        _cache['admin_stats'] = stats;
        return stats;
      }
      if (throwOnError) throw Exception('Failed to load admin stats');
      return _cache['admin_stats'] as AdminStats? ?? AdminStats.fromJson(const {});
    } catch (e) {
      if (throwOnError) rethrow;
      return _cache['admin_stats'] as AdminStats? ?? AdminStats.fromJson(const {});
    }
  }

  static Future<List<dynamic>> fetchPopularRecipes(
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _cache['popular_recipes'] is List) {
      unawaited(_refreshPopularRecipes());
      return _cache['popular_recipes'] as List;
    }
    return _refreshPopularRecipes(throwOnError: true);
  }

  static Future<List<dynamic>> _refreshPopularRecipes(
      {bool throwOnError = false}) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/admin/popular'),
              headers: await _getHeaders())
          .timeout(_httpTimeout);
      if (response.statusCode == 200) {
        final list = jsonDecode(response.body)['data'] as List;
        _cache['popular_recipes'] = list;
        return list;
      }
      if (throwOnError) throw Exception('Failed to load popular recipes');
      return _cache['popular_recipes'] as List? ?? const [];
    } catch (e) {
      if (throwOnError) rethrow;
      return _cache['popular_recipes'] as List? ?? const [];
    }
  }

  /// Bumped when the full recipe catalog finishes loading (UI can refresh).
  static final ValueNotifier<int> recipesCatalogRevision = ValueNotifier(0);

  static List<Recipe>? peekCachedRecipes() {
    final cached = _cache['recipes_all'];
    return cached is List<Recipe> ? cached : null;
  }

  static List<Recipe> _parseRecipeListResponse(String body) {
    final decoded = jsonDecode(body);
    List data = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return data.map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      final raw = map['image_url'] ?? map['image'];
      final resolved = RecipeImageResolver.networkUrl(raw?.toString());
      if (resolved != null) {
        map['image_url'] = resolved;
        map['image'] = resolved;
      }
      return Recipe.fromJson(map);
    }).toList();
  }

  static Future<List<Recipe>> fetchRecipes({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _cache['recipes_all'];
      if (cached is List<Recipe> &&
          _recipesFetchedAt != null &&
          DateTime.now().difference(_recipesFetchedAt!) < _recipesCacheTtl) {
        return cached;
      }
      if (_recipesInFlight != null) {
        return _recipesInFlight!;
      }

      // Offline / bundled fallback only when there is no network.
      final online = await ConnectivityService.isOnline;
      if (!online) {
        try {
          final offline = await OfflineCacheService.loadRecipesJson();
          if (offline != null && offline.isNotEmpty) {
            final list = _parseRecipeListResponse(offline);
            if (list.isNotEmpty) {
              _cache['recipes_all'] = list;
              _recipesFetchedAt = DateTime.now();
              return list;
            }
          }
        } catch (_) {}
      }
    } else {
      _cache.remove('recipes_all');
      _recipesFetchedAt = null;
    }

    _recipesInFlight = _fetchRecipesInternal(forceRefresh: forceRefresh);
    try {
      return await _recipesInFlight!;
    } finally {
      _recipesInFlight = null;
    }
  }

  static Future<List<Recipe>> _fetchRecipesInternal({bool forceRefresh = false}) async {
    final rawCached = await OfflineCacheService.loadRecipesJson();

    final sw = Stopwatch()..start();
    try {
      final online = await ConnectivityService.isOnline;
      if (!online) {
        final raw = await OfflineCacheService.loadRecipesJson();
        if (raw != null) {
          sw.stop();
          return _parseRecipeListResponse(raw);
        }
      }

      final all = <Recipe>[];
      var page = 1;
      var lastPage = 1;
      const perPage = 200;

      do {
        final uri = Uri.parse(
          '$baseUrl/recipes?compact=1&per_page=$perPage&page=$page',
        );
        final response = await http
            .get(uri, headers: await _getHeaders())
            .timeout(_httpTimeout);

        if (kDebugMode && page == 1) {
          debugPrint('FETCH RECIPES STATUS: ${response.statusCode}');
        }

        if (response.statusCode != 200) {
          break;
        }

        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          lastPage = int.tryParse('${decoded['last_page']}') ?? 1;
        }

        all.addAll(_parseRecipeListResponse(response.body));
        page++;
      } while (page <= lastPage && page <= 60);

      sw.stop();
      await PerformanceReporter.onApiCall('GET /recipes', sw.elapsedMilliseconds);

      if (all.isNotEmpty) {
        final encoded = jsonEncode({
          'data': all.map((r) => r.toJson()).toList(),
          'total': all.length,
        });
        await OfflineCacheService.saveRecipesJson(encoded);
        _cache['recipes_all'] = all;
        _recipesFetchedAt = DateTime.now();
        recipesCatalogRevision.value++;
        return all;
      }
      if (rawCached != null && rawCached.isNotEmpty) {
        final list = _parseRecipeListResponse(rawCached);
        _cache['recipes_all'] = list;
        _recipesFetchedAt = DateTime.now();
        return list;
      }
    } catch (e) {
      sw.stop();
      await AppLogger.logApiError(endpoint: 'GET /recipes', error: e);
      final raw = await OfflineCacheService.loadRecipesJson();
      if (raw != null) {
        final list = _parseRecipeListResponse(raw);
        _cache['recipes_all'] = list;
        _recipesFetchedAt = DateTime.now();
        return list;
      }
      rethrow;
    }

    throw Exception("Failed to fetch recipes");
  }

  static Future<List<Recipe>> fetchRecipesWithFilters({
    String? category,
    String? difficulty,
    int? maxCookingTime,
    int page = 1,
    int perPage = 25,
  }) async {
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      if (category != null && category.isNotEmpty) 'category': category,
      if (difficulty != null && difficulty.isNotEmpty) 'difficulty': difficulty,
      if (maxCookingTime != null && maxCookingTime > 0)
        'max_cooking_time': '$maxCookingTime',
    };
    final uri = Uri.parse('$baseUrl/recipes').replace(queryParameters: params);
    final response = await http.get(uri, headers: await _getHeaders());
    if (response.statusCode != 200) {
      throw Exception(_readErrorMessage(response.body) ?? 'Failed to load recipes');
    }
    final decoded = jsonDecode(response.body);
    final List data = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return data.map((e) => Recipe.fromJson(e)).toList();
  }

  /// Admin-only fetch: retrieves all recipes with full fields (including
  /// instructions), bypassing compact/offline browse cache.
  static Future<List<Recipe>> fetchAllRecipesForAdmin() async {
    const perPage = 200;
    var page = 1;
    var lastPage = 1;
    final all = <Recipe>[];

    do {
      final params = <String, String>{
        'page': '$page',
        'per_page': '$perPage',
      };
      final uri = Uri.parse('$baseUrl/recipes').replace(queryParameters: params);
      final response = await http.get(uri, headers: await _getHeaders());
      if (response.statusCode != 200) {
        throw Exception(_readErrorMessage(response.body) ?? 'Failed to load admin recipes');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final List data = (decoded['data'] as List?) ?? const [];
        all.addAll(data.map((e) => Recipe.fromJson(e)));
        final lp = int.tryParse(decoded['last_page']?.toString() ?? '');
        lastPage = (lp == null || lp < 1) ? page : lp;
      } else if (decoded is List) {
        all.addAll(decoded.map((e) => Recipe.fromJson(e)));
        lastPage = page;
      } else {
        lastPage = page;
      }
      page++;
    } while (page <= lastPage);

    return all;
  }

  static Future<List<dynamic>> fetchUsers({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache['users_list'] is List) {
      unawaited(_refreshUsersList());
      return _cache['users_list'] as List;
    }
    return _refreshUsersList(throwOnError: true);
  }

  static Future<Map<String, dynamic>> fetchUsersPaginated({
    int page = 1,
    int perPage = 20,
    String query = '',
    String searchMode = 'all', // all|first|last
  }) async {
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      if (query.trim().isNotEmpty) 'q': query.trim(),
      if (searchMode != 'all') 'search_mode': searchMode,
    };
    final uri = Uri.parse('$baseUrl/users').replace(queryParameters: params);
    final response = await http
        .get(uri, headers: await _getHeaders())
        .timeout(_httpTimeout);
    if (response.statusCode != 200) {
      throw Exception(_readErrorMessage(response.body) ?? 'Failed to load users');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      final list = (decoded['data'] as List?) ?? const [];
      return <String, dynamic>{
        'items': List<dynamic>.from(list),
        'current_page':
            int.tryParse(decoded['current_page']?.toString() ?? '') ?? page,
        'last_page': int.tryParse(decoded['last_page']?.toString() ?? '') ?? 1,
        'total': int.tryParse(decoded['total']?.toString() ?? '') ?? list.length,
      };
    }
    if (decoded is List) {
      return <String, dynamic>{
        'items': List<dynamic>.from(decoded),
        'current_page': page,
        'last_page': page,
        'total': decoded.length,
      };
    }
    return <String, dynamic>{
      'items': const <dynamic>[],
      'current_page': page,
      'last_page': 1,
      'total': 0,
    };
  }

  static Future<Map<String, dynamic>> fetchAdminRecipesPaginated({
    int page = 1,
    int perPage = 20,
    String query = '',
  }) async {
    final params = <String, String>{
      'page': '$page',
      'per_page': '$perPage',
      if (query.trim().isNotEmpty) 'q': query.trim(),
    };
    final uri = Uri.parse('$baseUrl/recipes').replace(queryParameters: params);
    final response = await http
        .get(uri, headers: await _getHeaders())
        .timeout(_httpTimeout);
    if (response.statusCode != 200) {
      throw Exception(_readErrorMessage(response.body) ?? 'Failed to load recipes');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      final list = (decoded['data'] as List?) ?? const [];
      return <String, dynamic>{
        'items': list.map((e) => Recipe.fromJson(Map<String, dynamic>.from(e))).toList(),
        'current_page':
            int.tryParse(decoded['current_page']?.toString() ?? '') ?? page,
        'last_page': int.tryParse(decoded['last_page']?.toString() ?? '') ?? 1,
        'total': int.tryParse(decoded['total']?.toString() ?? '') ?? list.length,
      };
    }
    if (decoded is List) {
      return <String, dynamic>{
        'items': decoded.map((e) => Recipe.fromJson(Map<String, dynamic>.from(e))).toList(),
        'current_page': page,
        'last_page': page,
        'total': decoded.length,
      };
    }
    return <String, dynamic>{
      'items': const <Recipe>[],
      'current_page': page,
      'last_page': 1,
      'total': 0,
    };
  }

  static Future<List<dynamic>> _refreshUsersList(
      {bool throwOnError = false}) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/users"), headers: await _getHeaders())
          .timeout(_httpTimeout);
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final list = decoded is Map
            ? List<dynamic>.from(decoded["data"] ?? const [])
            : List<dynamic>.from(decoded);
        _cache['users_list'] = list;
        return list;
      }
      if (throwOnError) throw Exception('Failed to load users');
      return _cache['users_list'] as List? ?? const [];
    } catch (e) {
      if (throwOnError) rethrow;
      return _cache['users_list'] as List? ?? const [];
    }
  }

  static Future<void> createRecipe({
    required String name,
    required String category,
    required String instructions,
    List<int> ingredientIds = const [],
    List<String> ingredientNames = const [],
    String difficulty = 'medium',
    int cookingTime = 30,
    XFile? imageFile,
  }) async {
    final uri = Uri.parse("$baseUrl/recipes");
    final request = http.MultipartRequest('POST', uri);
    final headers = await _getHeaders();
    headers.remove('Content-Type');
    request.headers.addAll(headers);

    request.fields['name'] = name;
    request.fields['category'] = category;
    request.fields['instructions'] = instructions;
    request.fields['difficulty'] = difficulty;
    request.fields['cooking_time'] = '$cookingTime';

    for (int i = 0; i < ingredientIds.length; i++) {
      request.fields['ingredient_ids[$i]'] = ingredientIds[i].toString();
    }
    for (int i = 0; i < ingredientNames.length; i++) {
      request.fields['ingredient_names[$i]'] = ingredientNames[i];
    }

    if (imageFile != null) {
      final bytes = await _prepareRecipeImageBytes(imageFile);
      final multipartFile = http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: imageFile.name,
      );
      request.files.add(multipartFile);
    }

    final response = await request.send();
    if (response.statusCode != 200 && response.statusCode != 201)
      throw Exception("Failed to create recipe");
  }

  static Future<void> updateRecipe({
    required int id,
    required String name,
    required String category,
    required String instructions,
    List<int> ingredientIds = const [],
    List<String> ingredientNames = const [],
    String difficulty = 'medium',
    int cookingTime = 30,
    XFile? imageFile,
  }) async {
    final uri = Uri.parse("$baseUrl/recipes/$id");
    final request = http.MultipartRequest('POST', uri);
    request.fields['_method'] = 'PUT';

    final headers = await _getHeaders();
    headers.remove('Content-Type');
    request.headers.addAll(headers);

    request.fields['name'] = name;
    request.fields['category'] = category;
    request.fields['instructions'] = instructions;
    request.fields['difficulty'] = difficulty;
    request.fields['cooking_time'] = '$cookingTime';

    for (int i = 0; i < ingredientIds.length; i++) {
      request.fields['ingredient_ids[$i]'] = ingredientIds[i].toString();
    }
    for (int i = 0; i < ingredientNames.length; i++) {
      request.fields['ingredient_names[$i]'] = ingredientNames[i];
    }

    if (imageFile != null) {
      final bytes = await _prepareRecipeImageBytes(imageFile);
      final multipartFile = http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: imageFile.name,
      );
      request.files.add(multipartFile);
    }

    final response = await request.send();
    if (response.statusCode != 200) throw Exception("Failed to update recipe");
  }

  static Future<void> deleteRecipe(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/recipes/$id'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200 && response.statusCode != 204)
      throw Exception("Failed to delete recipe");
  }

  static Future<void> createUser({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
        'role': role,
      }),
    );
    if (response.statusCode != 201 && response.statusCode != 200)
      throw Exception("Failed to create user");
  }

  static Future<void> deleteUser(int id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/users/$id'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200 && response.statusCode != 204)
      throw Exception("Failed to delete user");
  }

  static Future<void> adminUpdateUser(int id, String name, String email) async {
    final response = await http.put(
      Uri.parse('$baseUrl/users/$id'),
      headers: await _getHeaders(),
      body: jsonEncode({'name': name, 'email': email}),
    );
    if (response.statusCode != 200) throw Exception("Failed to update user");
  }

  static Future<void> rateRecipe(int recipeId, int rating) async {
    final response = await http.post(
      Uri.parse("$baseUrl/rate"),
      headers: await _getHeaders(),
      body: jsonEncode({
        "recipe_id": recipeId.toString(),
        "rating": rating.toString(),
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_readErrorMessage(response.body) ?? "Failed to submit rating");
    }
  }

  static Future<void> logActivity(String action, int? recipeId) async {
    final payload = {"action": action, "recipe_id": recipeId?.toString()};
    try {
      final online = await ConnectivityService.isOnline;
      if (!online) {
        await OfflineCacheService.enqueuePendingActivity(payload);
        return;
      }
      await http.post(
        Uri.parse("$baseUrl/activity"),
        headers: await _getHeaders(),
        body: jsonEncode(payload),
      );
    } catch (e) {
      await OfflineCacheService.enqueuePendingActivity(payload);
      await AppLogger.logApiError(endpoint: 'POST /activity', error: e);
    }
  }

  static Future<List<Recipe>> fetchRecommendedRecipes() async {
    if (_cache.containsKey('recommendations')) {
      debugPrint("CACHE HIT: recommendations");
      return _cache['recommendations'];
    }
    if (_recommendationsInFlight != null) {
      debugPrint("CACHE WAIT: recommendations");
      return _recommendationsInFlight!;
    }

    debugPrint("CACHE MISS: recommendations");
    _recommendationsInFlight = () async {
      try {
        final response = await http
            .get(
              Uri.parse("$baseUrl/recommended-recipes"),
              headers: await _getHeaders(),
            )
            .timeout(_httpTimeout);

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          List data = decoded is Map ? (decoded['data'] ?? []) : decoded;
          final result = data.map((e) => Recipe.fromJson(e)).toList();
          _cache['recommendations'] = result;
          return result;
        }
      } catch (_) {
        // Fall through to fast fallback.
      }

      // Fast fallback: use already-optimized recipes endpoint instead of failing home.
      final quick = await fetchRecipes();
      final fallback = quick.take(15).toList(growable: false);
      _cache['recommendations'] = fallback;
      return fallback;
    }();
    try {
      return await _recommendationsInFlight!;
    } finally {
      _recommendationsInFlight = null;
    }
  }

  static Future<Map<String, dynamic>> getUserProfile(
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _cache['user_profile'] is Map<String, dynamic>) {
      unawaited(_refreshUserProfile());
      return _cache['user_profile'] as Map<String, dynamic>;
    }
    if (!forceRefresh) {
      final prefs = await _getPrefs();
      final cached = prefs.getString('user_profile_cache');
      if (cached != null && cached.isNotEmpty) {
        try {
          final m = jsonDecode(cached) as Map<String, dynamic>;
          _cache['user_profile'] = m;
          unawaited(_refreshUserProfile());
          return m;
        } catch (_) {/* fall through */}
      }
    }
    return _refreshUserProfile(throwOnError: true);
  }

  static Future<Map<String, dynamic>> _refreshUserProfile(
      {bool throwOnError = false}) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/user/profile'),
              headers: await _getHeaders())
          .timeout(_httpTimeout);
      if (response.statusCode == 200) {
        final m = jsonDecode(response.body) as Map<String, dynamic>;
        _cache['user_profile'] = m;
        final prefs = await _getPrefs();
        await prefs.setString('user_profile_cache', response.body);
        return m;
      }
      if (throwOnError) {
        throw Exception('Failed to load profile data (status ${response.statusCode})');
      }
      return _cache['user_profile'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
    } catch (e) {
      if (throwOnError) {
        await AppLogger.logApiError(endpoint: 'GET /user/profile', error: e);
        rethrow;
      }
      return _cache['user_profile'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
    }
  }

  static Future<void> updateUserProfile(
    String name,
    String email,
    String? password,
  ) async {
    final Map<String, dynamic> body = {'name': name, 'email': email};
    if (password != null && password.isNotEmpty) body['password'] = password;
    final response = await http.put(
      Uri.parse('$baseUrl/user/profile'),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) throw Exception('Failed to update profile');
  }

  static Future<Map<String, dynamic>> fetchActivityStats(
      {bool forceRefresh = false}) async {
    if (!forceRefresh && _cache['activity_stats'] is Map<String, dynamic>) {
      unawaited(_refreshActivityStats());
      return _cache['activity_stats'] as Map<String, dynamic>;
    }
    return _refreshActivityStats(throwOnError: true);
  }

  static Future<Map<String, dynamic>> _refreshActivityStats(
      {bool throwOnError = false}) async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/admin/activity-stats'),
              headers: await _getHeaders())
          .timeout(_httpTimeout);
      if (response.statusCode == 200) {
        final m = jsonDecode(response.body)['data'] as Map<String, dynamic>;
        _cache['activity_stats'] = m;
        return m;
      }
      if (throwOnError) throw Exception('Failed to load activity statistics');
      return _cache['activity_stats'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
    } catch (e) {
      if (throwOnError) rethrow;
      return _cache['activity_stats'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
    }
  }

  static Future<List<dynamic>> fetchIngredientUsage({
    String? date,
    String? month,
    bool forceRefresh = false,
  }) async {
    final cacheKey = 'ingredient_usage|d=${date ?? ""}|m=${month ?? ""}';
    if (!forceRefresh && _cache[cacheKey] is List) {
      unawaited(_refreshIngredientUsage(date: date, month: month, key: cacheKey));
      return _cache[cacheKey] as List;
    }
    return _refreshIngredientUsage(
        date: date, month: month, key: cacheKey, throwOnError: true);
  }

  static Future<List<dynamic>> _refreshIngredientUsage({
    String? date,
    String? month,
    required String key,
    bool throwOnError = false,
  }) async {
    String url = '$baseUrl/admin/ingredient-usage';
    final params = <String>[];
    if (date != null) params.add('date=$date');
    if (month != null) params.add('month=$month');
    if (params.isNotEmpty) url += '?${params.join('&')}';

    try {
      final response = await http
          .get(Uri.parse(url), headers: await _getHeaders())
          .timeout(_httpTimeout);
      final decoded = jsonDecode(response.body);
      final list = (decoded['data'] ?? const []) as List;
      _cache[key] = list;
      return list;
    } catch (e) {
      if (throwOnError) rethrow;
      return _cache[key] as List? ?? const [];
    }
  }

  /// Returns `items` (list of error rows) and `meta` (`current_page`, `last_page`, `per_page`, `total`).
  static Future<Map<String, dynamic>> fetchErrorLogsPaginated({
    String? severity,
    String? errorType,
    String? startDate,
    String? endDate,
    int page = 1,
    int perPage = 15,
  }) async {
    final q = <String>[
      'per_page=$perPage',
      'page=$page',
    ];
    if (severity != null && severity.isNotEmpty) q.add('severity=$severity');
    if (errorType != null && errorType.isNotEmpty) {
      q.add('error_type=${Uri.encodeComponent(errorType)}');
    }
    if (startDate != null && startDate.isNotEmpty) q.add('start_date=$startDate');
    if (endDate != null && endDate.isNotEmpty) q.add('end_date=$endDate');

    final response = await http
        .get(
          Uri.parse('$baseUrl/admin/error-logs?${q.join('&')}'),
          headers: await _getHeaders(),
        )
        .timeout(_httpTimeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body['data'];
      final items = list is List
          ? List<dynamic>.from(list)
          : <dynamic>[];
      final rawMeta = body['meta'];
      final meta = rawMeta is Map
          ? Map<String, dynamic>.from(rawMeta)
          : <String, dynamic>{};
      return {'items': items, 'meta': meta};
    }
    throw Exception('Failed to load error logs');
  }

  static Future<List<dynamic>> fetchErrorLogs({
    String? severity,
    String? errorType,
    String? startDate,
    String? endDate,
    int perPage = 50,
    int page = 1,
  }) async {
    final r = await fetchErrorLogsPaginated(
      severity: severity,
      errorType: errorType,
      startDate: startDate,
      endDate: endDate,
      page: page,
      perPage: perPage,
    );
    return r['items'] as List<dynamic>;
  }

  static Future<List<dynamic>> fetchPerformanceMetrics({
    String? kind,
    String? startDate,
    String? endDate,
    int perPage = 50,
  }) async {
    final r = await fetchPerformanceMetricsPaginated(
      kind: kind,
      startDate: startDate,
      endDate: endDate,
      perPage: perPage,
      page: 1,
    );
    return r['items'] as List<dynamic>;
  }

  static Future<Map<String, dynamic>> fetchPerformanceMetricsPaginated({
    String? kind,
    String? startDate,
    String? endDate,
    int perPage = 10,
    int page = 1,
  }) async {
    final q = <String>['per_page=$perPage'];
    q.add('page=$page');
    if (kind != null && kind.isNotEmpty) q.add('kind=${Uri.encodeComponent(kind)}');
    if (startDate != null && startDate.isNotEmpty) q.add('start_date=$startDate');
    if (endDate != null && endDate.isNotEmpty) q.add('end_date=$endDate');

    final response = await http
        .get(
          Uri.parse('$baseUrl/admin/performance-metrics?${q.join('&')}'),
          headers: await _getHeaders(),
        )
        .timeout(_httpTimeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body['data'];
      final items = list is List ? List<dynamic>.from(list) : <dynamic>[];
      final rawMeta = body['meta'];
      final meta = rawMeta is Map
          ? Map<String, dynamic>.from(rawMeta)
          : <String, dynamic>{};
      return {'items': items, 'meta': meta};
    }
    throw Exception('Failed to load performance metrics');
  }

  static Future<String?> forgotPassword(String email) async {
    final response = await http.post(
      Uri.parse('$baseUrl/forgot-password'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'email': email}),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) return null;
    return data['message']?.toString() ?? 'Could not send reset link';
  }

  static Future<String?> resetPassword({
    required String email,
    required String token,
    required String password,
    required String passwordConfirmation,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reset-password'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'token': token,
        'password': password,
        'password_confirmation': passwordConfirmation,
      }),
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) return null;
    return data['message']?.toString() ?? 'Reset failed';
  }

  // 🌿 UPDATED: Now accepts a formatted date string (YYYY-MM-DD)
  static Future<List<dynamic>> fetchActivityLogs(
    int page, {
    String? date,
    String? month,
  }) async {
    String url = '$baseUrl/admin/activity-logs?page=$page';

    if (date != null) {
      url += '&date=$date';
    }

    if (month != null) {
      url += '&month=$month';
    }

    final response = await http
        .get(
          Uri.parse(url),
          headers: await _getHeaders(),
        )
        .timeout(_httpTimeout);

    final decoded = jsonDecode(response.body);

    return decoded['data']['data'] ?? [];
  }

  static Future<List<dynamic>> fetchAllActivityLogs({
    String? date,
    String? month,
  }) async {
    String url = '$baseUrl/admin/activity-logs?per_page=1000';

    if (date != null) {
      url += '&date=$date';
    }

    if (month != null) {
      url += '&month=$month';
    }

    final response = await http
        .get(
          Uri.parse(url),
          headers: await _getHeaders(),
        )
        .timeout(_httpTimeout);

    final decoded = jsonDecode(response.body);

    return decoded['data']['data'] ?? [];
  }

  static Future<void> createIngredient(String name) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/ingredients',
      ), // Ensure your Laravel route matches this
      headers: await _getHeaders(),
      body: jsonEncode({'name': name}),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception("Failed to create ingredient");
    }
  }

  static Future<List<dynamic>> fetchActivityLogsByDate(
    DateTime start,
    DateTime end,
  ) async {
    final response = await http
        .get(
          Uri.parse(
            "$baseUrl/admin/activity-logs?start_date=${start.toIso8601String()}&end_date=${end.toIso8601String()}",
          ),
          headers: await _getHeaders(),
        )
        .timeout(_httpTimeout);

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);

      if (decoded is Map && decoded.containsKey('data')) {
        return List<dynamic>.from(decoded['data']);
      }

      return [];
    } else {
      debugPrint("Date Filter Error: ${response.statusCode}");
      return [];
    }
  }

  static Future<List<dynamic>> fetchApiUsage() async {
    final r = await fetchApiUsagePaginated();
    return r['items'] as List<dynamic>;
  }

  static Future<Map<String, dynamic>> fetchApiUsagePaginated({
    String? startDate,
    String? endDate,
    int page = 1,
    int perPage = 10,
  }) async {
    final q = <String>[
      'page=$page',
      'per_page=$perPage',
    ];
    if (startDate != null && startDate.isNotEmpty) q.add('start_date=$startDate');
    if (endDate != null && endDate.isNotEmpty) q.add('end_date=$endDate');
    final response = await http
        .get(
          Uri.parse('$baseUrl/admin/api-usage?${q.join('&')}'),
          headers: await _getHeaders(),
        )
        .timeout(_httpTimeout);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body['data'];
      final items = list is List
          ? List<dynamic>.from(list)
          : <dynamic>[];
      final rawMeta = body['meta'];
      final meta = rawMeta is Map
          ? Map<String, dynamic>.from(rawMeta)
          : <String, dynamic>{};
      return {'items': items, 'meta': meta};
    }
    throw Exception('Failed to load API usage');
  }

  static Future<Map<String, dynamic>> globalSearch(String query) async {
    final uri = Uri.parse(
      '$baseUrl/search?query=${Uri.encodeQueryComponent(query)}',
    );
    final sw = Stopwatch()..start();
    try {
      final response = await http.get(
        uri,
        headers: const {'Accept': 'application/json'},
      );
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      throw Exception(
        _readErrorMessage(response.body) ?? 'Search could not be completed.',
      );
    } finally {
      sw.stop();
      await PerformanceReporter.onApiCall(
        'GET /search',
        sw.elapsedMilliseconds,
      );
    }
  }

  static Future<Map<String, dynamic>> fetchSearchSuggestions(
    String query,
  ) async {
    final response = await http.get(
      Uri.parse(
        '$baseUrl/search/suggestions?query=${Uri.encodeQueryComponent(query)}',
      ),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load suggestions');
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static Future<List<String>> fetchSearchHistory() async {
    final response = await http.get(
      Uri.parse('$baseUrl/search/history'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) return [];
    final decoded = jsonDecode(response.body);
    final list = (decoded['data'] as List?) ?? const [];
    return list
        .map((e) => (e is Map ? e['query'] : null)?.toString() ?? '')
        .where((q) => q.isNotEmpty)
        .toList();
  }

  static Future<Map<String, dynamic>> fetchPersonalizedHomeFeed() async {
    try {
      final online = await ConnectivityService.isOnline;
      if (!online) {
        final raw = await OfflineCacheService.loadHomeFeedJson();
        if (raw != null) {
          final decoded = jsonDecode(raw);
          return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
        }
      }

      final response = await http
          .get(
            Uri.parse('$baseUrl/home/feed'),
            headers: await _getHeaders(),
          )
          .timeout(_httpTimeout);
      if (response.statusCode != 200) {
        throw Exception('Failed to load personalized feed');
      }
      await OfflineCacheService.saveHomeFeedJson(response.body);
      final decoded = jsonDecode(response.body);
      return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (e) {
      await AppLogger.logApiError(endpoint: 'GET /home/feed', error: e);
      final raw = await OfflineCacheService.loadHomeFeedJson();
      if (raw != null) {
        final decoded = jsonDecode(raw);
        return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
      }
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> fetchAppVersionInfo() async {
    final response = await http.get(
      Uri.parse('$baseUrl/app/version'),
      headers: const {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to check app version');
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static Future<List<Map<String, dynamic>>> suggestIngredientSubstitutions(
    List<String> ingredients,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ingredients/substitutions'),
      headers: await _getHeaders(),
      body: jsonEncode({'ingredients': ingredients}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch substitutions');
    }
    final decoded = jsonDecode(response.body);
    final list = (decoded['data'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> submitSubstitutionFeedback({
    required String ingredient,
    required String substitute,
    required bool accepted,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ingredients/substitutions/feedback'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'ingredient': ingredient,
        'substitute': substitute,
        'accepted': accepted,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to save substitution feedback');
    }
  }

  static Future<List<Map<String, dynamic>>> fetchIngredientComboSuggestions(
    List<int> ingredientIds, {
    int limit = 6,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/ingredients/combo-suggestions'),
      headers: await _getHeaders(),
      body: jsonEncode({'ingredient_ids': ingredientIds, 'limit': limit}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch ingredient combo suggestions');
    }
    final decoded = jsonDecode(response.body);
    final list = (decoded['data'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<Map<String, dynamic>> askCookingAssistant({
    required String message,
    List<int>? ingredientIds,
    List<Map<String, String>>? conversation,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/assistant/cook-help'),
      headers: await _getHeaders(),
      body: jsonEncode({
        'message': message,
        if (ingredientIds != null) 'ingredient_ids': ingredientIds,
        if (conversation != null && conversation.isNotEmpty) 'conversation': conversation,
      }),
    );
    if (response.statusCode != 200) {
      final serverMsg = _readErrorMessage(response.body);
      throw Exception(
        serverMsg ??
            'Assistant unavailable (status ${response.statusCode}). Please login again if needed.',
      );
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> fetchCookingInsights() async {
    final response = await http.get(
      Uri.parse('$baseUrl/user/cooking-insights'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load cooking insights');
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  static Future<List<Map<String, dynamic>>> fetchSmartNotifications() async {
    final response = await http.get(
      Uri.parse('$baseUrl/notifications/smart'),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load smart notifications');
    }
    final decoded = jsonDecode(response.body);
    final list = (decoded['data'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<List<Recipe>> fetchCookNowRecipes(
    List<int> ingredientIds, {
    int limit = 12,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/cook-now'),
      headers: await _getHeaders(),
      body: jsonEncode({'ingredient_ids': ingredientIds, 'limit': limit}),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load cook now recipes');
    }
    final decoded = jsonDecode(response.body);
    final list = (decoded['data'] as List?) ?? const [];
    return list.map((e) => Recipe.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  static Future<Map<String, dynamic>> adminAutoTagRecipe({
    String? name,
    String? instructions,
    List<String>? ingredients,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/recipes/auto-tag'),
      headers: await _getHeaders(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (instructions != null) 'instructions': instructions,
        if (ingredients != null) 'ingredients': ingredients,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to auto-tag recipe');
    }
    final decoded = jsonDecode(response.body);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  // GET COLLECTIONS — stale-while-revalidate
  static Future<List<dynamic>> getCollections({bool forceRefresh = false}) async {
    if (!forceRefresh && _cache['collections'] is List) {
      unawaited(_refreshCollectionsFromApi());
      return _cache['collections'] as List;
    }
    if (!forceRefresh) {
      final raw = await OfflineCacheService.loadCollectionsJson();
      if (raw != null && raw.isNotEmpty) {
        try {
          final list = json.decode(raw) as List;
          _cache['collections'] = list;
          unawaited(_refreshCollectionsFromApi());
          return list;
        } catch (_) {/* fall through */}
      }
    }
    return _refreshCollectionsFromApi(throwOnError: true);
  }

  static Future<List<dynamic>> _refreshCollectionsFromApi(
      {bool throwOnError = false}) async {
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/collections"), headers: await _getHeaders())
          .timeout(_httpTimeout);
      if (response.statusCode == 200) {
        final raw = utf8.decode(response.bodyBytes);
        await OfflineCacheService.saveCollectionsJson(raw);
        final list = json.decode(raw) as List;
        _cache['collections'] = list;
        return list;
      }
      if (throwOnError) {
        throw Exception(
            'Failed to load collections (status ${response.statusCode})');
      }
      return _cache['collections'] as List? ?? const [];
    } catch (e) {
      if (throwOnError) {
        await AppLogger.logApiError(endpoint: 'GET /collections', error: e);
        rethrow;
      }
      return _cache['collections'] as List? ?? const [];
    }
  }

  static Future<void> createCollection(String name) async {
    final response = await http.post(
      Uri.parse("$baseUrl/collections"),
      headers: await _getHeaders(), // ✅ MUST use the helper here!
      body: json.encode({"name": name}),
    );

    // If the server returns 401 or 500, we need to throw an error
    // so the UI knows something went wrong.
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        _readErrorMessage(response.body) ?? 'Failed to create collection',
      );
    }
    _cache.remove('collections');
  }

  // 🔥 FIX: ADD RECIPE TO COLLECTION
  static Future<bool> addToCollection(int collectionId, int recipeId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/collections/add"),
      headers: await _getHeaders(), // ✅ Use helper
      body: jsonEncode({"collection_id": collectionId, "recipe_id": recipeId}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _readErrorMessage(response.body) ?? "Add to collection failed",
      );
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded['duplicate'] == true;
      }
    } catch (_) {}
    return false;
  }

  static Future<Map<String, dynamic>> getCollectionDetail(int id,
      {bool forceRefresh = false}) async {
    final key = 'collection_detail_$id';
    if (!forceRefresh && _cache[key] is Map<String, dynamic>) {
      unawaited(_refreshCollectionDetailFromApi(id));
      return _cache[key] as Map<String, dynamic>;
    }
    if (!forceRefresh) {
      final raw = await OfflineCacheService.loadCollectionDetailJson(id);
      if (raw != null && raw.isNotEmpty) {
        try {
          final map = json.decode(raw) as Map<String, dynamic>;
          _cache[key] = map;
          unawaited(_refreshCollectionDetailFromApi(id));
          return map;
        } catch (_) {/* fall through */}
      }
    }
    return _refreshCollectionDetailFromApi(id, throwOnError: true);
  }

  static Map<String, dynamic>? cachedCollectionDetail(int id) {
    final key = 'collection_detail_$id';
    final cached = _cache[key];
    if (cached is Map<String, dynamic>) return cached;
    return null;
  }

  static Future<Map<String, dynamic>> _refreshCollectionDetailFromApi(int id,
      {bool throwOnError = false}) async {
    final key = 'collection_detail_$id';
    try {
      final response = await http
          .get(Uri.parse("$baseUrl/collections/$id"),
              headers: await _getHeaders())
          .timeout(_httpTimeout);
      if (response.statusCode == 200) {
        final raw = utf8.decode(response.bodyBytes);
        await OfflineCacheService.saveCollectionDetailJson(id, raw);
        final map = json.decode(raw) as Map<String, dynamic>;
        _cache[key] = map;
        return map;
      }
      if (throwOnError) {
        throw Exception(
            'Failed to load collection (status ${response.statusCode})');
      }
      return _cache[key] as Map<String, dynamic>? ?? const <String, dynamic>{};
    } catch (e) {
      if (throwOnError) {
        await AppLogger.logApiError(endpoint: 'GET /collections/$id', error: e);
        rethrow;
      }
      return _cache[key] as Map<String, dynamic>? ?? const <String, dynamic>{};
    }
  }

  static Future<List<Recipe>> fetchRecentRecipes(List<int> ids) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/recipes/recent"),
        headers: await _getHeaders(),
        body: json.encode({"ids": ids}),
      );
      if (response.statusCode == 200) {
        List data = json.decode(utf8.decode(response.bodyBytes));
        return data.map((item) => Recipe.fromJson(item)).toList();
      }
      debugPrint(
        "fetchRecentRecipes failed: ${response.statusCode} ${response.body}",
      );
    } catch (e) {
      debugPrint("Recent fetch error: $e");
    }
    return [];
  }

  static Future<void> syncPendingActivities() async {
    final online = await ConnectivityService.isOnline;
    if (!online) return;
    final pending = await OfflineCacheService.loadPendingActivities();
    if (pending.isEmpty) return;
    final sent = <Map<String, dynamic>>[];
    for (final payload in pending) {
      try {
        final response = await http.post(
          Uri.parse("$baseUrl/activity"),
          headers: await _getHeaders(),
          body: jsonEncode(payload),
        );
        if (response.statusCode >= 200 && response.statusCode < 300) {
          sent.add(payload);
        }
      } catch (_) {}
    }
    if (sent.length == pending.length) {
      await OfflineCacheService.clearPendingActivities();
    }
  }

  static Future<void> warmStartupData() async {
    try {
      await Future.wait([fetchIngredients(), fetchRecipes()]);
    } catch (_) {}
  }
}
