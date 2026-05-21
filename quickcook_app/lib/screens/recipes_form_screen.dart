import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../services/api_service.dart';
import '../utils/recipe_image_resolver.dart';
import '../theme/app_colors.dart';
import '../widgets/recipe_image.dart';

class RecipeFormScreen extends StatefulWidget {
  final Recipe? recipe;
  final int? recipeId;

  const RecipeFormScreen({super.key, this.recipe, this.recipeId});

  @override
  State<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

class _RecipeFormScreenState extends State<RecipeFormScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController instructionsController = TextEditingController();
  final TextEditingController cookingTimeController = TextEditingController(
    text: '30',
  );
  final TextEditingController ingredientInputController = TextEditingController();

  XFile? _pickedImage;
  Uint8List? _imageBytes;
  String? _existingImageUrl;

  List<String>? ingredientEntries;
  List<Ingredient> _dbIngredients = [];
  List<String> _ingredientSuggestions = [];

  String selectedCategory = 'Breakfast';
  String selectedDifficulty = 'medium';
  bool isLoading = false;
  String? nameError;
  String? instructionsError;
  String? cookingTimeError;

  static const Color primaryBrand = AppColors.brand;
  static const Color darkSlate = AppColors.darkSlate;
  static const Color bgSoft = AppColors.bgSoft;
  static const Color surfaceWhite = AppColors.surfaceWhite;
  static const Color borderLight = AppColors.borderLight;
  static const Color textMain = AppColors.textMain;
  static const Color textMuted = AppColors.textMuted;

