<?php

namespace App\Http\Controllers;

use App\Models\Recipe;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use App\Models\UserActivity;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Storage;

class RecipeController extends Controller
{
    /**
     * GET ALL RECIPES (Admin Panel)
     */
    public function index()
    {
        $recipes = Cache::remember('recipes_all', 300, function () {
            return Recipe::with('ingredients')
                ->withAvg('ratings as average_rating', 'rating')
                ->get();
        });

        return response()->json($recipes);
    }

    /**
     * MATCH RECIPES BASED ON INGREDIENTS + CATEGORY
     */
    public function match(Request $request)
    {
        $request->validate([
            'ingredient_ids' => 'required|array'
        ]);

        $ingredientIds = $request->ingredient_ids;
        $category = $request->category;

        try {
            foreach ($ingredientIds as $id) {
                UserActivity::create([
                    'user_id' => Auth::id(),
                    'action' => 'select_ingredient',
                    'ingredient_id' => $id
                ]);
            }

            UserActivity::create([
                'user_id' => Auth::id(),
                'action' => 'search_recipe'
            ]);
        } catch (\Exception $e) {
            \Log::error("Activity Logging Failed: " . $e->getMessage());
        }

        $query = Recipe::with(['ingredients:id,name', 'ratings:id,recipe_id,rating'])
            ->whereHas('ingredients', function ($q) use ($ingredientIds) {
                $q->whereIn('ingredients.id', $ingredientIds);
            });

        if ($category) {
            $query->where('category', $category);
        }

        $recipes = $query->select('id', 'name', 'category', 'instructions', 'image')->paginate(5);

        $recipes->getCollection()->transform(function ($recipe) {
            return [
                'id' => $recipe->id,
                'name' => $recipe->name,
                'category' => $recipe->category,
                'instructions' => $recipe->instructions,
                'image_url' => $recipe->image ? url('storage/' . $recipe->image) : null,
                'ingredients' => $recipe->ingredients->pluck('name'),
                'average_rating' => $recipe->ratings->avg('rating') ? round($recipe->ratings->avg('rating'), 1) : 0
            ];
        });

        return response()->json($recipes);
    }

    /**
     * GET SINGLE RECIPE (DETAIL SCREEN)
     */
    public function show($id)
    {
        $recipe = Recipe::with(['ingredients', 'ratings'])->findOrFail($id);

        return response()->json([
            'id' => $recipe->id,
            'name' => $recipe->name,
            'category' => $recipe->category,
            'instructions' => $recipe->instructions,
            'image_url' => $recipe->image ? url('storage/' . $recipe->image) : null,
            'ingredients' => $recipe->ingredients->pluck('name'),
            'average_rating' => round($recipe->ratings()->avg('rating'), 1)
        ]);
    }

    /**
     * CREATE RECIPE
     */
    public function store(Request $request)
    {
        try {
            $validated = $request->validate([
                'name' => 'required|string|max:255',
                'category' => 'nullable|string|max:255',
                'instructions' => 'required|string',
                'ingredient_ids' => 'nullable|array',
                'image' => 'nullable|image|mimes:jpeg,png,jpg,webp|max:4096'
            ]);

            $imagePath = 'default_recipe.png';

            if ($request->hasFile('image')) {
                $imagePath = $request->file('image')->store('recipes', 'public');
            }

            $recipe = Recipe::create([
                'name' => $validated['name'],
                'category' => $validated['category'] ?? 'Uncategorized',
                'instructions' => $validated['instructions'],
                'image' => $imagePath
            ]);

            if (!empty($validated['ingredient_ids'])) {
                $recipe->ingredients()->attach($validated['ingredient_ids']);
            }

            Cache::forget('recipes_all'); // ✅ FIXED

            return response()->json([
                'message' => 'Recipe created successfully',
                'recipe' => $recipe->load('ingredients')
            ], 201);
        } catch (\Illuminate\Validation\ValidationException $e) {
            return response()->json([
                'message' => 'Validation failed',
                'errors' => $e->errors()
            ], 422);
        } catch (\Exception $e) {
            return response()->json([
                'message' => 'Failed to create recipe',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * UPDATE RECIPE
     */
    public function update(Request $request, $id)
    {
        try {
            $recipe = Recipe::findOrFail($id);

            $validated = $request->validate([
                'name' => 'required|string|max:255',
                'category' => 'nullable|string|max:255',
                'instructions' => 'required|string',
                'ingredient_ids' => 'nullable|array',
                'image' => 'nullable|image|mimes:jpeg,png,jpg,webp|max:4096'
            ]);

            $updateData = [
                'name' => $validated['name'],
                'category' => $validated['category'] ?? null,
                'instructions' => $validated['instructions']
            ];

            if ($request->hasFile('image')) {
                if ($recipe->image && $recipe->image !== 'default_recipe.png') {
                    Storage::disk('public')->delete($recipe->image);
                }

                $updateData['image'] = $request->file('image')->store('recipes', 'public');
            }

            $recipe->update($updateData);

            if (isset($validated['ingredient_ids'])) {
                $recipe->ingredients()->sync($validated['ingredient_ids']);
            }

            Cache::forget('recipes_all'); // ✅ FIXED

            return response()->json([
                'message' => 'Recipe updated successfully',
                'recipe' => $recipe
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'message' => 'Failed to update recipe',
                'error' => $e->getMessage()
            ], 500);
        }
    }

    /**
     * DELETE RECIPE
     */
    public function destroy($id)
    {
        $recipe = Recipe::findOrFail($id);

        $recipe->ingredients()->detach();
        $recipe->ratings()->delete();

        if ($recipe->image && $recipe->image !== 'default_recipe.png') {
            Storage::disk('public')->delete($recipe->image);
        }

        $recipe->delete();

        Cache::forget('recipes_all'); // ✅ FIXED

        return response()->json([
            'success' => true,
            'message' => 'Recipe deleted successfully'
        ]);
    }

    public function getRecentBatch(Request $request)
    {
        $ids = array_map('intval', $request->input('ids', []));

        if (empty($ids)) {
            return response()->json([]);
        }

        $fetched = Recipe::whereIn('id', $ids)->get()->keyBy('id');

        $ordered = collect($ids)
            ->map(fn (int $id) => $fetched->get($id))
            ->filter()
            ->values();

        $ordered->each->append('image_url');

        return response()->json($ordered);
    }
}
