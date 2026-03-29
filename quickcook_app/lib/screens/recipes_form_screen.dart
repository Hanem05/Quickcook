import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../services/api_service.dart';

class RecipeFormScreen extends StatefulWidget {
  final Recipe? recipe;

  const RecipeFormScreen({super.key, this.recipe});

  @override
  State<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

class _RecipeFormScreenState extends State<RecipeFormScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController instructionsController = TextEditingController();

  XFile? _pickedImage;
  Uint8List? _imageBytes;
  String? _existingImageUrl;

  List<Ingredient> ingredients = [];
  Set<int> selectedIngredients = {};

  String selectedCategory = 'Breakfast';
  bool isLoading = false;

  static const Color primaryBrand = Color(0xFF0D9488);
  static const Color darkSlate = Color(0xFF18181B);
  static const Color bgSoft = Color(0xFFF4F4F5);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE4E4E7);
  static const Color textMain = Color(0xFF27272A);
  static const Color textMuted = Color(0xFF71717A);

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
    loadIngredients();

    if (widget.recipe != null) {
      nameController.text = widget.recipe!.name;
      instructionsController.text = widget.recipe!.instructions;
      _existingImageUrl = widget.recipe!.imageUrl;

      if (categories.contains(widget.recipe!.category)) {
        selectedCategory = widget.recipe!.category!;
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    instructionsController.dispose();
    super.dispose();
  }

  Future<void> loadIngredients() async {
    try {
      final data = await ApiService.fetchIngredients();
      if (!mounted) return;
      setState(() {
        ingredients = data;
        if (widget.recipe != null) {
          for (String recipeIngredientName in widget.recipe!.ingredients) {
            try {
              final matchedIngredient = ingredients.firstWhere(
                (ing) => ing.name == recipeIngredientName,
              );
              selectedIngredients.add(matchedIngredient.id);
            } catch (e) {
              debugPrint(
                "Could not find ID for ingredient: $recipeIngredientName",
              );
            }
          }
        }
      });
    } catch (e) {
      _showSnackBar("Failed to load ingredients.", isError: true);
    }
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
    if (nameController.text.isEmpty ||
        instructionsController.text.isEmpty ||
        selectedIngredients.isEmpty ||
        (_existingImageUrl == null && _pickedImage == null)) {
      _showSnackBar(
        "Please fill all fields, select ingredients, and upload an image",
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
          ingredientIds: selectedIngredients.toList(),
          imageFile: _pickedImage,
        );
      } else {
        await ApiService.updateRecipe(
          id: widget.recipe!.id,
          name: nameController.text,
          category: selectedCategory,
          instructions: instructionsController.text,
          ingredientIds: selectedIngredients.toList(),
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
                            image: _existingImageUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(_existingImageUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : (_imageBytes != null
                                      ? DecorationImage(
                                          image: MemoryImage(_imageBytes!),
                                          fit: BoxFit.cover,
                                        )
                                      : null),
                          ),
                          child:
                              (_existingImageUrl == null && _imageBytes == null)
                              ? const Icon(
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

                      const SizedBox(height: 40),
                      _buildSectionHeader("Cooking Instructions"),
                      const SizedBox(height: 24),
                      _buildTextField(
                        controller: instructionsController,
                        label: "Step-by-Step Guide",
                        icon: Icons.description_outlined,
                        maxLines: 6,
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
                      _buildSectionHeader("Ingredients Selection"),
                      const SizedBox(height: 24),
                      ingredients.isEmpty
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: primaryBrand,
                              ),
                            )
                          : Wrap(
                              spacing: 8,
                              runSpacing: 12,
                              children: ingredients
                                  .map((ing) => _buildIngredientChip(ing))
                                  .toList(),
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
                                ? "Publish to Library"
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

  Widget _buildIngredientChip(Ingredient ingredient) {
    final isSelected = selectedIngredients.contains(ingredient.id);
    return FilterChip(
      label: Text(ingredient.name),
      selected: isSelected,
      onSelected: (val) {
        setState(() {
          if (val) {
            selectedIngredients.add(ingredient.id);
          } else {
            selectedIngredients.remove(ingredient.id);
          }
        });
      },
      selectedColor: primaryBrand.withOpacity(0.15),
      checkmarkColor: primaryBrand,
      labelStyle: TextStyle(
        color: isSelected ? primaryBrand : textMain,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
        fontSize: 13,
      ),
      backgroundColor: bgSoft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isSelected ? primaryBrand : Colors.transparent),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
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
          onChanged: onChanged,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: textMain,
            fontSize: 14,
          ),
          decoration: _inputDecoration(icon, "Enter $label"),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(IconData icon, String hint) {
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
    );
  }
}
