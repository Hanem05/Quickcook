import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'recipe_detail_screen.dart';

class CollectionDetailScreen extends StatefulWidget {
  final int collectionId;
  final String collectionName;
  final Map<String, dynamic>? initialData;

  const CollectionDetailScreen({
    super.key,
    required this.collectionId,
    required this.collectionName,
    this.initialData,
  });

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  Map<String, dynamic>? _data;
  bool _initialLoading = true;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData ?? ApiService.cachedCollectionDetail(widget.collectionId);
    if (_data != null) _initialLoading = false;
    _load();
  }

  String? _recipeImageUrl(Map recipe) {
    final raw = (recipe['image'] ??
            recipe['image_url'] ??
            recipe['thumbnail'] ??
            recipe['thumbnail_url'])
        ?.toString()
        .trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

    final base = ApiService.baseUrl;
    final uri = Uri.tryParse(base);
    if (uri == null) return raw;
    final origin = '${uri.scheme}://${uri.authority}';
    if (raw.startsWith('/')) return '$origin$raw';
    return '$origin/$raw';
  }

  Future<void> _load({bool force = false}) async {
    try {
      final data =
          await ApiService.getCollectionDetail(widget.collectionId, forceRefresh: force);
      if (!mounted) return;
      setState(() {
        _data = data;
        _initialLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _initialLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final recipes = (_data?['recipes'] as List?) ?? const [];
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        title: Text(widget.collectionName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: cs.outlineVariant),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: Builder(
          builder: (_) {
            if (_initialLoading && recipes.isEmpty) {
              return Center(
                child: CircularProgressIndicator(color: cs.primary),
              );
            }
            if (recipes.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Icon(Icons.folder_open_rounded, size: 52, color: cs.onSurfaceVariant),
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      "This collection is empty.",
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.grid_view_rounded, color: cs.primary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        "${recipes.length} recipe${recipes.length == 1 ? '' : 's'} in this collection",
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: recipes.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.18,
                  ),
                  itemBuilder: (context, index) {
                    final recipe = recipes[index] as Map;
                    final recipeName = recipe['name']?.toString() ?? 'Recipe';
                    final recipeId = int.tryParse(recipe['id']?.toString() ?? '') ?? 0;
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: recipeId <= 0
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RecipeDetailScreen(recipeId: recipeId),
                                ),
                              );
                            },
                      child: Ink(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(
                                  height: 88,
                                  width: double.infinity,
                                  child: Builder(
                                    builder: (context) {
                                      final imageUrl = _recipeImageUrl(recipe);
                                      if (imageUrl == null) {
                                        return Container(
                                          color: cs.surfaceContainerLow,
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.menu_book_rounded,
                                            size: 24,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        );
                                      }
                                      return CachedNetworkImage(
                                        imageUrl: imageUrl,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 420,
                                        placeholder: (context, url) => Container(
                                          color: cs.surfaceContainerLow,
                                          alignment: Alignment.center,
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: cs.primary,
                                            ),
                                          ),
                                        ),
                                        errorWidget: (context, url, error) => Container(
                                          color: cs.surfaceContainerLow,
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.broken_image_rounded,
                                            size: 24,
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 9),
                              Text(
                                recipeName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  height: 1.25,
                                ),
                              ),
                              const Spacer(),
                              Row(
                                children: [
                                  Icon(
                                    Icons.open_in_new_rounded,
                                    size: 14,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Open recipe",
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
