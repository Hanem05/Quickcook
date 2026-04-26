<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\Ingredient;
use Illuminate\Support\Facades\Cache;

class IngredientController extends Controller
{
    public function index()
    {
        $ingredients = Cache::remember('ingredients:list:v1', now()->addMinutes(15), function () {
            return Ingredient::query()
                ->select(['id', 'name'])
                ->orderBy('name')
                ->get();
        });

        return response()->json($ingredients);
    }

    public function store(Request $request)
    {
        $validated = $request->validate(['name' => 'required|string|unique:ingredients']);
        $ingredient = Ingredient::create($validated);
        Cache::forget('ingredients:list:v1');
        return response()->json($ingredient, 201);
    }
}
