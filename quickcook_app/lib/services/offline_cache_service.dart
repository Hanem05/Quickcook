import 'package:shared_preferences/shared_preferences.dart';

class OfflineCacheService {
  static const _recipesKey = 'offline_cache_recipes_json';
  static const _ingredientsKey = 'offline_cache_ingredients_json';

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
}
