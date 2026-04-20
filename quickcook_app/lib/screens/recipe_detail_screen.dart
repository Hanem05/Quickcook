import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ ADDED

import '../models/recipe.dart';
import '../services/api_service.dart';

class RecipeDetailScreen extends StatefulWidget {
  final int recipeId;

  const RecipeDetailScreen({super.key, required this.recipeId});

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  Recipe? recipe;
  bool loading = true;
  int? userRating;

  // --- MODERN TEAL & ZINC PALETTE ---
  static const Color primaryBrand = Color(0xFF0D9488);
  static const Color darkSlate = Color(0xFF18181B);
  static const Color bgSoft = Color(0xFFF4F4F5);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE4E4E7);
  static const Color textMain = Color(0xFF27272A);
  static const Color textMuted = Color(0xFF71717A);
  static const Color warningAmber = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    loadRecipe();
  }

  /// Persists IDs + a JSON snapshot so Home can show "Jump Back In" even if the API fails (e.g. web/CORS/offline).
  Future<void> _persistRecentSnapshot(Recipe recipe) async {
    final prefs = await SharedPreferences.getInstance();
    var ids = prefs.getStringList('recently_viewed') ?? [];
    final idStr = recipe.id.toString();
    ids.remove(idStr);
    ids.insert(0, idStr);
    if (ids.length > 10) ids = ids.sublist(0, 10);
    await prefs.setStringList('recently_viewed', ids);

    List<Map<String, dynamic>> old = [];
    final raw = prefs.getString('recently_viewed_snapshot');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          old = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (_) {}
    }
    old.removeWhere((e) => e['id'] == recipe.id);
    final merged = <Map<String, dynamic>>[
      {
        'id': recipe.id,
        'name': recipe.name,
        'imageUrl': recipe.imageUrl,
        'category': recipe.category,
      },
      ...old,
    ];
    final trimmed = merged.take(10).toList();
    await prefs.setString('recently_viewed_snapshot', jsonEncode(trimmed));
  }

  Future<void> loadRecipe() async {
    try {
      final data = await ApiService.fetchRecipeDetail(widget.recipeId);

      // ⭐ Log Activity: View Recipe
      await ApiService.logActivity("view_recipe", widget.recipeId);

      if (!mounted) return;
      setState(() {
        recipe = data;
        loading = false;
      });
      await _persistRecentSnapshot(data);
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _showSnackBar("Failed to load recipe details.", isError: true);
    }
  }

  Future<void> submitRating(int rating) async {
    setState(() => userRating = rating);

    try {
      await ApiService.rateRecipe(widget.recipeId, rating);

      ApiService.clearCache('recipe_${widget.recipeId}');

      if (!mounted) return;
      _showSnackBar("Thanks for your feedback!");
      loadRecipe(); // Reload to update average
    } catch (e) {
      if (!mounted) return;
      _showSnackBar("Failed to submit rating.", isError: true);
      setState(() => userRating = null);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        width: 400,
        backgroundColor: isError ? Colors.redAccent : darkSlate,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        backgroundColor: bgSoft,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: borderLight,
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    height: 28,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: borderLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 18,
                    width: 180,
                    decoration: BoxDecoration(
                      color: borderLight.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(color: primaryBrand),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (recipe == null) {
      return Scaffold(
        backgroundColor: bgSoft,
        appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
        body: const Center(
          child: Text(
            "Recipe not found.",
            style: TextStyle(color: textMuted, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgSoft,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            decoration: BoxDecoration(
              color: surfaceWhite.withOpacity(0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 8),
              ],
            ),
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: textMain,
                size: 20,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            _buildRecipeImage(recipe!.imageUrl),
            Transform.translate(
              offset: const Offset(0, -32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: bgSoft,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildMetaDataRow(),
                          if (recipe!.successScore != null) ...[
                            const SizedBox(height: 16),
                            _buildSuccessOutlook(),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            recipe!.name,
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: textMain,
                              letterSpacing: -1,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 32),
                          _buildRatingCard(),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => _showCollectionModal(),
                              icon: const Icon(Icons.bookmark_rounded),
                              label: const Text("Save to Collection"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryBrand,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                          _buildSectionHeader("Ingredients"),
                          const SizedBox(height: 20),
                          _buildIngredientsList(),
                          const SizedBox(height: 40),
                          _buildSectionHeader("Instructions"),
                          const SizedBox(height: 20),
                          Text(
                            recipe!.instructions,
                            style: const TextStyle(
                              fontSize: 16,
                              color: textMain,
                              height: 1.7,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 60),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipeImage(String? imageUrl) {
    return Container(
      height: 400,
      width: double.infinity,
      decoration: const BoxDecoration(color: borderLight),
      child: imageUrl != null && imageUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => const Center(
                child: CircularProgressIndicator(color: primaryBrand),
              ),
              errorWidget: (context, url, error) => const Icon(
                Icons.restaurant_menu_rounded,
                size: 80,
                color: textMuted,
              ),
            )
          : const Icon(
              Icons.restaurant_menu_rounded,
              size: 80,
              color: textMuted,
            ),
    );
  }

  Widget _buildSuccessOutlook() {
    final score = recipe!.successScore!;
    final label = recipe!.successLabel ?? '';
    final diff = recipe!.difficulty;
    final mins = recipe!.cookingTimeMinutes;

    final friendly = label.toLowerCase().contains('beginner');
    final challenging = label.toLowerCase().contains('challeng');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.insights_rounded,
            color: friendly
                ? primaryBrand
                : challenging
                    ? warningAmber
                    : textMuted,
            size: 26,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SUCCESS OUTLOOK',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: textMuted,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label.isNotEmpty ? label : 'Estimated fit',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: textMain,
                  ),
                ),
                if (diff != null || mins != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (diff != null) diff,
                      if (mins != null) '~$mins min',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '$score%',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: primaryBrand,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaDataRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (recipe!.category != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: primaryBrand.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              recipe!.category!.toUpperCase(),
              style: const TextStyle(
                color: primaryBrand,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        _buildAverageRating(recipe!.rating),
      ],
    );
  }

  Widget _buildAverageRating(double? rating) {
    return Row(
      children: [
        const Icon(Icons.star_rounded, color: warningAmber, size: 22),
        const SizedBox(width: 6),
        Text(
          rating != null ? rating.toStringAsFixed(1) : "N/A",
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: textMain,
          ),
        ),
      ],
    );
  }

  Widget _buildRatingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Rate this discovery",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: textMain,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (index) {
              final isFilled = userRating != null ? index < userRating! : false;
              return GestureDetector(
                onTap: () => submitRating(index + 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isFilled ? warningAmber : textMuted.withOpacity(0.3),
                    size: 42,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: primaryBrand,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: textMain,
          ),
        ),
      ],
    );
  }

  Widget _buildIngredientsList() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: surfaceWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderLight),
      ),
      child: Column(
        children: recipe!.ingredients.map((ingredient) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  height: 10,
                  width: 10,
                  decoration: const BoxDecoration(
                    color: primaryBrand,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    ingredient,
                    style: const TextStyle(
                      fontSize: 16,
                      color: textMain,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showCollectionModal() async {
    try {
      List collections = await ApiService.getCollections();

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          TextEditingController controller = TextEditingController();

          return StatefulBuilder(
            builder: (context, setModalState) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                  left: 20,
                  right: 20,
                  top: 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Save to Collection",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...collections.map(
                      (c) => ListTile(
                        leading: const Icon(Icons.folder, color: primaryBrand),
                        title: Text(c['name']),
                        onTap: () async {
                          try {
                            await ApiService.addToCollection(
                              c['id'],
                              widget.recipeId,
                            );
                            if (!mounted) return;
                            Navigator.pop(context);
                            _showSnackBar("Saved to ${c['name']}!");
                          } catch (e) {
                            _showSnackBar("Could not save.", isError: true);
                          }
                        },
                      ),
                    ),
                    const Divider(),
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        hintText: "Create new folder...",
                        prefixIcon: Icon(Icons.create_new_folder_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (controller.text.isEmpty) return;
                          try {
                            // 1. Create Folder
                            await ApiService.createCollection(controller.text);
                            // 2. Refresh list to get ID
                            List updated = await ApiService.getCollections();
                            final newCol = updated.firstWhere(
                              (c) => c['name'] == controller.text,
                            );
                            // 3. Auto-save current recipe
                            await ApiService.addToCollection(
                              newCol['id'],
                              widget.recipeId,
                            );

                            if (!mounted) return;
                            Navigator.pop(context);
                            _showSnackBar("Created and saved!");
                          } catch (e) {
                            _showSnackBar(
                              "Failed to create folder.",
                              isError: true,
                            );
                          }
                        },
                        child: const Text("Create and Save"),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      _showSnackBar("Failed to load collections.", isError: true);
    }
  }
}
