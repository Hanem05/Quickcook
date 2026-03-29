<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use App\Models\Collection;

class CollectionController extends Controller
{
    public function index()
    {
        $user = Auth::user();

        if (!$user) {
            return response()->json(['error' => 'Unauthorized'], 401);
        }

        $collections = $user->collections()->get();

        return response()->json($collections);
    }

    public function store(Request $request)
    {
        $user = Auth::user();

        // Safety check to prevent 500 error
        if (!$user) {
            return response()->json(['error' => 'Unauthorized'], 401);
        }

        return $user->collections()->create([
            'name' => $request->name
        ]);
    }

    public function addRecipe(Request $request)
    {
        $user = Auth::user();

        if (!$user) {
            return response()->json(['error' => 'Unauthorized'], 401);
        }

        $request->validate([
            'collection_id' => 'required|integer',
            'recipe_id' => 'required|integer',
        ]);

        $collection = $user->collections()
            ->find($request->collection_id);

        if (!$collection) {
            return response()->json(['error' => 'Collection not found'], 404);
        }

        $collection->recipes()->syncWithoutDetaching([
            $request->recipe_id
        ]);

        return response()->json([
            'message' => 'Recipe added successfully'
        ]);
    }

    public function show($id)
    {
        // Gets the collection AND all recipes linked to it
        return Auth::user()->collections()->with('recipes')->findOrFail($id);
    }
}
