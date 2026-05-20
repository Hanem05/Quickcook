import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../utils/recipe_image_resolver.dart';

/// Recipe photo: network (storage/API) with bundled [imgs] fallback.
class RecipeImage extends StatelessWidget {
  const RecipeImage({
    super.key,
    required this.recipeId,
    this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
    this.memCacheWidth,
  });

  final int recipeId;
  final String? imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final int? memCacheWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final network = RecipeImageResolver.primaryNetworkUrl(imageUrl, recipeId);
    final asset = RecipeImageResolver.bundledFallback(recipeId);

    Widget child;
    if (network != null && network.isNotEmpty) {
      child = CachedNetworkImage(
        imageUrl: network,
        fit: fit,
        width: width,
        height: height,
        memCacheWidth: memCacheWidth,
        placeholder: (_, __) => _placeholder(cs, asset),
        errorWidget: (_, __, ___) => _assetOrIcon(asset, cs),
      );
    } else {
      child = _assetOrIcon(asset, cs);
    }

    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius!, child: child);
    }

    return SizedBox(width: width, height: height, child: child);
  }

  Widget _placeholder(ColorScheme cs, String asset) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _assetOrIcon(asset, cs),
        ColoredBox(
          color: cs.surface.withValues(alpha: 0.35),
        ),
      ],
    );
  }

  Widget _assetOrIcon(String asset, ColorScheme cs) {
    if (asset.isNotEmpty) {
      return Image.asset(
        asset,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => _icon(cs),
      );
    }
    return _icon(cs);
  }

  Widget _icon(ColorScheme cs) {
    return ColoredBox(
      color: cs.surfaceContainerLow,
      child: Center(
        child: Icon(
          Icons.restaurant_menu_rounded,
          color: cs.onSurfaceVariant,
          size: 38,
        ),
      ),
    );
  }
}
