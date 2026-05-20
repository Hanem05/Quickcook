import '../utils/recipe_image_resolver.dart';

class Recipe {
  final int id;
  final String name;
  final String instructions;
  final List<String> ingredients;
  final String? imageUrl;
  final String? category;
  final double? rating;
  final int? userRating;

  /// Ingredient match flow (match-recipes API).
  final double? matchCoveragePct;
  final int? missingIngredientsApprox;

  /// Detail / success prediction (show API).
  final int? successScore;
  final String? successLabel;
  final String? difficulty;
  final int? cookingTimeMinutes;

  Recipe({
    required this.id,
    required this.name,
    required this.instructions,
    required this.ingredients,
    this.imageUrl,
    this.category,
    this.rating,
    this.userRating,
    this.matchCoveragePct,
    this.missingIngredientsApprox,
    this.successScore,
    this.successLabel,
    this.difficulty,
    this.cookingTimeMinutes,
  });

  /// Lightweight thumbnail URL for list/grid cards.
  ///
  /// TheMealDB supports a small preview image by appending `/preview` to its
  /// image URLs. Cards should use this to avoid downloading many full-size JPGs
  /// at once on Android emulator / low-end devices. Detail pages can still use
  /// [imageUrl] for the full image.
  String? get thumbnailUrl {
    final url = RecipeImageResolver.networkUrl(imageUrl)?.trim();
    if (url == null || url.isEmpty) return null;
    if (url.contains('themealdb.com/images/media/meals') &&
        !url.endsWith('/preview')) {
      return '$url/preview';
    }
    return url;
  }

  /// Bundled photo from [imgs] (used when network image fails).
  String get bundledImageAsset => RecipeImageResolver.bundledFallback(id);

  factory Recipe.fromJson(Map<String, dynamic> json) {
    List<String> ingredientNames = [];

    if (json['ingredients'] != null) {
      ingredientNames = (json['ingredients'] as List).map((ingredient) {
        if (ingredient is Map) {
          return ingredient['name']?.toString() ?? 'Unknown Ingredient';
        }
        return ingredient.toString();
      }).toList();
    }

    int parsedId = json['id'] is int
        ? json['id'] as int
        : int.tryParse(json['id']?.toString() ?? '0') ?? 0;

    final cov = json['match_coverage_pct'];
    final miss = json['missing_ingredients'];

    return Recipe(
      id: parsedId,
      name: json['name']?.toString() ?? 'Unknown Recipe',
      instructions:
          json['instructions']?.toString() ?? 'No instructions provided.',
      ingredients: ingredientNames,
      // Prefer backend-resolved absolute URL; raw `image` may be a relative
      // storage path like `recipes/foo.jpg` which won't load directly.
      imageUrl: json['image_url']?.toString() ?? json['image']?.toString(),
      category: json['category']?.toString(),
      rating: json['average_rating'] != null
          ? double.tryParse(json['average_rating'].toString())
          : null,
      userRating: json['user_rating'] != null
          ? int.tryParse(json['user_rating'].toString())
          : null,
      matchCoveragePct: cov != null ? double.tryParse(cov.toString()) : null,
      missingIngredientsApprox:
          miss is int ? miss : int.tryParse(miss?.toString() ?? ''),
      successScore: json['success_score'] != null
          ? int.tryParse(json['success_score'].toString())
          : null,
      successLabel: json['success_label']?.toString(),
      difficulty: json['difficulty']?.toString(),
      cookingTimeMinutes: json['cooking_time'] != null
          ? int.tryParse(json['cooking_time'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'instructions': instructions,
        'ingredients': ingredients,
        'image_url': imageUrl,
        'category': category,
        'average_rating': rating,
        if (userRating != null) 'user_rating': userRating,
        if (matchCoveragePct != null)
          'match_coverage_pct': matchCoveragePct,
        if (missingIngredientsApprox != null)
          'missing_ingredients': missingIngredientsApprox,
        if (successScore != null) 'success_score': successScore,
        if (successLabel != null) 'success_label': successLabel,
        if (difficulty != null) 'difficulty': difficulty,
        if (cookingTimeMinutes != null) 'cooking_time': cookingTimeMinutes,
      };
}
