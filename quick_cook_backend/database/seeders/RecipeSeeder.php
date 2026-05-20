<?php

namespace Database\Seeders;

use App\Models\Ingredient;
use App\Models\Recipe;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use RecursiveDirectoryIterator;
use RecursiveIteratorIterator;

class RecipeSeeder extends Seeder
{
    public function run(): void
    {
        \Illuminate\Support\Facades\DB::table('recipe_ingredient')->delete();
        Recipe::query()->delete();

        $supportsCategory = Schema::hasColumn('recipes', 'category');
        $supportsDifficulty = Schema::hasColumn('recipes', 'difficulty');
        $supportsCookingTime = Schema::hasColumn('recipes', 'cooking_time');
        $supportsImage = Schema::hasColumn('recipes', 'image');

        $synced = $this->syncRepoImgsToPublicStorage();
        if ($synced > 0) {
            $this->command?->info("Copied {$synced} image(s) from imgs/ to storage/app/public/recipes/seed/.");
        }

        $imagePool = $this->discoverStoragePublicImagePaths();
        if ($imagePool === []) {
            $imagePool = ['images/recipe-placeholder.svg'];
            $this->command?->warn(
                'No recipe images found. Add files to quickcook-backend/imgs/ or storage/app/public/recipes/.'
            );
        }

        $targetTotal = max(1, min(10000, (int) env('RECIPE_SEED_TARGET', 2000)));
        $useJson = filter_var(env('RECIPE_SEED_USE_JSON', false), FILTER_VALIDATE_BOOL);

        $ingredientIdByNormalizedName = Ingredient::query()
            ->get(['id', 'name'])
            ->mapWithKeys(function (Ingredient $ingredient): array {
                return [$this->normalizeIngredientName($ingredient->name) => $ingredient->id];
            })
            ->all();

        if ($useJson) {
            $jsonPath = base_path('../docs/recipes_200_web.json');
            if (! is_file($jsonPath)) {
                $jsonPath = database_path('data/recipes_200_web.json');
            }
            if (is_file($jsonPath)) {
                $decoded = json_decode((string) file_get_contents($jsonPath), true);
                if (is_array($decoded)) {
                    $take = min(count($decoded), $targetTotal);
                    $this->importFromJson(
                        array_slice($decoded, 0, $take),
                        $ingredientIdByNormalizedName,
                        $imagePool,
                        $supportsCategory,
                        $supportsDifficulty,
                        $supportsCookingTime,
                        $supportsImage
                    );
                    $this->command?->info("Imported {$take} recipes from JSON.");
                }
            } else {
                $this->command?->warn('RECIPE_SEED_USE_JSON is true but no recipes JSON file found.');
            }
        }

        $current = Recipe::query()->count();
        $needRandom = $targetTotal - $current;
        if ($needRandom > 0) {
            $this->command?->info("Seeding {$needRandom} random recipes (".count($imagePool).' image(s) in rotation).');
            $this->seedRandomRecipes(
                $needRandom,
                $imagePool,
                $supportsCategory,
                $supportsDifficulty,
                $supportsCookingTime,
                $supportsImage
            );
        }

        if ($supportsImage && $imagePool !== [] && ! in_array('images/recipe-placeholder.svg', $imagePool, true)) {
            $assigned = $this->assignImagesFromPoolToAllRecipes($imagePool);
            $this->command?->info("Assigned rotating images to {$assigned} recipe(s).");
        }

        $final = Recipe::query()->count();
        $withIngredients = Recipe::query()->whereHas('ingredients')->count();
        $withImages = Recipe::query()->whereNotNull('image')->where('image', '!=', '')->count();
        $this->command?->info("Recipe seed complete: {$final} recipes, {$withIngredients} with ingredients, {$withImages} with images.");
    }

