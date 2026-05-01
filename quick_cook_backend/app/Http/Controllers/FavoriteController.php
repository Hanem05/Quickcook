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
