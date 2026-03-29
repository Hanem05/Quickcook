<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\Ingredient;

class IngredientSeeder extends Seeder
{
    public function run(): void
    {
        $ingredients = [
            'Egg',
            'Tomato',
            'Onion',
            'Garlic',
            'Chicken',
            'Salt',
            'Pepper',
            'Rice',
            'Carrot',
            'Potato',
            'Soy Sauce',
            'Cooking Oil',
            'Milk',
            'Flour',
            'Sugar'
        ];

        foreach ($ingredients as $ingredient) {
            Ingredient::firstOrcreate([
                'name' => $ingredient
            ]);
        }
    }
}