    /**
     * Copy photos from quickcook-backend/imgs into public storage for /storage/ URLs.
     */
    public function syncRepoImgsToPublicStorage(): int
    {
        $source = $this->resolveImgsSourceDir();
        if ($source === null) {
            return 0;
        }

        $dest = storage_path('app/public/recipes/seed');
        if (! is_dir($dest) && ! mkdir($dest, 0755, true) && ! is_dir($dest)) {
            return 0;
        }

        $files = glob($source.'/*') ?: [];
        $files = array_values(array_filter($files, static fn (string $path): bool => is_file($path)
            && preg_match('/\.(jpe?g|png|gif|webp|bmp|avif)$/i', $path) === 1));
        sort($files, SORT_NATURAL | SORT_FLAG_CASE);

        $copied = 0;
        foreach ($files as $index => $file) {
            $ext = strtolower(pathinfo($file, PATHINFO_EXTENSION));
            $target = $dest.'/seed-'.str_pad((string) ($index + 1), 2, '0', STR_PAD_LEFT).'.'.$ext;
            if (! file_exists($target) || filemtime($file) > @filemtime($target)) {
                if (@copy($file, $target)) {
                    $copied++;
                }
            } else {
                $copied++;
            }
        }

        return $copied;
    }

    /**
     * Assign rotating storage paths to every recipe (safe to re-run).
     *
     * @param  list<string>|null  $imagePool
     */
    public function assignImagesFromPoolToAllRecipes(?array $imagePool = null): int
    {
        if (! Schema::hasColumn('recipes', 'image')) {
            return 0;
        }

        $pool = $imagePool ?? $this->discoverStoragePublicImagePaths();
        $pool = array_values(array_filter(
            $pool,
            static fn (string $path): bool => $path !== '' && $path !== 'images/recipe-placeholder.svg'
        ));
        if ($pool === []) {
            return 0;
        }

        $count = 0;
        $imageCount = count($pool);
        Recipe::query()->orderBy('id')->chunkById(250, function ($recipes) use ($pool, $imageCount, &$count): void {
            foreach ($recipes as $recipe) {
                $rel = $pool[((int) $recipe->id) % $imageCount];
                if ($recipe->image !== $rel) {
                    $recipe->forceFill(['image' => $rel])->save();
                }
                $count++;
            }
        });

        return $count;
    }

    private function resolveImgsSourceDir(): ?string
    {
        $candidates = array_filter([
            env('RECIPE_IMGS_PATH'),
            base_path('../imgs'),
            base_path('imgs-seed'),
        ]);

        foreach ($candidates as $candidate) {
            $path = realpath((string) $candidate);
            if ($path !== false && is_dir($path)) {
                return $path;
            }
        }

        return null;
    }

    /**
     * Relative paths for DB `image` column: either `images/...` (public/) or `...` served via /storage/...
     *
     * @return list<string>
     */
    private function discoverStoragePublicImagePaths(): array
    {
        $root = storage_path('app/public');
        if (! is_dir($root)) {
            return [];
        }

        // Use raster formats that Flutter's Image/CachedNetworkImage can render reliably.
        $ext = '~\.(jpe?g|png|gif|webp|bmp|avif)$~i';
        $out = [];

        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($root, RecursiveDirectoryIterator::SKIP_DOTS)
        );
        foreach ($iterator as $file) {
            if (! $file->isFile()) {
                continue;
            }
            $path = $file->getPathname();
            if (preg_match($ext, $path) !== 1) {
                continue;
            }
            $rel = str_replace('\\', '/', substr($path, strlen($root) + 1));
            if ($rel === '' || str_contains($rel, '/.')) {
                continue;
            }
            // Seed assets from imgs/ may include avif; keep them even if GD cannot probe them.
            $isSeedAsset = str_starts_with($rel, 'recipes/seed/');
            if (! $isSeedAsset && @getimagesize($path) === false) {
                continue;
            }
            $out[] = $rel;
        }

        sort($out);