  final List<String> categories = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Dessert',
    'Snacks',
    'Drinks',
    'General',
  ];

  @override
  void initState() {
    super.initState();

    if (widget.recipe != null) {
      nameController.text = widget.recipe!.name;
      instructionsController.text = widget.recipe!.instructions;
      _existingImageUrl = widget.recipe!.imageUrl;
      ingredientEntries = widget.recipe!.ingredients
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      if (categories.contains(widget.recipe!.category)) {
        selectedCategory = widget.recipe!.category!;
      }
      selectedDifficulty = widget.recipe!.difficulty ?? 'medium';
      cookingTimeController.text =
          (widget.recipe!.cookingTimeMinutes ?? 30).toString();
    } else {
      ingredientEntries = <String>[];
    }
    unawaited(_loadDbIngredients());
    unawaited(_hydrateRecipeForEdit());
  }

  Future<void> _hydrateRecipeForEdit() async {
    final id = widget.recipeId ?? widget.recipe?.id;
    if (id == null) return;
    final needsDetail =
        widget.recipe == null || widget.recipe!.ingredients.isEmpty;
    if (!needsDetail && widget.recipe != null) return;

    try {
      final full = await ApiService.fetchRecipeDetail(id);
      if (!mounted) return;
      setState(() {
        nameController.text = full.name;
        instructionsController.text = full.instructions;
        _existingImageUrl = RecipeImageResolver.networkUrl(full.imageUrl);
        ingredientEntries = full.ingredients
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
        if (categories.contains(full.category)) {
          selectedCategory = full.category!;
        }
        selectedDifficulty = full.difficulty ?? 'medium';
        cookingTimeController.text =
            (full.cookingTimeMinutes ?? 30).toString();
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    nameController.dispose();
    instructionsController.dispose();
    cookingTimeController.dispose();
    ingredientInputController.dispose();
    super.dispose();
  }

  Future<void> _loadDbIngredients() async {
    try {
      final data = await ApiService.fetchIngredients();
      if (!mounted) return;
      setState(() => _dbIngredients = data);
    } catch (_) {}
  }

  void _updateIngredientSuggestions(String raw) {
    final q = raw.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() => _ingredientSuggestions = []);
      return;
    }
    final matches = _dbIngredients
        .map((e) => e.name.trim())
        .where((name) => name.isNotEmpty)
        .where((name) => name.toLowerCase().contains(q))
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    setState(() => _ingredientSuggestions = matches.take(8).toList());
  }

  Future<void> _addIngredientEntry([String? value]) async {
    ingredientEntries ??= <String>[];
    final raw = (value ?? ingredientInputController.text).trim();
    if (raw.isEmpty) return;

    final parts = raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;

    final existingLower = ingredientEntries!.map((e) => e.toLowerCase()).toSet();
    final dbLower = _dbIngredients.map((e) => e.name.trim().toLowerCase()).toSet();
    bool addedAny = false;
    bool createdAny = false;
    bool skippedLocalDuplicate = false;
    for (final part in parts) {
      final key = part.toLowerCase();
      if (existingLower.contains(key)) {
        skippedLocalDuplicate = true;
        continue;
      }
      if (!dbLower.contains(key)) {
        try {
          await ApiService.createIngredient(part);
          createdAny = true;
          dbLower.add(key);
          _dbIngredients = [
            ..._dbIngredients,
            Ingredient(id: -DateTime.now().microsecondsSinceEpoch, name: part),
          ];
        } catch (_) {
          await _loadDbIngredients();
          final refreshedSet =
              _dbIngredients.map((e) => e.name.trim().toLowerCase()).toSet();
          if (!refreshedSet.contains(key)) {
            if (!mounted) return;
            _showSnackBar("Failed to add ingredient '$part'.", isError: true);
            continue;
          }
        }
      }
      ingredientEntries!.add(part);
      existingLower.add(key);
      addedAny = true;
    }

    ingredientInputController.clear();
    if (!mounted) return;
    setState(() {
      _ingredientSuggestions = [];
    });
    if (createdAny) {
      _showSnackBar("New ingredient(s) added to database.");
    } else if (skippedLocalDuplicate && !addedAny) {
      _showSnackBar("Ingredient already added in this recipe.");
    }
    if (addedAny) {
      setState(() {});
    }
  }

  void _removeIngredientEntry(String value) {
    ingredientEntries ??= <String>[];
    setState(() {
      ingredientEntries!.remove(value);
    });
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    try {
      // FIX: Removed 'imageQuality: 80' because it causes crashes on Flutter Web!
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);

      if (image != null) {
        // Read bytes for universal (Web/Mobile) preview
        final Uint8List bytes = await image.readAsBytes();

        setState(() {
          _pickedImage = image;
          _imageBytes = bytes;
          _existingImageUrl = null;
        });
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
      // Updated this to show you the exact error if it happens again!
      _showSnackBar("Failed to pick image: $e", isError: true);
    }
  }

  Future<void> saveRecipe() async {
    _validateName(nameController.text);
    _validateInstructions(instructionsController.text);
    _validateCookingTime(cookingTimeController.text);

    final isNew = widget.recipe == null && widget.recipeId == null;
    final missingImage =
        isNew && _pickedImage == null && (_existingImageUrl == null || _existingImageUrl!.isEmpty);

    if (nameError != null ||
        instructionsError != null ||
        cookingTimeError != null ||
        (ingredientEntries ?? const <String>[]).isEmpty ||
        missingImage) {
      _showSnackBar(
        isNew
            ? "Please fix highlighted fields, add ingredients, and upload an image."
            : "Please fix highlighted fields and add at least one ingredient.",
        isError: true,
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      if (widget.recipe == null) {
        await ApiService.createRecipe(
          name: nameController.text,
          category: selectedCategory,
          instructions: instructionsController.text,
          ingredientNames: List<String>.from(ingredientEntries ?? const <String>[]),
          difficulty: selectedDifficulty,
          cookingTime: int.tryParse(cookingTimeController.text) ?? 30,
          imageFile: _pickedImage,
        );
      } else {
        final id = widget.recipe?.id ?? widget.recipeId;
        if (id == null) {
          throw Exception('Missing recipe id');
        }
        await ApiService.updateRecipe(
          id: id,
          name: nameController.text,
          category: selectedCategory,
          instructions: instructionsController.text,
          ingredientNames: List<String>.from(ingredientEntries ?? const <String>[]),
          difficulty: selectedDifficulty,
          cookingTime: int.tryParse(cookingTimeController.text) ?? 30,
          imageFile: _pickedImage,
        );
      }

      if (!mounted) return;
      _showSnackBar(
        widget.recipe == null ? "Recipe published!" : "Recipe updated!",
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      debugPrint("Save error: $e");
      _showSnackBar("Failed to save recipe.", isError: true);
    } finally {
      if (mounted) setState(() => isLoading = false);
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
    return Scaffold(
      backgroundColor: bgSoft,
      appBar: AppBar(
        backgroundColor: surfaceWhite,
        elevation: 0,
        centerTitle: false,
        title: Text(
          widget.recipe == null
              ? "Recipe Library / New Entry"
              : "Recipe Library / Edit Entry",
          style: const TextStyle(
            color: textMain,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: borderLight, height: 1),
        ),
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                Column(
                  children: [
                    Stack(
                      children: [
                        Container(
                          height: 140,
                          width: 140,
                          decoration: BoxDecoration(
                            color: surfaceWhite,
                            shape: BoxShape.circle,
                            border: Border.all(color: borderLight, width: 4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            image: _imageBytes != null
                                ? DecorationImage(
                                    image: MemoryImage(_imageBytes!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: _imageBytes == null
                              ? (widget.recipe != null || widget.recipeId != null)
                                  ? ClipOval(
                                      child: RecipeImage(
                                        recipeId: widget.recipe?.id ?? widget.recipeId ?? 0,
                                        imageUrl: _existingImageUrl,
                                        width: 140,
                                        height: 140,
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.restaurant_menu_rounded,
                                      size: 50,
                                      color: textMuted,
                                    )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: primaryBrand,
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              onPressed: _pickImage,
                              icon: const Icon(
                                Icons.add_a_photo_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              tooltip: "Upload Photo",
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _pickedImage != null
                          ? _pickedImage!.name
                          : (_existingImageUrl != null
                                ? "Existing Network Image"
                                : "No image selected"),
                      style: const TextStyle(
                        fontSize: 12,
                        color: textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: surfaceWhite,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderLight),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader("Basic Information"),
                      const SizedBox(height: 24),
                      _buildTextField(
                        controller: nameController,
                        label: "Recipe Name",
                        icon: Icons.title_rounded,
                        errorText: nameError,
                        onChanged: _validateName,
                      ),
                      const SizedBox(height: 24),

                      const Text(
                        "Dish Category",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedCategory,
                        dropdownColor: surfaceWhite,
                        style: const TextStyle(
                          color: textMain,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                        decoration: _inputDecoration(
                          Icons.category_outlined,
                          "Select Category",
                        ),
                        items: categories
                            .map(
                              (cat) => DropdownMenuItem(
                                value: cat,
                                child: Text(cat),
                              ),
                            )
                            .toList(),
                        onChanged: (val) =>
                            setState(() => selectedCategory = val!),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        value: selectedDifficulty,
                        dropdownColor: surfaceWhite,
                        decoration: _inputDecoration(
                          Icons.speed_rounded,
                          "Difficulty",
                        ),
                        items: const [
                          DropdownMenuItem(value: 'easy', child: Text('Easy')),
                          DropdownMenuItem(value: 'medium', child: Text('Medium')),
                          DropdownMenuItem(value: 'hard', child: Text('Hard')),
                        ],
                        onChanged: (val) =>
                            setState(() => selectedDifficulty = val ?? 'medium'),
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        controller: cookingTimeController,
                        label: "Cooking Time (minutes)",
                        icon: Icons.timer_outlined,
                        keyboardType: TextInputType.number,
                        errorText: cookingTimeError,
                        onChanged: _validateCookingTime,
                      ),

                      const SizedBox(height: 40),
                      _buildSectionHeader("Cooking Instructions"),
                      const SizedBox(height: 24),
                      _buildTextField(
                        controller: instructionsController,
                        label: "Step-by-Step Guide",
                        icon: Icons.description_outlined,
                        maxLines: 6,
                        errorText: instructionsError,
                        onChanged: _validateInstructions,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: surfaceWhite,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionHeader("Ingredients Input"),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: bgSoft,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderLight),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.tips_and_updates_outlined, color: textMuted, size: 17),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                "Type ingredients then press Enter or Add. Existing names are reused automatically.",
                                style: TextStyle(
                                  color: textMuted,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: bgSoft.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderLight),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: ingredientInputController,
                                onChanged: _updateIngredientSuggestions,
                                onSubmitted: (_) {
                                  _addIngredientEntry();
                                },
                                decoration: _inputDecoration(
                                  Icons.kitchen_rounded,
                                  "Enter ingredient (e.g. Garlic)",
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  _addIngredientEntry();
                                },
                                icon: const Icon(Icons.add_rounded, size: 17),
                                label: const Text("Add"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryBrand,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_ingredientSuggestions.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: surfaceWhite,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderLight),
                          ),
                          child: Column(
                            children: _ingredientSuggestions
                                .map(
                                  (name) => ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 18,
                                      color: primaryBrand,
                                    ),
                                    title: Text(
                                      name,
                                      style: const TextStyle(
                                        color: textMain,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    subtitle: const Text(
                                      "Existing ingredient in database",
                                      style: TextStyle(
                                        color: textMuted,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    onTap: () => _addIngredientEntry(name),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      if ((ingredientEntries ?? const <String>[]).isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: bgSoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderLight),
                          ),
                          child: const Text(
                            "No ingredients added yet.",
                            style: TextStyle(
                              color: textMuted,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: bgSoft.withOpacity(0.55),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderLight),
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 10,
                            children: (ingredientEntries ?? const <String>[])
                                .map(
                                  (ing) => InputChip(
                                    label: Text(
                                      ing,
                                      style: const TextStyle(
                                        color: textMain,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    backgroundColor: surfaceWhite,
                                    side: const BorderSide(color: borderLight),
                                    onDeleted: () => _removeIngredientEntry(ing),
                                    deleteIconColor: textMuted,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : saveRecipe,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryBrand,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            widget.recipe == null
                                ? "Add to Recipes"
                                : "Commit Updates",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: primaryBrand,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: textMain,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? errorText,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: textMuted,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: textMain,
            fontSize: 14,
          ),
          decoration: _inputDecoration(icon, "Enter $label", errorText: errorText),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(IconData icon, String hint, {String? errorText}) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: textMuted, size: 20),
      filled: true,
      fillColor: bgSoft,
      hintText: hint,
      hintStyle: const TextStyle(
        color: textMuted,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryBrand, width: 1.5),
      ),
      errorText: errorText,
    );
  }

  void _validateName(String value) {
    final v = value.trim();
    setState(() {
      if (v.isEmpty) {
        nameError = 'Recipe name is required.';
      } else if (v.length < 3) {
        nameError = 'Recipe name must be at least 3 characters.';
      } else {
        nameError = null;
      }
    });
  }

  void _validateInstructions(String value) {
    final v = value.trim();
    setState(() {
      if (v.isEmpty) {
        instructionsError = 'Instructions are required.';
      } else if (v.length < 20) {
        instructionsError = 'Instructions are too short.';
      } else {
        instructionsError = null;
      }
    });
  }

  void _validateCookingTime(String value) {
    final v = int.tryParse(value.trim());
    setState(() {
      if (v == null) {
        cookingTimeError = 'Enter cooking time in minutes.';
      } else if (v < 1 || v > 1440) {
        cookingTimeError = 'Cooking time must be between 1 and 1440.';
      } else {
        cookingTimeError = null;
      }
    });
  }
}
