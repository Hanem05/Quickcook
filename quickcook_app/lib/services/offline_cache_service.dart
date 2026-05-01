import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class OfflineCacheService {
  static const _recipesKey = 'offline_cache_recipes_json';
  static const _ingredientsKey = 'offline_cache_ingredients_json';
  static const _homeFeedKey = 'offline_cache_home_feed_json';
  static const _favoritesKey = 'offline_cache_favorites_json';
  static const _collectionsKey = 'offline_cache_collections_json';
  static const _collectionDetailPrefix = 'offline_cache_collection_detail_';
  static const _recipeDetailPrefix = 'offline_cache_recipe_detail_';
  static const _pendingActivitiesKey = 'offline_pending_activities_json';

  static Future<void> saveRecipesJson(String json) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_recipesKey, json);
    await p.setInt(
      'offline_cache_recipes_at',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<String?> loadRecipesJson() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_recipesKey);
  }

  static Future<void> saveIngredientsJson(String json) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_ingredientsKey, json);
  }

  static Future<String?> loadIngredientsJson() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_ingredientsKey);
  }

  static Future<void> saveHomeFeedJson(String json) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_homeFeedKey, json);
  }

  static Future<String?> loadHomeFeedJson() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_homeFeedKey);
  }

  static Future<void> saveFavoritesJson(String json) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_favoritesKey, json);
  }

  static Future<String?> loadFavoritesJson() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_favoritesKey);
  }

  static Future<void> saveCollectionsJson(String json) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_collectionsKey, json);
  }

  static Future<String?> loadCollectionsJson() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_collectionsKey);
  }

  static Future<void> saveCollectionDetailJson(int id, String json) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('$_collectionDetailPrefix$id', json);
  }

  static Future<String?> loadCollectionDetailJson(int id) async {
    final p = await SharedPreferences.getInstance();
    return p.getString('$_collectionDetailPrefix$id');
  }

  static Future<void> saveRecipeDetailJson(int id, String json) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('$_recipeDetailPrefix$id', json);
  }

  static Future<String?> loadRecipeDetailJson(int id) async {
    final p = await SharedPreferences.getInstance();
    return p.getString('$_recipeDetailPrefix$id');
  }

  static Future<void> enqueuePendingActivity(Map<String, dynamic> payload) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_pendingActivitiesKey);
    final list = raw == null ? <dynamic>[] : (raw.isEmpty ? <dynamic>[] : (jsonDecode(raw) as List<dynamic>));
    list.add(payload);
    await p.setString(_pendingActivitiesKey, jsonEncode(list));
  }

  static Future<List<Map<String, dynamic>>> loadPendingActivities() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_pendingActivitiesKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> clearPendingActivities() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_pendingActivitiesKey);
  }
}
