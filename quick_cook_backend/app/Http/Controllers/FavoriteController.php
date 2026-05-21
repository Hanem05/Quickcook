<?php

namespace App\Http\Controllers;

use App\Models\Favorite;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class FavoriteController extends Controller
{
    public function store(Request $request)
    {
        $request->merge([
            'recipe_id' => is_numeric($request->input('recipe_id'))
                ? (int) $request->input('recipe_id')
                : $request->input('recipe_id'),
        ]);

        $request->validate([
            'recipe_id' => 'required|integer|exists:recipes,id',
        ]);

        $uid = $request->user()->id;
        $rid = (int) $request->recipe_id;

        $created = DB::transaction(function () use ($uid, $rid) {
            $existing = Favorite::query()
                ->where('user_id', $uid)
                ->where('recipe_id', $rid)
                ->lockForUpdate()
                ->first();

            if ($existing !== null) {
                return ['favorite' => $existing, 'duplicate' => true];
            }

            $favorite = Favorite::create([
                'user_id' => $uid,
                'recipe_id' => $rid,
            ]);

            return ['favorite' => $favorite, 'duplicate' => false];
        });

        if ($created['duplicate']) {
            return response()->json([
                'message' => 'Already in favorites',
                'favorite' => $created['favorite'],
                'duplicate' => true,
            ], 200);
        }

        return response()->json([
            'message' => 'Recipe added to favorites',
            'favorite' => $created['favorite'],
            'duplicate' => false,
        ], 201);
    }

    public function index(Request $request)
    {
        $favorites = $request->user()
            ->favorites()
            ->with(['recipe' => function ($query) {
                $query
                    ->select('recipes.*')
                    ->withCount('ratings')
                    ->withAvg('ratings as average_rating', 'rating');
            }])
            ->orderByDesc('id')
            ->get();

        $payload = $favorites->map(function (Favorite $favorite) {
            $recipe = $favorite->recipe;
            if ($recipe === null) {
                return null;
            }

            return [
                'id' => $favorite->id,
                'user_id' => $favorite->user_id,
                'recipe_id' => $favorite->recipe_id,
                'recipe' => [
                    'id' => $recipe->id,
                    'name' => $recipe->name,
                    'category' => $recipe->category,
                    'difficulty' => $recipe->difficulty ?? 'medium',
                    'cooking_time' => (int) ($recipe->cooking_time ?? 30),
                    'image' => $recipe->image_url,
                    'image_url' => $recipe->image_url,
                    'instructions' => '',
                    'ingredients' => [],
                    'average_rating' => $recipe->average_rating !== null
                        ? round((float) $recipe->average_rating, 1)
                        : 0.0,
                    'ratings_count' => (int) ($recipe->ratings_count ?? 0),
                ],
            ];
        })->filter()->values();

        return response()->json($payload);
    }

    public function destroy(Request $request, $id)
    {
        $deleted = DB::transaction(function () use ($request, $id) {
            $favorite = Favorite::where('user_id', $request->user()->id)
                ->where('recipe_id', $id)
                ->lockForUpdate()
                ->first();

            if (! $favorite) {
                return false;
            }

            $favorite->delete();
            return true;
        });

        if (! $deleted) {
            return response()->json([
                'message' => 'Favorite not found'
            ], 404);
        }

        return response()->json([
            'message' => 'Removed from favorites'
        ]);
    }
}
