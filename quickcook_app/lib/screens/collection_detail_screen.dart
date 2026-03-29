import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'recipe_detail_screen.dart';

class CollectionDetailScreen extends StatelessWidget {
  final int collectionId;
  final String collectionName;

  const CollectionDetailScreen({
    super.key,
    required this.collectionId,
    required this.collectionName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(collectionName)),
      body: FutureBuilder<Map<String, dynamic>>(
        future: ApiService.getCollectionDetail(
          collectionId,
        ), // Fetching recipes
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!['recipes'].isEmpty) {
            return const Center(child: Text("This collection is empty."));
          }

          final recipes = snapshot.data!['recipes'];

          return ListView.builder(
            itemCount: recipes.length,
            itemBuilder: (context, index) {
              final recipe = recipes[index];
              return ListTile(
                title: Text(recipe['name']),
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
    );
  }
}
