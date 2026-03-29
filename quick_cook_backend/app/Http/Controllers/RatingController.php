<?php

namespace App\Http\Controllers;

use App\Models\Ratings;
use Illuminate\Http\Request;

use Illuminate\Support\Facades\Auth;

class RatingController extends Controller
{
    public function rate(Request $request)
    {
        $request->validate([
            'recipe_id' => 'required',
            'rating' => 'required|integer|min:1|max:5'
        ]);

        Ratings::updateOrCreate(
            [
                'user_id' => Auth::id(),
                'recipe_id' => $request->recipe_id
            ],
            [
                'rating' => $request->rating
            ]
        );

        return response()->json([
            'message' => 'Rating saved'
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