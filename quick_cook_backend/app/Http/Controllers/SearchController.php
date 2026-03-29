<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\Recipe;
use App\Models\Ingredient;

class SearchController extends Controller
{
    public function search(Request $request)
    {
        $query = $request->input('query');

        if (!$query) {
            return response()->json([
                'recipes' => [],
                'ingredients' => [],
                'categories' => []
            ]);
        }

        $recipes = Recipe::where('name', 'LIKE', "%{$query}%")
            ->orWhere('instructions', 'LIKE', "%{$query}%")
            ->limit(10)
            ->get();

        $ingredients = Ingredient::where('name', 'LIKE', "%{$query}%")
            ->limit(10)
            ->get();

        $categories = Recipe::where('category', 'LIKE', "%{$query}%")
            ->select('category')
            ->distinct()
            ->pluck('category');

        return response()->json([
            'recipes' => $recipes,
            'ingredients' => $ingredients,
            'categories' => $categories
        ]);
    }
}
