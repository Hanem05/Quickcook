<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\Ingredient;

class IngredientController extends Controller
{
    public function index()
    {
        $ingredients = Ingredient::all();

        return response()->json($ingredients);
    }

    public function store(Request $request)
    {
        $validated = $request->validate(['name' => 'required|string|unique:ingredients']);
        $ingredient = Ingredient::create($validated);
        return response()->json($ingredient, 201);
    }
}
