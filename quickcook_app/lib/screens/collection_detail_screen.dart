import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'recipe_detail_screen.dart';

class CollectionDetailScreen extends StatefulWidget {
  final int collectionId;
  final String collectionName;

  const CollectionDetailScreen({
    super.key,
    required this.collectionId,
    required this.collectionName,
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
    _load();
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
    final recipes = (_data?['recipes'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(widget.collectionName)),
      body: RefreshIndicator(
        onRefresh: () => _load(force: true),
        child: Builder(
          builder: (_) {
            if (_initialLoading && recipes.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (recipes.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text("This collection is empty.")),
                ],
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              itemCount: recipes.length,
              itemBuilder: (context, index) {
                final recipe = recipes[index];
                return ListTile(
                  title: Text(recipe['name']?.toString() ?? 'Recipe'),
                  subtitle: const Text("Tap to view recipe"),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            RecipeDetailScreen(recipeId: recipe['id']),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
