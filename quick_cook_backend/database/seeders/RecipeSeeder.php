<?php

namespace Database\Seeders;

use App\Models\Ingredient;
use App\Models\Recipe;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class RecipeSeeder extends Seeder
{
    public function run(): void
    {
        $jsonPath = base_path('../docs/recipes_200_web.json');
        if (! is_file($jsonPath)) {
            $this->command?->warn("Recipe source file not found: {$jsonPath}");
            return;
        }

        $decoded = json_decode((string) file_get_contents($jsonPath), true);
        if (! is_array($decoded)) {
            $this->command?->warn('Invalid recipes JSON format. Expected top-level array.');
            return;
        }

        // Keep recipe library deterministic: exactly the imported web set.
        DB::table('recipe_ingredient')->delete();
        Recipe::query()->delete();
        $decoded = array_slice($decoded, 0, 200);

        $supportsCategory = Schema::hasColumn('recipes', 'category');
        $supportsDifficulty = Schema::hasColumn('recipes', 'difficulty');
        $supportsCookingTime = Schema::hasColumn('recipes', 'cooking_time');
        $supportsImage = Schema::hasColumn('recipes', 'image');

        $ingredientIdByNormalizedName = Ingredient::query()
            ->get(['id', 'name'])
            ->mapWithKeys(function (Ingredient $ingredient): array {
                return [$this->normalizeIngredientName($ingredient->name) => $ingredient->id];
            })
            ->all();

        foreach ($decoded as $entry) {
            if (! is_array($entry)) {
                continue;
            }

            $name = trim((string) ($entry['name'] ?? ''));
            $instructions = trim((string) ($entry['instructions'] ?? ''));
            if ($name === '' || $instructions === '') {
                continue;
            }

            $payload = [
                'name' => $name,
                'instructions' => $instructions,
            ];

            if ($supportsCategory) {
                $payload['category'] = $this->mapCategory($entry['category'] ?? null);
            }
            if ($supportsDifficulty) {
                $payload['difficulty'] = $this->estimateDifficulty($instructions);
            }
            if ($supportsCookingTime) {
                $payload['cooking_time'] = $this->estimateCookingMinutes($instructions);
            }
            if ($supportsImage) {
                $payload['image'] = trim((string) ($entry['image_url'] ?? '')) ?: null;
            }

            $recipe = Recipe::query()->create($payload);
            $ingredientIds = [];

            foreach (($entry['ingredients'] ?? []) as $ingredientEntry) {
                if (! is_array($ingredientEntry)) {
                    continue;
                }

                $ingredientName = trim((string) ($ingredientEntry['ingredient'] ?? ''));
                if ($ingredientName === '') {
                    continue;
                }

                $normalized = $this->normalizeIngredientName($ingredientName);
                if (! isset($ingredientIdByNormalizedName[$normalized])) {
                    $ingredient = Ingredient::query()->firstOrCreate(['name' => $ingredientName]);
                    $ingredientIdByNormalizedName[$normalized] = $ingredient->id;
                }

                $ingredientIds[] = $ingredientIdByNormalizedName[$normalized];
            }

            $ingredientIds = array_values(array_unique($ingredientIds));
            if (! empty($ingredientIds)) {
                $recipe->ingredients()->sync($ingredientIds);
            }
        }
    }

    private function normalizeIngredientName(string $value): string
    {
        return mb_strtolower(trim(preg_replace('/\s+/', ' ', $value) ?? $value));
    }

    private function mapCategory(mixed $value): string
    {
        $normalized = mb_strtolower(trim((string) $value));
        $breakfast = ['breakfast'];
        $lunch = ['beef', 'chicken', 'goat', 'lamb', 'pasta', 'pork', 'seafood', 'side', 'vegan', 'vegetarian'];
        $dinner = ['starter'];
        $snack = ['miscellaneous'];
        $dessert = ['dessert'];

        if (in_array($normalized, $breakfast, true)) {
            return 'Breakfast';
        }
        if (in_array($normalized, $dessert, true)) {
            return 'Dessert';
        }
        if (in_array($normalized, $snack, true)) {
            return 'Snack';
        }
        if (in_array($normalized, $dinner, true)) {
            return 'Dinner';
        }
        if (in_array($normalized, $lunch, true)) {
            return 'Lunch';
        }

        return 'Dinner';
    }

    private function estimateDifficulty(string $instructions): string
    {
        $steps = preg_split('/(\r\n|\r|\n)+/', trim($instructions)) ?: [];
        $stepCount = count(array_filter(array_map('trim', $steps), static fn (string $line): bool => $line !== ''));
        if ($stepCount >= 10) {
            return 'hard';
        }
        if ($stepCount >= 6) {
            return 'medium';
        }

        return 'easy';
    }

    private function estimateCookingMinutes(string $instructions): int
    {
        preg_match_all('/(\d+)\s*(mins?|minutes?|hours?|hrs?)/i', $instructions, $matches, PREG_SET_ORDER);
        if (empty($matches)) {
            return 30;
        }

        $minutes = 0;
        foreach ($matches as $match) {
            $value = (int) ($match[1] ?? 0);
            $unit = mb_strtolower((string) ($match[2] ?? ''));
            if (str_contains($unit, 'hour') || str_contains($unit, 'hr')) {
                $minutes += $value * 60;
            } else {
                $minutes += $value;
            }
        }

        return max(5, min($minutes, 360));
    }
}