<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

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

        $normalized = mb_strtolower($name);
        $duplicate = $user->collections()
            ->whereRaw('LOWER(TRIM(name)) = ?', [$normalized])
            ->exists();

        if ($duplicate) {
            return response()->json([
                'message' => 'You already have a folder with this name.',
            ], 422);
        }

        return response()->json(
            $user->collections()->create(['name' => $name]),
            201
        );
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

        $collection = $user->collections()
            ->find($request->collection_id);

        if (! $collection) {
            return response()->json(['error' => 'Collection not found'], 404);
        }

        $recipeId = (int) $request->recipe_id;
        $already = $collection->recipes()->where('recipes.id', $recipeId)->exists();

        $collection->recipes()->syncWithoutDetaching([$recipeId]);

        return response()->json([
            'message' => $already ? 'Recipe already exists in this collection' : 'Recipe added successfully',
            'duplicate' => $already,
        ]);
    }

    public function show($id)
    {
        return Auth::user()->collections()->with('recipes')->findOrFail($id);
    }
}
