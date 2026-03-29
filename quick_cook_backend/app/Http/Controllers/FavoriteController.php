<?php

namespace App\Http\Controllers;

use App\Models\Favorite;
use Illuminate\Http\Request;

class FavoriteController extends Controller
{
    public function store(Request $request)
    {
        $request->validate([
            'recipe_id' => 'required|exists:recipes,id',
        ]);

        $favorite = Favorite::firstOrCreate([
            'user_id' => $request->user()->id,
            'recipe_id' => $request->recipe_id,
        ]);

        return response()->json([
            'message' => 'Recipe added to favorites',
            'favorite' => $favorite
        ]);
    }

    public function index(Request $request)
    {
        // Tell Laravel to get the favorites, AND inside that recipe, 
        // load the ingredients and calculate the average rating!
        $favorites = $request->user()
            ->favorites()
            ->with(['recipe' => function ($query) {
                $query->with('ingredients')
                    ->withAvg('ratings as average_rating', 'rating');
            }])
            ->get();

        // Returning exactly as it was originally so Flutter doesn't break, 
        // but now the data is fully loaded with ingredients and ratings!
        return response()->json($favorites);
    }

    public function destroy(Request $request, $id)
    {
        $favorite = Favorite::where('user_id', $request->user()->id)
            ->where('recipe_id', $id)
            ->first();

        if (!$favorite) {
            return response()->json([
                'message' => 'Favorite not found'
            ], 404);
        }

        $favorite->delete();

        return response()->json([
            'message' => 'Removed from favorites'
        ]);
    }
}
