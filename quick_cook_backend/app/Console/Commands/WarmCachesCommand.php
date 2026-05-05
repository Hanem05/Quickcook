<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use App\Models\Recipe;
use App\Models\Ingredient;

/**
 * Pre-warms hot read paths so the first real user request does not pay the
 * cold-start cost on Docker bind mounts and PHP-FPM worker boot.
 *
 * Usage: `php artisan app:warm`
 */
class WarmCachesCommand extends Command
{
    protected $signature = 'app:warm';

    protected $description = 'Warm critical caches and hot read paths.';

    public function handle(): int
    {
        $this->info('Warming ingredients cache...');
        Cache::remember('ingredients:list:v1', now()->addMinutes(15), function () {
            return Ingredient::query()
                ->select(['id', 'name'])
                ->orderBy('name')
                ->get();
        });

        $this->info('Warming recipes list cache...');
        $version = (int) Cache::get('recipes_cache_version', 1);
        $key = 'recipes:v'.$version.':'.md5(json_encode([
            'category' => null,
            'difficulty' => null,
            'ingredient_ids' => [],
            'max_cooking_time' => 0,
            'per_page' => 80,
            'compact' => 1,
        ]));
        Cache::remember($key, now()->addMinutes(5), function () {
            $page = Recipe::query()
                ->orderByDesc('id')
                ->select(['id','name','category','difficulty','cooking_time','image'])
                ->withAvg('ratings as average_rating', 'rating')
                ->paginate(80);
            $page->getCollection()->transform(function (Recipe $recipe) {
                return [
                    'id' => $recipe->id,
                    'name' => $recipe->name,
                    'category' => $recipe->category,
                    'difficulty' => $recipe->difficulty ?? 'medium',
                    'cooking_time' => (int) ($recipe->cooking_time ?? 30),
                    'image_url' => $recipe->image_url,
                    'image' => $recipe->image_url,
                    'ingredients' => [],
                    'average_rating' => $recipe->average_rating !== null
                        ? round((float) $recipe->average_rating, 1)
                        : 0,
                ];
            });
            return $page;
        });

        $this->info('Warming admin/popular caches...');
        $trendingVersion = (int) Cache::get('trending_cache_version', 1);
        Cache::remember('popular_recipes:v'.$trendingVersion, 300, function () {
            return DB::table('user_activities')
                ->select('recipe_id', DB::raw('count(*) as views'))
                ->where('action', 'view_recipe')
                ->groupBy('recipe_id')
                ->orderByDesc('views')
                ->limit(5)
                ->get();
        });

        $this->info('Done.');
        return self::SUCCESS;
    }
}
