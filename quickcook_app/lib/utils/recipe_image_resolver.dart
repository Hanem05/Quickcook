import '../services/api_service.dart';

/// Maps recipes to bundled seed photos and fixes API image URLs for emulators/phones.
class RecipeImageResolver {
  RecipeImageResolver._();

  static const List<String> bundledAssets = [
    'assets/images/recipes/seed-01.jpg',
    'assets/images/recipes/seed-02.jpg',
    'assets/images/recipes/seed-03.jpg',
    'assets/images/recipes/seed-04.jpg',
    'assets/images/recipes/seed-05.jpg',
    'assets/images/recipes/seed-06.jpg',
    'assets/images/recipes/seed-07.webp',
    'assets/images/recipes/seed-08.jpg',
    'assets/images/recipes/seed-09.jpg',
    'assets/images/recipes/seed-10.webp',
    'assets/images/recipes/seed-11.jpg',
    'assets/images/recipes/seed-12.jpg',
    'assets/images/recipes/seed-13.webp',
    'assets/images/recipes/seed-14.jpg',
    'assets/images/recipes/seed-15.jpg',
    'assets/images/recipes/seed-16.png',
    'assets/images/recipes/seed-17.jpg',
    'assets/images/recipes/seed-18.avif',
    'assets/images/recipes/seed-19.webp',
    'assets/images/recipes/seed-20.jpg',
    'assets/images/recipes/seed-21.jpg',
    'assets/images/recipes/seed-22.jpg',
    'assets/images/recipes/seed-23.webp',
    'assets/images/recipes/seed-24.jpg',
    'assets/images/recipes/seed-25.jpg',
    'assets/images/recipes/seed-26.jpg',
  ];

  /// Rewrites localhost/relative paths so [CachedNetworkImage] can load on device.
  static String? networkUrl(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('assets/')) return null;

    final apiUri = Uri.tryParse(ApiService.baseUrl);
    if (apiUri == null || apiUri.host.isEmpty) return trimmed;

    final origin = Uri(
      scheme: apiUri.scheme,
      host: apiUri.host,
      port: apiUri.hasPort ? apiUri.port : null,
    );

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final parsed = Uri.tryParse(trimmed);
      if (parsed == null) return trimmed;
      if (parsed.host == 'localhost' ||
          parsed.host == '127.0.0.1' ||
          parsed.host == 'nginx') {
        return parsed.replace(
          scheme: origin.scheme,
          host: origin.host,
          port: origin.hasPort ? origin.port : null,
        ).toString();
      }
      return trimmed;
    }

    var path = trimmed.startsWith('/') ? trimmed.substring(1) : trimmed;
    if (!path.startsWith('storage/')) {
      path = 'storage/$path';
    }
    return origin.replace(path: '/$path').toString();
  }

  static String bundledAssetForRecipeId(int id) {
    if (bundledAssets.isEmpty || id <= 0) {
      return bundledAssets.isNotEmpty ? bundledAssets.first : '';
    }
    return bundledAssets[(id - 1) % bundledAssets.length];
  }

  /// Prefer API image; fall back to bundled seed photo (always works offline).
  static String? primaryNetworkUrl(String? apiImageUrl, int recipeId) {
    return networkUrl(apiImageUrl);
  }

  static String bundledFallback(int recipeId) => bundledAssetForRecipeId(recipeId);
}
