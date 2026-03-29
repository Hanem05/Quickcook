import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../models/admin_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

import 'connectivity_service.dart';
import 'offline_cache_service.dart';
import 'performance_reporter.dart';

class ApiService {
  static String? token;

  static final Map<String, dynamic> _cache = {};
  /// Production: `flutter build apk --dart-define=API_BASE_URL=https://your-host/api`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.2:8000/api',
  );

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static void clearCache(String key) {
    _cache.remove(key);
  }

  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/login"),
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
        },
        body: jsonEncode({"email": email, "password": password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);

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
      return {"success": false, "message": "Cannot connect to server."};
    }
  }

  static Future<String?> register(
    String name,
    String email,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/register"),
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
        },
        body: jsonEncode({"name": name, "email": email, "password": password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['token']);
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
      return "Cannot connect to server.";
    }
  }

  static Future<void> logout() async {
    await http.post(Uri.parse("$baseUrl/logout"), headers: await _getHeaders());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
  }

  static Future<List<Ingredient>> fetchIngredients() async {
    if (_cache.containsKey('ingredients')) {
      debugPrint("CACHE HIT: ingredients");
      return _cache['ingredients'];
    }

    debugPrint("CACHE MISS: ingredients");

    final sw = Stopwatch()..start();
    try {
      final online = await ConnectivityService.isOnline;
      if (!online) {
        final raw = await OfflineCacheService.loadIngredientsJson();
        if (raw != null) {
          List data = jsonDecode(raw);
          final result = data.map((e) => Ingredient.fromJson(e)).toList();
          _cache['ingredients'] = result;
          return result;
        }
      }

      final response = await http.get(
        Uri.parse("$baseUrl/ingredients"),
        headers: {"Accept": "application/json"},
      );
      sw.stop();
      await PerformanceReporter.onApiCall('GET /ingredients', sw.elapsedMilliseconds);

      if (response.statusCode == 200) {
        await OfflineCacheService.saveIngredientsJson(response.body);
        List data = jsonDecode(response.body);
        final result = data.map((e) => Ingredient.fromJson(e)).toList();

        _cache['ingredients'] = result;

        return result;
      }
    } catch (e) {
      sw.stop();
      final raw = await OfflineCacheService.loadIngredientsJson();
      if (raw != null) {
        List data = jsonDecode(raw);
        final result = data.map((e) => Ingredient.fromJson(e)).toList();
        _cache['ingredients'] = result;
        return result;
      }
      rethrow;
    }

    throw Exception("Failed to load ingredients");
  }

  static Future<Map<String, dynamic>> matchRecipes(
    List<int> ingredientIds,
    int page,
    String? category,
  ) async {
    final body = {
      "ingredient_ids": ingredientIds,
      if (category != null) "category": category,
    };
    final response = await http.post(
      Uri.parse("$baseUrl/match-recipes?page=$page"),
      headers: await _getHeaders(),
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) throw Exception("Failed to fetch recipes");
    final json = jsonDecode(response.body);
    final List data = json["data"] ?? [];
    final recipes = data.map<Recipe>((e) => Recipe.fromJson(e)).toList();
    return {"recipes": recipes, "hasMore": json["next_page_url"] != null};
  }

  static Future<Recipe> fetchRecipeDetail(int id) async {
    final key = 'recipe_$id';

    if (_cache.containsKey(key)) {
      debugPrint("CACHE HIT: recipe $id");
      return _cache[key];
    }

    debugPrint("CACHE MISS: recipe $id");

    final response = await http.get(
      Uri.parse("$baseUrl/recipes/$id"),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final result = Recipe.fromJson(jsonDecode(response.body));

      _cache[key] = result; // ✅ CACHE

      return result;
    }

    throw Exception("Failed to load recipe");
  }

  static Future<List<Recipe>> fetchFavorite() async {
    final response = await http.get(
      Uri.parse("$baseUrl/favorites"),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      List data = jsonDecode(response.body);
      return data.map((e) => Recipe.fromJson(e['recipe'])).toList();
    }
    throw Exception("Failed to load favorites");
  }

  static Future<Set<int>> fetchFavoriteIds() async {
    final response = await http.get(
      Uri.parse("$baseUrl/favorites"),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      List data = jsonDecode(response.body);
      return data.map<int>((e) => e['recipe']['id'] as int).toSet();
    }
    throw Exception("Failed to fetch favorites");
  }

  static Future<void> addToFavorites(int recipeId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/favorites"),
      headers: await _getHeaders(),
      body: jsonEncode({"recipe_id": recipeId.toString()}),
    );
    if (response.statusCode != 200) throw Exception("Failed to add favorite");
  }

  static Future<void> removeFavorite(int recipeId) async {
    final response = await http.delete(
      Uri.parse("$baseUrl/favorites/$recipeId"),
      headers: await _getHeaders(),
    );
    if (response.statusCode != 200)
      throw Exception("Failed to remove favorite");
  }

  static Future<AdminStats> fetchAdminStats() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/stats'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200)
      return AdminStats.fromJson(jsonDecode(response.body)['data']);
    throw Exception("Failed to load admin stats");
  }

  static Future<List<dynamic>> fetchPopularRecipes() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/popular'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) return jsonDecode(response.body)['data'];
    throw Exception("Failed to load popular recipes");
  }

  static List<Recipe> _parseRecipeListResponse(String body) {
    final decoded = jsonDecode(body);
    List data = decoded is Map ? (decoded['data'] ?? []) : decoded;
    return data.map((e) => Recipe.fromJson(e)).toList();
  }

  static Future<List<Recipe>> fetchRecipes() async {
    final sw = Stopwatch()..start();
    final uri = Uri.parse("$baseUrl/recipes");
    try {
      final online = await ConnectivityService.isOnline;
      if (!online) {
        final raw = await OfflineCacheService.loadRecipesJson();
        if (raw != null) {
          sw.stop();
          return _parseRecipeListResponse(raw);
        }
      }

      final response = await http.get(uri, headers: await _getHeaders());

      debugPrint("FETCH RECIPES STATUS: ${response.statusCode}");
      sw.stop();
      await PerformanceReporter.onApiCall('GET /recipes', sw.elapsedMilliseconds);

      if (response.statusCode == 200) {
        await OfflineCacheService.saveRecipesJson(response.body);
        return _parseRecipeListResponse(response.body);
      }
    } catch (e) {
      sw.stop();
      final raw = await OfflineCacheService.loadRecipesJson();
      if (raw != null) return _parseRecipeListResponse(raw);
      rethrow;
    }

    throw Exception("Failed to fetch recipes");
  }

  static Future<List<dynamic>> fetchUsers() async {
    final response = await http.get(
      Uri.parse("$baseUrl/users"),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return List<dynamic>.from(decoded["data"] ?? []);
      return List<dynamic>.from(decoded);
    }
    throw Exception("Failed to load users");
  }

  static Future<void> createRecipe({
    required String name,
    required String category,
    required String instructions,
    required List<int> ingredientIds,
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

    for (int i = 0; i < ingredientIds.length; i++) {
      request.fields['ingredient_ids[$i]'] = ingredientIds[i].toString();
    }

    if (imageFile != null) {
      final bytes = await imageFile.readAsBytes();
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
    required List<int> ingredientIds,
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

    for (int i = 0; i < ingredientIds.length; i++) {
      request.fields['ingredient_ids[$i]'] = ingredientIds[i].toString();
    }

    if (imageFile != null) {
      final bytes = await imageFile.readAsBytes();
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
    await http.post(
      Uri.parse("$baseUrl/rate"),
      headers: await _getHeaders(),
      body: jsonEncode({
        "recipe_id": recipeId.toString(),
        "rating": rating.toString(),
      }),
    );
  }

  static Future<void> logActivity(String action, int? recipeId) async {
    await http.post(
      Uri.parse("$baseUrl/activity"),
      headers: await _getHeaders(),
      body: jsonEncode({"action": action, "recipe_id": recipeId?.toString()}),
    );
  }

  static Future<List<Recipe>> fetchRecommendedRecipes() async {
    if (_cache.containsKey('recommendations')) {
      debugPrint("CACHE HIT: recommendations");
      return _cache['recommendations'];
    }

    debugPrint("CACHE MISS: recommendations");

    final response = await http.get(
      Uri.parse("$baseUrl/recommended-recipes"),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      List data = decoded is Map ? (decoded['data'] ?? []) : decoded;

      final result = data.map((e) => Recipe.fromJson(e)).toList();

      _cache['recommendations'] = result; // ✅ CACHE

      return result;
    }

    throw Exception("Failed to load recommendations");
  }

  static Future<Map<String, dynamic>> getUserProfile() async {
    final response = await http.get(
      Uri.parse('$baseUrl/user/profile'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to load profile data');
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

  static Future<Map<String, dynamic>> fetchActivityStats() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/activity-stats'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) return jsonDecode(response.body)['data'];
    throw Exception("Failed to load activity statistics");
  }

  static Future<List<dynamic>> fetchIngredientUsage({
    String? date,
    String? month,
  }) async {
    String url = '$baseUrl/admin/ingredient-usage';

    List<String> params = [];

    if (date != null) params.add('date=$date');
    if (month != null) params.add('month=$month');

    if (params.isNotEmpty) {
      url += '?' + params.join('&');
    }

    final response = await http.get(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

    final decoded = jsonDecode(response.body);

    return decoded['data'] ?? [];
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

    final response = await http.get(
      Uri.parse('$baseUrl/admin/error-logs?${q.join('&')}'),
      headers: await _getHeaders(),
    );
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
    final q = <String>['per_page=$perPage'];
    if (kind != null && kind.isNotEmpty) q.add('kind=${Uri.encodeComponent(kind)}');
    if (startDate != null && startDate.isNotEmpty) q.add('start_date=$startDate');
    if (endDate != null && endDate.isNotEmpty) q.add('end_date=$endDate');

    final response = await http.get(
      Uri.parse('$baseUrl/admin/performance-metrics?${q.join('&')}'),
      headers: await _getHeaders(),
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body['data'];
      if (list is List) return List<dynamic>.from(list);
      return [];
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

    final response = await http.get(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

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

    final response = await http.get(
      Uri.parse(url),
      headers: await _getHeaders(),
    );

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
    final response = await http.get(
      Uri.parse(
        "$baseUrl/admin/activity-logs?start_date=${start.toIso8601String()}&end_date=${end.toIso8601String()}",
      ),
      headers: await _getHeaders(),
    );

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
    final response = await http.get(
      Uri.parse('$baseUrl/admin/api-usage'),
      headers: await _getHeaders(),
    );

    final decoded = jsonDecode(response.body);

    return decoded['data'] ?? [];
  }

  static Future<Map<String, dynamic>> globalSearch(String query) async {
    final response = await http.get(Uri.parse("$baseUrl/search?query=$query"));

    print("STATUS: ${response.statusCode}");
    print("BODY: ${response.body}");

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception("Search failed");
    }
  }

  // 🔥 FIX #1: GET COLLECTIONS
  static Future<List<dynamic>> getCollections() async {
    // 1. Get the real headers that include the token from memory
    final headers = await _getHeaders();

    // 2. Debug: This will show you if the token actually exists
    print("DEBUG TOKEN: ${headers['Authorization']}");

    final response = await http.get(
      Uri.parse("$baseUrl/collections"),
      headers: headers, // ✅ Use the full headers here
    );

    print("COLLECTIONS STATUS: ${response.statusCode}");
    print("BODY: ${utf8.decode(response.bodyBytes)}");

    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    } else {
      throw Exception("Failed to load collections: ${response.statusCode}");
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
      print("CREATE ERROR: ${response.body}");
      throw Exception("Failed to create collection");
    }
  }

  // 🔥 FIX: ADD RECIPE TO COLLECTION
  static Future<void> addToCollection(int collectionId, int recipeId) async {
    final response = await http.post(
      Uri.parse("$baseUrl/collections/add"),
      headers: await _getHeaders(), // ✅ Use helper
      body: jsonEncode({"collection_id": collectionId, "recipe_id": recipeId}),
    );

    if (response.statusCode != 200) {
      throw Exception("Add to collection failed");
    }
  }

  static Future<Map<String, dynamic>> getCollectionDetail(int id) async {
    final response = await http.get(
      Uri.parse("$baseUrl/collections/$id"),
      headers: await _getHeaders(),
    );

    if (response.statusCode == 200) {
      return json.decode(utf8.decode(response.bodyBytes));
    }
    throw Exception("Failed to load recipes in this collection");
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
}