        return array_values(array_unique($out));
    }

    /**
     * @param  array<string, int>  $ingredientIdByNormalizedName
     * @param  list<array<string, mixed>>  $decoded
     */
    private function importFromJson(
        array $decoded,
        array &$ingredientIdByNormalizedName,
        array $imagePool,
        bool $supportsCategory,
        bool $supportsDifficulty,
        bool $supportsCookingTime,
        bool $supportsImage
    ): void {
        $imageCount = count($imagePool);
        $jsonIndex = 0;

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
                $fromJson = trim((string) ($entry['image_url'] ?? ''));
                if ($fromJson !== '') {
                    $payload['image'] = $fromJson;
                } elseif ($imageCount > 0) {
                    $payload['image'] = $imagePool[$jsonIndex % $imageCount];
                }
            }

            $recipe = Recipe::query()->create($payload);
            $jsonIndex++;
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
            if ($ingredientIds !== []) {
                $recipe->ingredients()->sync($ingredientIds);
            }
        }
    }

    /**
     * @param  list<string>  $imagePool
     */
    private function seedRandomRecipes(
        int $count,
        array $imagePool,
        bool $supportsCategory,
        bool $supportsDifficulty,
        bool $supportsCookingTime,
        bool $supportsImage
    ): void {
        $allIngredientIds = Ingredient::query()->orderBy('id')->pluck('id')->all();
        if ($allIngredientIds === []) {
            $this->command?->error('No ingredients in database. Run IngredientSeeder before RecipeSeeder.');

            return;
        }

        $minPick = min(6, count($allIngredientIds));
        $maxPick = min(12, count($allIngredientIds));
        if ($minPick < 3) {
            $minPick = count($allIngredientIds);
            $maxPick = count($allIngredientIds);
        }

        $categories = ['Breakfast', 'Lunch', 'Dinner', 'Dessert', 'Snack'];
        $difficulties = ['easy', 'medium', 'hard'];

        // Larger pools to avoid repetitive names like "Chili ...".
        $proteins = [
            'Chicken', 'Beef', 'Pork', 'Salmon', 'Tofu', 'Shrimp', 'Lamb', 'Turkey',
            'Tempeh', 'Cod', 'Tuna', 'Mushroom', 'Egg', 'Paneer', 'Duck', 'Seabass',
            'Sardine', 'Chickpea', 'Lentil', 'Cauliflower', 'Quinoa', 'Black Bean',
        ];
        $styles = [
            'Skillet', 'Bowl', 'Bake', 'Curry', 'Stew', 'Stir-Fry', 'Roast', 'Soup',
            'Salad', 'Risotto', 'Tacos', 'Ramen', 'Pasta', 'Pilaf', 'Wrap', 'Noodles',
            'Hash', 'Casserole', 'Sandwich', 'Fritters', 'Paella', 'Soba',
        ];
        $flavors = [
            'Smoky', 'Citrus', 'Herbed', 'Spiced', 'Garlic', 'Ginger', 'Coconut',
            'Honey', 'Tamarind', 'Miso', 'Lemon', 'Pepper', 'Sesame', 'Tomato',
            'Basil', 'Rosemary', 'Paprika', 'Cumin', 'Coriander', 'Soy-Glazed',
            'Maple', 'Buttery', 'Creamy', 'Roasted', 'Toasted', 'Zesty',
        ];
        $cuisineHints = [
            'Mediterranean', 'Asian', 'Filipino', 'Mexican', 'Italian', 'Indian',
            'Middle Eastern', 'Fusion', 'Home-Style', 'Street-Style', 'Rustic',
            'Coastal', 'Nordic', 'Bistro', 'Classic',
        ];

        $existing = Recipe::query()->pluck('name')->flip()->all();
        $imageCount = count($imagePool);

        for ($i = 0; $i < $count; $i++) {
            $n = $i + 1;
            $protein = $proteins[$i % count($proteins)];
            $style = $styles[($i * 3) % count($styles)];
            $flavor = $flavors[($i * 5) % count($flavors)];
            $cuisine = $cuisineHints[($i * 7) % count($cuisineHints)];
            $name = $this->uniqueRandomRecipeName(
                $existing,
                $protein,
                $style,
                $flavor,
                $cuisine,
                $n
            );

            $instructions = $this->buildRandomInstructions($i, $name, $protein, $style, $flavor);

            $payload = [
                'name' => $name,
                'instructions' => $instructions,
            ];
            if ($supportsCategory) {
                $payload['category'] = $categories[$i % count($categories)];
            }
            if ($supportsDifficulty) {
                $payload['difficulty'] = $difficulties[$i % count($difficulties)];
            }
            if ($supportsCookingTime) {
                $payload['cooking_time'] = 12 + (($i * 11) % 89);
            }
            if ($supportsImage) {
                $rel = $imagePool[$i % $imageCount];
                $payload['image'] = str_starts_with($rel, 'images/')
                    ? $rel
                    : $rel;
            }

            $recipe = Recipe::query()->create($payload);

            $ids = $allIngredientIds;
            shuffle($ids);
            $pickCount = $minPick + ($maxPick > $minPick ? ($i % ($maxPick - $minPick + 1)) : 0);
            $pick = array_slice($ids, 0, $pickCount);
            $recipe->ingredients()->sync($pick);
        }
    }

    /**
     * @param  array<string, true>  $existing
     */
    private function uniqueRandomRecipeName(
        array &$existing,
        string $protein,
        string $style,
        string $flavor,
        string $cuisine,
        int $n
    ): string {
        $pattern = $n % 4;
        if ($pattern === 0) {
            $base = "{$cuisine} {$flavor} {$protein} {$style}";
        } elseif ($pattern === 1) {
            $base = "{$flavor} {$style} with {$protein}";
        } elseif ($pattern === 2) {
            $base = "{$protein} {$style} ({$cuisine} style)";
        } else {
            $base = "{$cuisine} {$protein} {$style} with {$flavor} notes";
        }
        $name = $base;
        $suffix = 0;
        while (isset($existing[$name])) {
            $suffix++;
            $name = "{$base} {$suffix}";
        }
        $existing[$name] = true;

        return $name;
    }

    private function buildRandomInstructions(
        int $i,
        string $title,
        string $protein,
        string $style,
        string $flavor
    ): string
    {
        $prep = 5 + ($i % 20);
        $cook = 10 + (($i * 3) % 55);
        $rest = ($i % 8) > 4 ? 0 : 5 + ($i % 10);
        $servings = 2 + ($i % 5);
        $heatLevels = ['low', 'medium', 'medium-high'];
        $heat = $heatLevels[$i % count($heatLevels)];
        $panNames = ['skillet', 'saucepan', 'Dutch oven', 'wok', 'stock pot'];
        $pan = $panNames[($i * 2) % count($panNames)];
        $finishes = ['fresh herbs', 'toasted sesame', 'lemon zest', 'chopped scallions', 'black pepper'];
        $finish = $finishes[($i * 4) % count($finishes)];

        $lines = [
            "{$title} is a {$flavor} {$style} built around {$protein}, ideal for about {$servings} servings.",
            "1. Mise en place ({$prep} min): prep vegetables and season {$protein} evenly with salt and pepper.",
            "2. Heat a {$pan} over {$heat} heat with oil for 1-2 minutes.",
            "3. Cook {$protein} until lightly browned, about 3-6 minutes, then transfer to a plate.",
            '4. In the same pan, saute aromatics until fragrant (1-2 minutes).',
            "5. Add the remaining ingredients and bring to a gentle simmer over {$heat} heat.",
            "6. Return {$protein} to the pan and cook until tender, {$cook} minutes, stirring every few minutes.",
            "7. Taste and balance seasoning; finish with {$finish}.",
        ];

        if ($rest > 0) {
            $lines[] = "8. Rest {$rest} minutes off heat before serving.";
        } else {
            $lines[] = '8. Serve immediately while hot.';
        }

        $lines[] = "Prep time: {$prep} min. Estimated cook time: {$cook} min.";

        return implode("\n", $lines);
    }

    private function normalizeIngredientName(string $value): string
    {
        return Str::lower(trim(preg_replace('/\s+/', ' ', $value) ?? $value));
    }

    private function mapCategory(mixed $value): string
    {
        $normalized = Str::lower(trim((string) $value));
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
            $unit = Str::lower((string) ($match[2] ?? ''));
            if (str_contains($unit, 'hour') || str_contains($unit, 'hr')) {
                $minutes += $value * 60;
            } else {
                $minutes += $value;
            }
        }

        return max(5, min($minutes, 360));
    }
}
