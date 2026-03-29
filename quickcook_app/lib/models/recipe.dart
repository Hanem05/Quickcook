class Recipe {
  final int id;
  final String name;
  final String instructions;
  final List<String> ingredients;
  final String? imageUrl;
  final String? category;
  final double? rating;

  Recipe({
    required this.id,
    required this.name,
    required this.instructions,
    required this.ingredients,
    this.imageUrl,
    this.category,
    this.rating,
  });

  factory Recipe.fromJson(Map<String, dynamic> json) {
    List<String> ingredientNames = [];

    if (json['ingredients'] != null) {
      ingredientNames = (json['ingredients'] as List).map((ingredient) {
        // Safely handle both Object and String returns
        if (ingredient is Map) {
          return ingredient['name']?.toString() ?? 'Unknown Ingredient';
        }
        return ingredient.toString();
      }).toList();
    }

    // Safely parse the ID just in case caching turned it into a String
    int parsedId = json['id'] is int
        ? json['id']
        : int.tryParse(json['id']?.toString() ?? '0') ?? 0;

    // Temporary debug print - check your console for this!
    print("DEBUG JSON for ${json['name']}: ${json['instructions']}");

    return Recipe(
      id: parsedId,
      name: json['name']?.toString() ?? 'Unknown Recipe',
      // Check if your API uses 'instructions' or 'description'
      instructions:
          json['instructions']?.toString() ?? 'No instructions provided.',
      ingredients: ingredientNames,
      // FIX: Match the key to what you have in Laravel (likely 'image')
      imageUrl: json['image']?.toString() ?? json['image_url']?.toString(),
      category: json['category']?.toString(),
      rating: json['average_rating'] != null
          ? double.tryParse(json['average_rating'].toString())
          : null,
    );
  }
}
