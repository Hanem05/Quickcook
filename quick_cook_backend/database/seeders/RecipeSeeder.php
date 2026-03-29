<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use App\Models\Recipe;
use App\Models\Ingredient;

class RecipeSeeder extends Seeder
{
    public function run(): void
    {
        // Example Recipe 1
        $omelette = Recipe::create([
            'name' => 'Simple Omelette',
            'instructions' => 'Beat eggs. Heat oil in pan. Add eggs and cook for 3-5 minutes.'

            
        ]);

        $omelette->ingredients()->attach(
            Ingredient::whereIn('name', [
                'Egg',
                'Salt',
                'Pepper',
                'Cooking Oil'
            ])->pluck('id')
        );

        // Example Recipe 2
        $friedRice = Recipe::create([
            'name' => 'Chicken Fried Rice',
            'instructions' => 'Cook rice. Sauté garlic, onion, and chicken. Add rice and soy sauce. Mix well.'
        ]);

        $friedRice->ingredients()->attach(
            Ingredient::whereIn('name', [
                'Rice',
                'Chicken',
                'Garlic',
                'Onion',
                'Soy Sauce',
                'Cooking Oil'
            ])->pluck('id')
        );

        // Example Recipe 3
        $pancake = Recipe::create([
            'name' => 'Basic Pancake',
            'instructions' => 'Mix flour, milk, sugar, and egg. Cook on pan until golden brown.'
        ]);

        $pancake->ingredients()->attach(
            Ingredient::whereIn('name', [
                'Flour',
                'Milk',
                'Sugar',
                'Egg'
            ])->pluck('id')
        );
    }
}