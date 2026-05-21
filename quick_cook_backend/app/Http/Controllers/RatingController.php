<?php

namespace App\Http\Controllers;

use App\Models\Ratings;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Cache;

class RatingController extends Controller
{
    public function rate(Request $request)
    {
        $request->validate([
            'recipe_id' => 'required',
            'rating' => 'required|integer|min:1|max:5'
        ]);

        $recipeId = (int) $request->recipe_id;

        Ratings::updateOrCreate(
            [
                'user_id' => Auth::id(),
                'recipe_id' => $recipeId,
            ],
            [
                'rating' => (int) $request->rating,
            ]
        );

        Cache::add('recipes_cache_version', 1);
        Cache::increment('recipes_cache_version');

        $count = Ratings::where('recipe_id', $recipeId)->count();
        $avg = Ratings::where('recipe_id', $recipeId)->avg('rating');

        return response()->json([
            'message' => 'Rating saved',
            'average_rating' => round((float) ($avg ?? 0), 1),
            'ratings_count' => $count,
        ]);
    }

    public function average($recipeId)
    {
        $avg = Ratings::where('recipe_id', $recipeId)->avg('rating');

        return response()->json([
            'average_rating' => round($avg, 1)
        ]);
    }
}