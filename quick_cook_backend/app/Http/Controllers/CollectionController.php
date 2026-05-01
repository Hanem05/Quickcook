<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;

class CollectionController extends Controller
{
    public function index()
    {
        $user = Auth::user();

        if (! $user) {
            return response()->json(['error' => 'Unauthorized'], 401);
        }

        $collections = $user->collections()->get();

        return response()->json($collections);
    }

    public function store(Request $request)
    {
        $user = Auth::user();

        if (! $user) {
            return response()->json(['error' => 'Unauthorized'], 401);
        }

        $validated = $request->validate([
            'name' => ['required', 'string', 'max:255'],
        ]);

        $name = trim($validated['name']);
        if ($name === '') {
            return response()->json(['message' => 'Folder name cannot be empty.'], 422);
        }

        $created = DB::transaction(function () use ($user, $name) {
            $normalized = mb_strtolower($name);
            $duplicate = $user->collections()
                ->whereRaw('LOWER(TRIM(name)) = ?', [$normalized])
                ->lockForUpdate()
                ->exists();

            if ($duplicate) {
                return null;
            }

            return $user->collections()->create(['name' => $name]);
        });

        if ($created === null) {
            return response()->json([
                'message' => 'You already have a folder with this name.',
            ], 422);
        }

        return response()->json($created, 201);
    }

    public function addRecipe(Request $request)
    {
        $user = Auth::user();

        if (! $user) {
            return response()->json(['error' => 'Unauthorized'], 401);
        }

        $request->validate([
            'collection_id' => 'required|integer',
            'recipe_id' => 'required|integer|exists:recipes,id',
        ]);

        $result = DB::transaction(function () use ($user, $request) {
            $collection = $user->collections()
                ->lockForUpdate()
                ->find($request->collection_id);

            if (! $collection) {
                return ['error' => 'Collection not found', 'status' => 404];
            }

            $recipeId = (int) $request->recipe_id;
            $already = $collection->recipes()->where('recipes.id', $recipeId)->exists();
            $collection->recipes()->syncWithoutDetaching([$recipeId]);

            return ['already' => $already, 'status' => 200];
        });

        if (($result['status'] ?? 200) === 404) {
            return response()->json(['error' => $result['error']], 404);
        }

        return response()->json([
            'message' => $result['already'] ? 'Recipe already exists in this collection' : 'Recipe added successfully',
            'duplicate' => $result['already'],
        ]);
    }

    public function show($id)
    {
        return Auth::user()->collections()->with('recipes')->findOrFail($id);
    }
}
