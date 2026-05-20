<?php

namespace App\Http\Controllers;

use App\Jobs\ProcessRecipeImageJob;
use App\Jobs\WarmRecommendationCacheJob;
use App\Models\Ingredient;
use App\Models\Recipe;
use App\Models\UserActivity;
use App\Services\IngredientResolverService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class RecipeController extends Controller
{
    public function __construct(
        protected IngredientResolverService $ingredientResolver
    ) {
    }

    protected function resolveIngredientIds(array $validated): array
    {
        return $this->ingredientResolver->resolve($validated);
    }

    protected function recipesCacheVersion(): int
    {
        return (int) Cache::get('recipes_cache_version', 1);
    }

    protected function recommendationCacheVersion(): int
    {
        return (int) Cache::get('recommend_cache_version', 1);
    }

    protected function bumpRecipeRelatedCache(): void
    {
        Cache::add('recipes_cache_version', 1);
        Cache::add('recommend_cache_version', 1);
        Cache::add('trending_cache_version', 1);
        Cache::increment('recipes_cache_version');
        Cache::increment('recommend_cache_version');
        Cache::increment('trending_cache_version');
        Cache::forget('recipes_all');
        Cache::forget('admin_stats');
    }

    protected function askGeminiAssistant(string $message, array $history, array $ingredientIds): ?array
    {
        $apiKey = (string) env('GEMINI_API_KEY', '');
        if ($apiKey === '') {
            return null;
        }

        $ingredientNames = [];
        if ($ingredientIds !== []) {
            $ingredientNames = Ingredient::query()
                ->whereIn('id', $ingredientIds)
                ->pluck('name')
                ->map(static fn ($name): string => (string) $name)
                ->values()
                ->all();
        }

        $systemPrompt = implode("\n", [
            'You are QuickCook AI, a helpful cooking and recipe assistant.',
            'Use concise, friendly answers with practical steps.',
            'When useful, format with markdown bullets.',
            'Stay focused on recipes, ingredients, substitutions, cooking, and app-related guidance.',
            'If asked for unsafe or unrelated content, politely refuse and redirect to cooking help.',
        ]);

        $contents = [
            [
                'role' => 'user',
                'parts' => [['text' => $systemPrompt]],
            ],
        ];

        foreach (array_slice($history, -10) as $item) {
            $role = (($item['role'] ?? '') === 'assistant') ? 'model' : 'user';
            $text = trim((string) ($item['content'] ?? ''));
            if ($text === '') {
                continue;
            }
            $contents[] = [
                'role' => $role,
                'parts' => [['text' => $text]],
            ];
        }

        $contextText = $ingredientNames === []
            ? 'Selected ingredient context: none'
            : 'Selected ingredient context: '.implode(', ', $ingredientNames);

        $contents[] = [
            'role' => 'user',
            'parts' => [[
                'text' => $contextText."\n\nUser message: ".$message,
            ]],
        ];

        $url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key='.$apiKey;

        $res = Http::timeout(20)->post($url, [
            'contents' => $contents,
            'generationConfig' => [
                'temperature' => 0.7,
                'maxOutputTokens' => 700,
            ],
        ]);

        if (! $res->successful()) {
            return null;
        }

        $data = $res->json();
        $text = trim((string) data_get($data, 'candidates.0.content.parts.0.text', ''));
        if ($text === '') {
            return null;
        }

        return [
            'reply' => $text,
            'suggestions' => [],
        ];
    }

    /**
     * GET ALL RECIPES (Admin Panel)
     */
    public function index()
    {
        $compact = (int) request()->query('compact', 0) === 1;
        $page = max(1, (int) request()->query('page', 1));
        $category = request()->query('category');
        $difficulty = request()->query('difficulty');
        $q = trim((string) request()->query('q', ''));
        $ingredientIds = request()->query('ingredient_ids', []);
        $maxCookingTime = (int) request()->query('max_cooking_time', 0);
        $perPage = min(500, max(5, (int) request()->query('per_page', 25)));

        $key = 'recipes:v'.$this->recipesCacheVersion().':'.md5(json_encode([
            'category' => $category,
            'difficulty' => $difficulty,
            'q' => $q,
            'ingredient_ids' => $ingredientIds,
            'max_cooking_time' => $maxCookingTime,
            'page' => $page,
            'per_page' => $perPage,
            'compact' => $compact ? 1 : 0,
        ]));

        $recipes = Cache::remember($key, now()->addMinutes(5), function () use ($category, $difficulty, $q, $ingredientIds, $maxCookingTime, $perPage, $compact) {
            $query = Recipe::query()->orderByDesc('id');

            if (! $compact) {
                $query->with('ingredients');
            } else {
                $query->select([
                    'id',
                    'name',
                    'category',
                    'difficulty',
                    'cooking_time',
                    'image',
                ]);
            }
            $query->withAvg('ratings as average_rating', 'rating');

            if (is_string($category) && $category !== '') {
                $query->where('category', $category);
            }
            if (is_string($difficulty) && in_array($difficulty, ['easy', 'medium', 'hard'], true)) {
                $query->where('difficulty', $difficulty);
            }
            if ($q !== '') {
                $query->where(function ($builder) use ($q) {
                    $builder
                        ->where('name', 'like', '%'.$q.'%')
                        ->orWhere('category', 'like', '%'.$q.'%');
                });
            }
            if ($maxCookingTime > 0) {
                $query->where('cooking_time', '<=', $maxCookingTime);
            }
            if (is_array($ingredientIds) && $ingredientIds !== []) {
                $ids = array_values(array_unique(array_map(static fn ($v): int => (int) $v, $ingredientIds)));
                $query->whereHas('ingredients', function ($q) use ($ids) {
                    $q->whereIn('ingredients.id', $ids);
                }, '>=', count($ids));
            }

            return $query->paginate($perPage);
        });

        if ($compact && $recipes instanceof \Illuminate\Pagination\LengthAwarePaginator) {
            $recipes->setCollection(
                $recipes->getCollection()->map(function (Recipe $recipe) {
                    return [
                        'id' => $recipe->id,
                        'name' => $recipe->name,
                        'category' => $recipe->category,
                        'difficulty' => $recipe->difficulty ?? 'medium',
                        'cooking_time' => (int) ($recipe->cooking_time ?? 30),
                        'image_url' => $recipe->image_url,
                        'image' => $recipe->image_url,
                        'ingredients' => [],
                        'instructions' => '',
                        'average_rating' => $recipe->average_rating !== null
                            ? round((float) $recipe->average_rating, 1)
                            : 0.0,
                    ];
                })
            );
        }

        return response()->json($recipes);
    }

    /**
     * MATCH RECIPES — scored coverage, fewer missing ingredients first (Sprint 8 Task 80).
     */
    public function match(Request $request)
    {
        $request->validate([
            'ingredient_ids' => 'required|array|min:1',
            'ingredient_ids.*' => 'integer|min:1',
            'category' => 'nullable|string|max:255',
            'difficulty' => 'nullable|string|in:easy,medium,hard',
            'max_cooking_time' => 'nullable|integer|min:1|max:1440',
            'page' => 'nullable|integer|min:1',
            'per_page' => 'nullable|integer|min:5|max:50',
        ]);

        $rawIds = array_values(array_unique(array_map(static fn ($v): int => (int) $v, $request->ingredient_ids)));
        $pantryIds = Ingredient::query()->whereIn('id', $rawIds)->pluck('id')->map(static fn ($id): int => (int) $id)->values()->all();

        if ($pantryIds === []) {
            return response()->json([
                'data' => [],
                'current_page' => 1,
                'last_page' => 1,
                'per_page' => 15,
                'total' => 0,
                'meta' => [
                    'message' => 'No valid ingredient IDs.',
                    'suggestions' => $this->matchSuggestionsFallback(),
                ],
            ]);
        }

        try {
            foreach ($pantryIds as $id) {
                UserActivity::create([
                    'user_id' => Auth::id(),
                    'action' => 'select_ingredient',
                    'ingredient_id' => $id,
                ]);
            }
            UserActivity::create([
                'user_id' => Auth::id(),
                'action' => 'search_recipe',
            ]);
        } catch (\Exception $e) {
            \Log::error('Activity Logging Failed: '.$e->getMessage());
        }

        $pantryNames = Ingredient::query()->whereIn('id', $pantryIds)->pluck('name')->map(static fn ($n): string => mb_strtolower(trim((string) $n)))->values()->all();

        $placeholders = implode(',', array_fill(0, count($pantryIds), '?'));
        $sql = "
            SELECT h.recipe_id, h.pantry_hits, t.ingredient_total,
                   (t.ingredient_total - h.pantry_hits) AS missing_exact
            FROM (
                SELECT recipe_id, COUNT(*) AS pantry_hits
                FROM recipe_ingredient
                WHERE ingredient_id IN ($placeholders)
                GROUP BY recipe_id
            ) h
            INNER JOIN (
                SELECT recipe_id, COUNT(*) AS ingredient_total
                FROM recipe_ingredient
                GROUP BY recipe_id
            ) t ON t.recipe_id = h.recipe_id
            ORDER BY missing_exact ASC, h.pantry_hits DESC, h.recipe_id ASC
        ";

        /** @var list<object{recipe_id:int|string,pantry_hits:int|string,ingredient_total:int|string,missing_exact:int|string}> $rankedRows */
        $rankedRows = DB::select($sql, $pantryIds);

        $perPage = min(50, max(5, (int) $request->get('per_page', 15)));
        $page = max(1, (int) $request->get('page', 1));

        if (
            $request->filled('category') ||
            $request->filled('difficulty') ||
            $request->filled('max_cooking_time')
        ) {
            $candidateIds = array_values(array_unique(array_map(
                static fn ($row): int => (int) $row->recipe_id,
                $rankedRows
            )));

            if ($candidateIds !== []) {
                $allowedQuery = Recipe::query()->whereIn('id', $candidateIds);

                if ($request->filled('category')) {
                    $allowedQuery->where('category', (string) $request->string('category'));
                }
                if ($request->filled('difficulty')) {
                    $allowedQuery->where('difficulty', (string) $request->string('difficulty'));
                }
                if ($request->filled('max_cooking_time')) {
                    $allowedQuery->where('cooking_time', '<=', (int) $request->input('max_cooking_time'));
                }

                $allowedIds = $allowedQuery
                    ->pluck('id')
                    ->map(static fn ($id): int => (int) $id)
                    ->all();
                $allowedFlip = array_fill_keys($allowedIds, true);
                $rankedRows = array_values(array_filter($rankedRows, static function ($row) use ($allowedFlip) {
                    return isset($allowedFlip[(int) $row->recipe_id]);
                }));
            } else {
                $rankedRows = [];
            }
        }

        $candidateRecipeIds = array_values(array_unique(array_map(static fn ($row): int => (int) $row->recipe_id, $rankedRows)));
        $matchedIngredientIds = $candidateRecipeIds === []
            ? []
            : DB::table('recipe_ingredient')
                ->whereIn('recipe_id', $candidateRecipeIds)
                ->whereIn('ingredient_id', $pantryIds)
                ->distinct()
                ->pluck('ingredient_id')
                ->map(static fn ($id): int => (int) $id)
                ->values()
                ->all();

        $unmatchedIngredientIds = array_values(array_diff($pantryIds, $matchedIngredientIds));
        $unmatchedIngredientNames = $unmatchedIngredientIds === []
            ? []
            : Ingredient::query()
                ->whereIn('id', $unmatchedIngredientIds)
                ->orderBy('name')
                ->pluck('name')
                ->map(static fn ($n): string => (string) $n)
                ->values()
                ->all();

        $totalRanked = count($rankedRows);
        $offset = ($page - 1) * $perPage;
        $pageRows = array_slice($rankedRows, $offset, $perPage);

        $rankMeta = [];
        foreach ($pageRows as $row) {
            $rankMeta[(int) $row->recipe_id] = [
                'pantry_hits' => (int) $row->pantry_hits,
                'ingredient_total' => (int) $row->ingredient_total,
                'missing_exact' => (int) $row->missing_exact,
            ];
        }

        $pageIds = array_keys($rankMeta);

        $recipes = $pageIds === []
            ? collect()
            : Recipe::query()
                ->with(['ingredients:id,name', 'ratings:id,recipe_id,rating'])
                ->whereIn('id', $pageIds)
                ->get()
                ->sortBy(static fn ($r) => array_search($r->id, $pageIds, true))
                ->values();

        $collection = $recipes->map(function (Recipe $recipe) use ($pantryIds, $pantryNames, $rankMeta) {
            $meta = $rankMeta[$recipe->id] ?? ['pantry_hits' => 0, 'ingredient_total' => 1, 'missing_exact' => 1];
            $total = max(1, (int) ($meta['ingredient_total'] ?? 1));
            $hits = (int) ($meta['pantry_hits'] ?? 0);
            $missingExact = (int) ($meta['missing_exact'] ?? ($total - $hits));

            $partialBonus = 0;
            foreach ($recipe->ingredients as $ing) {
                if (in_array((int) $ing->id, $pantryIds, true)) {
                    continue;
                }
                $lower = mb_strtolower(trim((string) $ing->name));
                foreach ($pantryNames as $pn) {
                    if ($pn !== '' && (str_contains($lower, $pn) || str_contains($pn, $lower))) {
                        $partialBonus += 0.35;
                        break;
                    }
                }
            }

            $effectiveHits = min($total, $hits + $partialBonus);
            $coveragePct = round(($effectiveHits / $total) * 100, 1);
            $missingApprox = max(0, (int) ceil($total - $effectiveHits));

            $avg = $recipe->ratings->avg('rating');

            return [
                'id' => $recipe->id,
                'name' => $recipe->name,
                'category' => $recipe->category,
                'difficulty' => $recipe->difficulty ?? 'medium',
                'cooking_time' => (int) ($recipe->cooking_time ?? 30),
                'instructions' => $recipe->instructions,
                'image_url' => $recipe->image_url,
                'ingredients' => $recipe->ingredients->pluck('name'),
                'average_rating' => $avg ? round((float) $avg, 1) : 0,
                'match_coverage_pct' => $coveragePct,
                'pantry_hits' => $hits,
                'missing_ingredients' => $missingApprox,
                'partial_match_bonus' => round($partialBonus, 2),
            ];
        });

        $lastPage = max(1, (int) ceil($totalRanked / $perPage));

        $payload = [
            'data' => $collection->values()->all(),
            'current_page' => $page,
            'last_page' => $lastPage,
            'per_page' => $perPage,
            'total' => $totalRanked,
            'meta' => [
                'pantry_size' => count($pantryIds),
                'strict_and_match' => false,
                'unmatched_ingredient_ids' => $unmatchedIngredientIds,
                'unmatched_ingredients' => $unmatchedIngredientNames,
            ],
        ];

        if ($collection->isEmpty()) {
            $payload['meta']['suggestions'] = $this->matchSuggestionsFallback();
            $payload['meta']['message'] = 'Try fewer filters or add staple ingredients.';
        }

        return response()->json($payload);
    }

    /**
     * @return list<array{id:int,name:string,category:?string}>
     */
    protected function matchSuggestionsFallback(): array
    {
        return Recipe::query()
            ->withAvg('ratings as average_rating', 'rating')
            ->orderByDesc('average_rating')
            ->limit(5)
            ->get(['id', 'name', 'category'])
            ->map(static fn ($r) => [
                'id' => $r->id,
                'name' => $r->name,
                'category' => $r->category,
            ])
            ->values()
            ->all();
    }

    /**
     * Weighted recommendations + boost scores (Sprint 8 Task 84).
     */
    public function recommend(Request $request)
    {
        $limit = min(30, max(5, (int) $request->get('limit', 15)));
        $userId = (int) ($request->user()?->id ?? 0);
        $latestViewActivityId = $userId > 0
            ? (int) (UserActivity::query()
                ->where('user_id', $userId)
                ->whereIn('action', ['view_recipe', 'favorite_recipe'])
                ->max('id') ?? 0)
            : 0;

        $cacheKey = 'recommend:v'.$this->recommendationCacheVersion().':u'.$userId.':l'.$limit.':a'.$latestViewActivityId;

        return response()->json(Cache::remember($cacheKey, now()->addMinutes(10), function () use ($limit, $userId) {
            $favoriteIds = $userId > 0
                ? DB::table('favorites')->where('user_id', $userId)->pluck('recipe_id')->map(static fn ($id): int => (int) $id)->values()->all()
                : [];

            $collectionIds = $userId > 0
                ? DB::table('collection_recipe')
                    ->join('collections', 'collections.id', '=', 'collection_recipe.collection_id')
                    ->where('collections.user_id', $userId)
                    ->pluck('collection_recipe.recipe_id')
                    ->map(static fn ($id): int => (int) $id)->values()->all()
                : [];

            $recentViewIds = $userId > 0
                ? UserActivity::query()
                    ->where('user_id', $userId)
                    ->where('action', 'view_recipe')
                    ->whereNotNull('recipe_id')
                    ->latest('id')
                    ->limit(30)
                    ->pluck('recipe_id')
                    ->map(static fn ($id): int => (int) $id)->values()->all()
                : [];

            $interactionFrequency = $userId > 0
                ? UserActivity::query()
                    ->where('user_id', $userId)
                    ->whereIn('action', ['view_recipe', 'favorite_recipe', 'cook_now_open'])
                    ->whereNotNull('recipe_id')
                    ->selectRaw('recipe_id, COUNT(*) as c')
                    ->groupBy('recipe_id')
                    ->pluck('c', 'recipe_id')
                    ->map(static fn ($v): int => (int) $v)
                    ->all()
                : [];

            $seedIds = array_values(array_unique(array_merge($favoriteIds, $collectionIds, $recentViewIds)));

            $favoriteIngredientIds = $seedIds === []
                ? []
                : DB::table('recipe_ingredient')
                    ->whereIn('recipe_id', $seedIds)
                    ->pluck('ingredient_id')
                    ->map(static fn ($id): int => (int) $id)
                    ->values()
                    ->all();

            $favoriteCategories = $seedIds === []
                ? []
                : Recipe::query()->whereIn('id', $seedIds)->whereNotNull('category')->pluck('category')->map(static fn ($v): string => (string) $v)->values()->all();

            $hasBoostScores = Schema::hasTable('recipe_boost_scores');
            $favoriteSet = array_fill_keys($favoriteIds, true);
            $collectionSet = array_fill_keys($collectionIds, true);
            $recentSet = array_fill_keys($recentViewIds, true);
            $favoriteCategorySet = array_fill_keys($favoriteCategories, true);
            $favoriteIngredientSet = array_fill_keys($favoriteIngredientIds, true);

            $ratingAgg = DB::table('ratings')
                ->selectRaw('recipe_id, AVG(rating) as avg_rating')
                ->groupBy('recipe_id');

            $favoriteAgg = DB::table('favorites')
                ->selectRaw('recipe_id, COUNT(*) as fav_count')
                ->groupBy('recipe_id');

            $query = Recipe::query()
                ->select([
                    'recipes.id',
                    'recipes.name',
                    'recipes.category',
                    'recipes.difficulty',
                    'recipes.cooking_time',
                    'recipes.instructions',
                    'recipes.image',
                ])
                ->leftJoinSub($favoriteAgg, 'fav_agg', function ($join) {
                    $join->on('fav_agg.recipe_id', '=', 'recipes.id');
                })
                ->leftJoinSub($ratingAgg, 'rating_agg', function ($join) {
                    $join->on('rating_agg.recipe_id', '=', 'recipes.id');
                });

            if ($hasBoostScores) {
                $query->leftJoin('recipe_boost_scores as rbs', 'rbs.recipe_id', '=', 'recipes.id');
            }

            $globalScoreSql = $hasBoostScores
                ? 'COALESCE(rbs.recommend_clicks, 0) * 3 + COALESCE(rbs.recommend_saves, 0) * 5 + COALESCE(fav_agg.fav_count, 0) * 2 + COALESCE(rating_agg.avg_rating, 0) * 8'
                : 'COALESCE(fav_agg.fav_count, 0) * 2 + COALESCE(rating_agg.avg_rating, 0) * 8';

            $candidates = $query
                ->addSelect([
                    DB::raw('COALESCE(rating_agg.avg_rating, 0) as average_rating'),
                    DB::raw("($globalScoreSql) as global_rank_score"),
                ])
                ->orderByDesc('global_rank_score')
                ->orderByDesc('recipes.id')
                ->limit(120)
                ->get();

            if ($candidates->isEmpty()) {
                return [];
            }

            $candidateIds = $candidates->pluck('id')->map(static fn ($id): int => (int) $id)->values()->all();
            $recipeIngredientIdsMap = DB::table('recipe_ingredient')
                ->whereIn('recipe_id', $candidateIds)
                ->select(['recipe_id', 'ingredient_id'])
                ->get()
                ->groupBy('recipe_id')
                ->map(static fn ($rows) => collect($rows)->pluck('ingredient_id')->map(static fn ($id): int => (int) $id)->values()->all())
                ->all();

            $ingredientNamesByRecipe = DB::table('recipe_ingredient')
                ->join('ingredients', 'ingredients.id', '=', 'recipe_ingredient.ingredient_id')
                ->whereIn('recipe_ingredient.recipe_id', $candidateIds)
                ->select(['recipe_ingredient.recipe_id', 'ingredients.name'])
                ->get()
                ->groupBy('recipe_id')
                ->map(static fn ($rows) => collect($rows)->pluck('name')->values()->all())
                ->all();

            $scored = $candidates
                ->map(function (Recipe $recipe) use ($recipeIngredientIdsMap, $ingredientNamesByRecipe, $favoriteSet, $collectionSet, $recentSet, $interactionFrequency, $favoriteCategorySet, $favoriteIngredientSet) {
                    $rid = (int) $recipe->id;
                    $global = (float) ($recipe->global_rank_score ?? 0);
                    $personal = 0.0;

                    if (isset($favoriteSet[$rid])) {
                        $personal += 18;
                    }
                    if (isset($collectionSet[$rid])) {
                        $personal += 14;
                    }
                    if (isset($recentSet[$rid])) {
                        $personal += 10;
                    }
                    $personal += min(24, ((int) ($interactionFrequency[$rid] ?? 0)) * 1.8);

                    $category = (string) ($recipe->category ?? '');
                    if ($category !== '' && isset($favoriteCategorySet[$category])) {
                        $personal += 8;
                    }

                    if ($favoriteIngredientSet !== []) {
                        $overlap = 0;
                        foreach (($recipeIngredientIdsMap[$rid] ?? []) as $ingId) {
                            if (isset($favoriteIngredientSet[$ingId])) {
                                $overlap++;
                            }
                        }
                        $personal += min(20, $overlap * 2.5);
                    }

                    return [
                        'id' => $rid,
                        'name' => $recipe->name,
                        'category' => $recipe->category,
                        'difficulty' => $recipe->difficulty ?? 'medium',
                        'cooking_time' => (int) ($recipe->cooking_time ?? 30),
                        'instructions' => $recipe->instructions,
                        'image_url' => $recipe->image_url,
                        'image' => $recipe->image_url,
                        'ingredients' => $ingredientNamesByRecipe[$rid] ?? [],
                        'average_rating' => round((float) ($recipe->average_rating ?? 0), 1),
                        'recommendation_score' => round($global + $personal, 2),
                    ];
                })
                ->sortByDesc('recommendation_score')
                ->values();

            if ($scored->isEmpty()) {
                return [];
            }

            $out = $scored
                ->unique(static fn (array $item): string => mb_strtolower(trim((string) ($item['name'] ?? ''))))
                ->values()
                ->take($limit)
                ->all();

            // Safety fallback so recommendations never come back empty
            // when candidate scoring is unexpectedly constrained.
            if ($out === []) {
                $fallback = Recipe::query()
                    ->with(['ingredients:id,name'])
                    ->withAvg('ratings as average_rating', 'rating')
                    ->orderByDesc('id')
                    ->limit($limit)
                    ->get();

                return $fallback->map(function (Recipe $recipe) {
                    $avg = $recipe->average_rating;

                    return [
                        'id' => $recipe->id,
                        'name' => $recipe->name,
                        'category' => $recipe->category,
                        'difficulty' => $recipe->difficulty ?? 'medium',
                        'cooking_time' => (int) ($recipe->cooking_time ?? 30),
                        'instructions' => $recipe->instructions,
                        'image_url' => $recipe->image_url,
                        'image' => $recipe->image_url,
                        'ingredients' => $recipe->ingredients->pluck('name'),
                        'average_rating' => $avg !== null ? round((float) $avg, 1) : 0,
                        'recommendation_score' => 0,
                    ];
                })
                    ->unique(static fn (array $item): string => mb_strtolower(trim((string) ($item['name'] ?? ''))))
                    ->values()
                    ->take($limit)
                    ->all();
            }

            return $out;
        }));
    }

    public function homeFeed(Request $request)
    {
        $userId = (int) ($request->user()?->id ?? 0);
        $cacheKey = 'feed:v'.(int) Cache::get('trending_cache_version', 1).':u'.$userId;
        $payload = Cache::remember($cacheKey, now()->addMinutes(5), function () use ($request, $userId) {
            $recommended = $this->recommend($request)->getData(true);
            $recommended = is_array($recommended) ? array_slice($recommended, 0, 8) : [];

            $activityRecipeIds = $userId > 0
            ? UserActivity::query()
                ->where('user_id', $userId)
                ->whereIn('action', ['view_recipe', 'favorite_recipe'])
                ->whereNotNull('recipe_id')
                ->latest('id')
                ->limit(25)
                ->pluck('recipe_id')
                ->map(static fn ($id): int => (int) $id)->unique()->values()->all()
            : [];

            $basedOnActivity = Recipe::query()
            ->with('ingredients:id,name')
            ->withAvg('ratings as average_rating', 'rating')
            ->whereIn('id', $activityRecipeIds)
            ->limit(8)
            ->get()
            ->map(fn (Recipe $r) => $this->toFeedRecipe($r))
            ->values()
            ->all();

            $trendingIds = UserActivity::query()
            ->where('action', 'view_recipe')
            ->whereNotNull('recipe_id')
            ->selectRaw('recipe_id, COUNT(*) as c')
            ->groupBy('recipe_id')
            ->orderByDesc('c')
            ->limit(8)
            ->pluck('recipe_id')
            ->map(static fn ($id): int => (int) $id)->values()->all();

            $trending = Recipe::query()
            ->with('ingredients:id,name')
            ->withAvg('ratings as average_rating', 'rating')
            ->whereIn('id', $trendingIds)
            ->get()
            ->sortBy(fn ($r) => array_search((int) $r->id, $trendingIds, true))
            ->values()
            ->map(fn (Recipe $r) => $this->toFeedRecipe($r))
            ->values()
            ->all();

            return [
                'recommended_for_you' => $recommended,
                'based_on_your_activity' => $basedOnActivity,
                'trending' => $trending,
            ];
        });

        return response()->json($payload);
    }

    public function ingredientSubstitutions(Request $request)
    {
        $v = $request->validate([
            'ingredients' => 'required|array|min:1',
            'ingredients.*' => 'string|max:100',
        ]);

        $rules = [
            'garlic' => ['onion powder', 'garlic powder', 'shallots'],
            'onion' => ['shallots', 'leeks', 'onion powder'],
            'soy sauce' => ['tamari', 'coconut aminos', 'fish sauce + water'],
            'milk' => ['evaporated milk', 'oat milk', 'soy milk'],
            'butter' => ['margarine', 'olive oil', 'coconut oil'],
            'egg' => ['mashed banana', 'flaxseed gel', 'silken tofu'],
            'tomato' => ['tomato paste + water', 'canned tomatoes', 'roasted red pepper'],
            'vinegar' => ['calamansi juice', 'lemon juice', 'apple cider vinegar'],
            'ginger' => ['galangal', 'ground ginger', 'turmeric + pepper'],
            'bread crumbs' => ['crushed crackers', 'oats', 'panko'],
        ];

        $learned = [];
        if (Schema::hasTable('ingredient_substitution_feedback')) {
            foreach ($v['ingredients'] as $name) {
                $k = mb_strtolower(trim((string) $name));
                $learned[$k] = DB::table('ingredient_substitution_feedback')
                    ->where('ingredient', $k)
                    ->orderByDesc('accepted_count')
                    ->orderBy('substitute')
                    ->limit(3)
                    ->pluck('substitute')
                    ->map(static fn ($s): string => (string) $s)
                    ->values()
                    ->all();
            }
        }

        $out = [];
        foreach ($v['ingredients'] as $name) {
            $k = mb_strtolower(trim((string) $name));
            $found = $learned[$k] ?? null;
            if ($found === [] || $found === null) {
                $found = $rules[$k] ?? null;
            }
            if ($found === null) {
                foreach ($rules as $key => $alts) {
                    if (str_contains($k, $key) || str_contains($key, $k)) {
                        $found = $alts;
                        break;
                    }
                }
            }
            $out[] = [
                'ingredient' => $name,
                'alternatives' => $found ?? ['No direct match yet. Try a similar aromatic or pantry staple.'],
            ];
        }

        return response()->json(['data' => $out]);
    }

    /**
     * Sprint 9 Task 97 — learn substitution choices over time.
     */
    public function substitutionFeedback(Request $request)
    {
        $v = $request->validate([
            'ingredient' => 'required|string|max:100',
            'substitute' => 'required|string|max:100',
            'accepted' => 'required|boolean',
        ]);

        if (! Schema::hasTable('ingredient_substitution_feedback')) {
            return response()->json([
                'success' => false,
                'message' => 'Substitution learning table not available.',
            ], 409);
        }

        $ingredient = mb_strtolower(trim((string) $v['ingredient']));
        $substitute = mb_strtolower(trim((string) $v['substitute']));
        $now = now();

        $row = DB::table('ingredient_substitution_feedback')
            ->where('ingredient', $ingredient)
            ->where('substitute', $substitute)
            ->first();

        if ($row) {
            DB::table('ingredient_substitution_feedback')
                ->where('ingredient', $ingredient)
                ->where('substitute', $substitute)
                ->update([
                    'accepted_count' => ($row->accepted_count ?? 0) + ($v['accepted'] ? 1 : 0),
                    'rejected_count' => ($row->rejected_count ?? 0) + ($v['accepted'] ? 0 : 1),
                    'updated_at' => $now,
                ]);
        } else {
            DB::table('ingredient_substitution_feedback')->insert([
                'ingredient' => $ingredient,
                'substitute' => $substitute,
                'accepted_count' => $v['accepted'] ? 1 : 0,
                'rejected_count' => $v['accepted'] ? 0 : 1,
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }

        return response()->json(['success' => true]);
    }

    /**
     * Sprint 9 Task 91 — suggest ingredient combinations ("Try adding").
     */
    public function ingredientCombinationPredictor(Request $request)
    {
        $v = $request->validate([
            'ingredient_ids' => 'required|array|min:1',
            'ingredient_ids.*' => 'integer|min:1',
            'limit' => 'nullable|integer|min:1|max:12',
        ]);

        $seedIds = array_values(array_unique(array_map(static fn ($id): int => (int) $id, $v['ingredient_ids'])));
        $limit = (int) ($v['limit'] ?? 6);

        if ($seedIds === []) {
            return response()->json(['data' => []]);
        }

        $recipeIds = DB::table('recipe_ingredient')
            ->whereIn('ingredient_id', $seedIds)
            ->pluck('recipe_id')
            ->map(static fn ($id): int => (int) $id)
            ->values()
            ->all();

        if ($recipeIds === []) {
            return response()->json(['data' => []]);
        }

        $rows = DB::table('recipe_ingredient as ri')
            ->join('ingredients as i', 'i.id', '=', 'ri.ingredient_id')
            ->whereIn('ri.recipe_id', $recipeIds)
            ->whereNotIn('ri.ingredient_id', $seedIds)
            ->selectRaw('ri.ingredient_id, i.name, COUNT(*) as freq')
            ->groupBy('ri.ingredient_id', 'i.name')
            ->orderByDesc('freq')
            ->limit($limit)
            ->get();

        return response()->json([
            'data' => collect($rows)->map(static fn ($r) => [
                'ingredient_id' => (int) $r->ingredient_id,
                'name' => (string) $r->name,
                'frequency' => (int) $r->freq,
            ])->values()->all(),
        ]);
    }

    /**
     * Sprint 9 Task 92 — rule-based AI cooking assistant.
     */
    public function cookingAssistant(Request $request)
    {
        $v = $request->validate([
            'message' => 'required|string|max:500',
            'ingredient_ids' => 'nullable|array',
            'ingredient_ids.*' => 'integer|min:1',
            'conversation' => 'nullable|array|max:20',
            'conversation.*.role' => 'required_with:conversation|string|in:user,assistant',
            'conversation.*.content' => 'required_with:conversation|string|max:1200',
        ]);

        $msgRaw = trim((string) $v['message']);
        $msg = Str::lower($msgRaw);
        $ingredientIds = collect($v['ingredient_ids'] ?? [])->map(static fn ($id): int => (int) $id)->filter()->unique()->values()->all();
        $conversation = collect($v['conversation'] ?? [])
            ->map(static fn ($item): array => [
                'role' => (string) ($item['role'] ?? 'user'),
                'content' => trim((string) ($item['content'] ?? '')),
            ])
            ->filter(static fn ($item): bool => $item['content'] !== '')
            ->values()
            ->all();
        $msgContainsPantryContext = str_contains($msg, 'i have')
            || str_contains($msg, 'available')
            || str_contains($msg, 'in my pantry')
            || str_contains($msg, 'with ');

        $extractIngredientIdsFromMessage = static function (string $messageLower): array {
            $clean = preg_replace('/[^a-z0-9\s]/i', ' ', $messageLower) ?? '';
            $clean = preg_replace('/\s+/', ' ', trim($clean)) ?? '';
            if ($clean === '') {
                return [];
            }

            $tokens = collect(explode(' ', $clean))
                ->map(static fn ($w): string => trim((string) $w))
                ->filter(static fn ($w): bool => strlen($w) >= 3)
                ->unique()
                ->take(14)
                ->values()
                ->all();
            if ($tokens === []) {
                return [];
            }

            $rows = Ingredient::query()
                ->select(['id', 'name'])
                ->where(function ($q) use ($tokens) {
                    foreach ($tokens as $token) {
                        $q->orWhere('name', 'like', '%'.$token.'%');
                    }
                })
                ->limit(120)
                ->get();

            return $rows
                ->filter(static function ($row) use ($clean): bool {
                    $name = Str::lower(trim((string) ($row->name ?? '')));
                    if ($name === '' || strlen($name) < 3) {
                        return false;
                    }
                    return str_contains($clean, $name);
                })
                ->map(static fn ($row): int => (int) $row->id)
                ->filter(static fn ($id): bool => $id > 0)
                ->unique()
                ->values()
                ->all();
        };

        if ($ingredientIds === []) {
            $ingredientIds = $extractIngredientIdsFromMessage($msg);
        }

        $response = [
            'reply' => 'I can help with recipes, ingredients, substitutions, cook-now matches, and app features.',
            'suggestions' => [],
        ];

        $formatRecipeSuggestions = static fn ($rows): array => collect($rows)->map(static fn ($r) => [
            'id' => (int) $r->id,
            'name' => (string) $r->name,
        ])->values()->all();

        if (str_contains($msg, 'hello') || str_contains($msg, 'hi')) {
            $response['reply'] = 'Hi! Ask me things like "what can I cook", "substitute for milk", "ingredients of adobo", or "how many recipes".';
            return response()->json($response);
        }

        if (str_contains($msg, 'how many recipe') || str_contains($msg, 'total recipe')) {
            $count = Recipe::query()->count();
            $response['reply'] = "There are currently {$count} recipes in QuickCook.";
            return response()->json($response);
        }

        if (str_contains($msg, 'how many ingredient') || str_contains($msg, 'total ingredient')) {
            $count = Ingredient::query()->count();
            $response['reply'] = "There are {$count} ingredients in the system.";
            return response()->json($response);
        }

        if (str_contains($msg, 'recommend')) {
            $recommended = collect($this->recommend($request)->getData(true))->take(5)->values();
            $response['reply'] = 'Here are personalized recommendations for you.';
            $response['suggestions'] = $recommended->map(static fn ($r) => [
                'id' => (int) ($r['id'] ?? 0),
                'name' => (string) ($r['name'] ?? 'Recipe'),
            ])->filter(static fn ($r) => $r['id'] > 0)->values()->all();
            return response()->json($response);
        }

        if (preg_match('/ingredients?\s+of\s+(.+)/iu', $msgRaw, $m) === 1) {
            $recipeName = trim((string) ($m[1] ?? ''));
            if ($recipeName !== '') {
                $recipe = Recipe::query()
                    ->with('ingredients:id,name')
                    ->where('name', 'like', '%'.$recipeName.'%')
                    ->first();
                if ($recipe) {
                    $ings = $recipe->ingredients->pluck('name')->take(8)->implode(', ');
                    $response['reply'] = "Ingredients for {$recipe->name}: {$ings}.";
                    $response['suggestions'] = [['id' => (int) $recipe->id, 'name' => (string) $recipe->name]];
                    return response()->json($response);
                }
            }
            $response['reply'] = 'I could not find that recipe yet. Try another recipe name.';
            return response()->json($response);
        }

        if (preg_match('/difficulty\s+of\s+(.+)/iu', $msgRaw, $m) === 1) {
            $recipeName = trim((string) ($m[1] ?? ''));
            if ($recipeName !== '') {
                $recipe = Recipe::query()->where('name', 'like', '%'.$recipeName.'%')->first();
                if ($recipe) {
                    $response['reply'] = "{$recipe->name} is tagged as ".strtoupper((string) ($recipe->difficulty ?? 'medium')).' difficulty.';
                    $response['suggestions'] = [['id' => (int) $recipe->id, 'name' => (string) $recipe->name]];
                    return response()->json($response);
                }
            }
            $response['reply'] = 'I could not find that recipe to check difficulty.';
            return response()->json($response);
        }

        if (str_contains($msg, 'substitute')) {
            $parts = preg_split('/substitute for/i', $msgRaw) ?: [];
            $target = trim((string) ($parts[1] ?? ''));
            if ($target !== '') {
                $sub = $this->ingredientSubstitutions(new Request(['ingredients' => [$target]]))->getData(true);
                $alts = $sub['data'][0]['alternatives'] ?? [];
                $response['reply'] = 'You can try these substitutes for '.$target.': '.implode(', ', array_slice($alts, 0, 4)).'.';
                return response()->json($response);
            }
        }

        if (str_contains($msg, 'trending')) {
            $trendingIds = UserActivity::query()
                ->where('action', 'view_recipe')
                ->whereNotNull('recipe_id')
                ->selectRaw('recipe_id, COUNT(*) as c')
                ->groupBy('recipe_id')
                ->orderByDesc('c')
                ->limit(5)
                ->pluck('recipe_id')
                ->map(static fn ($id): int => (int) $id)->values()->all();
            $rows = Recipe::query()->whereIn('id', $trendingIds)->get(['id', 'name']);
            $response['reply'] = 'These are trending recipes right now.';
            $response['suggestions'] = $formatRecipeSuggestions($rows);
            return response()->json($response);
        }

        if (str_contains($msg, 'what can i cook') || str_contains($msg, 'cook now') || ($msgContainsPantryContext && $ingredientIds !== [])) {
            if ($ingredientIds === []) {
                $quickStarter = Recipe::query()
                    ->whereNotNull('id')
                    ->orderByDesc('id')
                    ->limit(5)
                    ->get(['id', 'name']);
                $response['reply'] = 'Select ingredients first, then ask "what can I cook now?" for exact matches. For now, here are starter ideas.';
                $response['suggestions'] = $formatRecipeSuggestions($quickStarter);
                return response()->json($response);
            }
            $matchRequest = new Request([
                'ingredient_ids' => $ingredientIds,
                'per_page' => 5,
            ]);
            $matchData = $this->match($matchRequest)->getData(true);
            $recipes = $matchData['data'] ?? [];
            if ($recipes !== []) {
                $response['reply'] = 'Here are recipes you can start with now.';
                $response['suggestions'] = array_map(static fn ($r) => [
                    'id' => (int) $r['id'],
                    'name' => (string) $r['name'],
                ], array_slice($recipes, 0, 5));
                return response()->json($response);
            }
            $response['reply'] = 'No direct matches yet. Try fewer filters or add staples like onion, garlic, and egg.';
            return response()->json($response);
        }

        if (str_contains($msg, 'quick') || str_contains($msg, 'under 30')) {
            $quick = Recipe::query()
                ->where('cooking_time', '<=', 30)
                ->orderBy('cooking_time')
                ->limit(5)
                ->get(['id', 'name']);
            $response['reply'] = 'Here are quick meal ideas under 30 minutes.';
            $response['suggestions'] = $formatRecipeSuggestions($quick);
            return response()->json($response);
        }

        if (str_contains($msg, 'how long') || str_contains($msg, 'how many minute') || str_contains($msg, 'minutes')) {
            $recipeHint = '';
            if (preg_match('/(?:for|of)\s+(.+)/iu', $msgRaw, $m) === 1) {
                $recipeHint = trim((string) ($m[1] ?? ''));
            }

            if ($recipeHint !== '') {
                $recipe = Recipe::query()
                    ->where('name', 'like', '%'.$recipeHint.'%')
                    ->first(['id', 'name', 'cooking_time']);
                if ($recipe) {
                    $mins = (int) ($recipe->cooking_time ?? 0);
                    $response['reply'] = $mins > 0
                        ? "{$recipe->name} usually takes about {$mins} minutes."
                        : "I found {$recipe->name}, but cooking time is not set yet.";
                    $response['suggestions'] = [['id' => (int) $recipe->id, 'name' => (string) $recipe->name]];
                    return response()->json($response);
                }
            }

            // Use recent assistant suggestions from conversation context.
            $suggestedNames = [];
            foreach (array_reverse($conversation) as $turn) {
                if (($turn['role'] ?? '') !== 'assistant') {
                    continue;
                }
                $content = (string) ($turn['content'] ?? '');
                if (preg_match('/Suggested recipes:\s*(.+)$/imu', $content, $m) === 1) {
                    $raw = trim((string) ($m[1] ?? ''));
                    if ($raw !== '') {
                        $suggestedNames = array_values(array_filter(array_map(static fn ($v): string => trim((string) $v), explode('|', $raw))));
                        break;
                    }
                }
            }

            if ($suggestedNames !== []) {
                $rows = Recipe::query()
                    ->where(function ($q) use ($suggestedNames) {
                        foreach ($suggestedNames as $name) {
                            $q->orWhere('name', 'like', '%'.$name.'%');
                        }
                    })
                    ->limit(5)
                    ->get(['id', 'name', 'cooking_time']);

                if ($rows->isNotEmpty()) {
                    $lines = $rows->map(static function ($r): string {
                        $mins = (int) ($r->cooking_time ?? 0);
                        return $mins > 0 ? "- {$r->name}: {$mins} min" : "- {$r->name}: time not set";
                    })->values()->all();
                    $response['reply'] = "Here are the cooking times from the last suggested recipes:\n".implode("\n", $lines);
                    $response['suggestions'] = $formatRecipeSuggestions($rows);
                    return response()->json($response);
                }
            }

            $response['reply'] = 'I can estimate minutes if you include a recipe name, for example: "how many minutes for adobo?"';
            return response()->json($response);
        }

        if (str_contains($msg, 'cook now mode') || str_contains($msg, 'pantry')) {
            $response['reply'] = 'Cook Now Mode shows recipes you can cook immediately with selected ingredients. Pantry matching highlights your best-fit recipes.';
            return response()->json($response);
        }

        if (
            str_contains($msg, 'another recipe')
            || str_contains($msg, 'another one')
            || str_contains($msg, 'more recipe')
            || str_contains($msg, 'give me another')
            || str_contains($msg, 'more suggestions')
        ) {
            $excludeNames = [];
            foreach (array_reverse($conversation) as $turn) {
                if (($turn['role'] ?? '') !== 'assistant') {
                    continue;
                }
                $content = (string) ($turn['content'] ?? '');
                if (preg_match('/Suggested recipes:\s*(.+)$/imu', $content, $m) === 1) {
                    $raw = trim((string) ($m[1] ?? ''));
                    if ($raw !== '') {
                        $excludeNames = array_values(array_filter(array_map(static fn ($v): string => trim((string) $v), explode('|', $raw))));
                        break;
                    }
                }
            }

            if ($ingredientIds !== []) {
                $matchRequest = new Request([
                    'ingredient_ids' => $ingredientIds,
                    'per_page' => 12,
                ]);
                $matchData = $this->match($matchRequest)->getData(true);
                $recipes = collect($matchData['data'] ?? [])
                    ->filter(static function ($r) use ($excludeNames): bool {
                        $name = trim((string) ($r['name'] ?? ''));
                        if ($name === '') {
                            return false;
                        }
                        foreach ($excludeNames as $ex) {
                            if ($ex !== '' && strcasecmp($name, $ex) === 0) {
                                return false;
                            }
                        }
                        return true;
                    })
                    ->take(5)
                    ->values()
                    ->all();

                if ($recipes !== []) {
                    $response['reply'] = 'Sure, here are more recipes you can try.';
                    $response['suggestions'] = array_map(static fn ($r) => [
                        'id' => (int) ($r['id'] ?? 0),
                        'name' => (string) ($r['name'] ?? 'Recipe'),
                    ], $recipes);
                    return response()->json($response);
                }
            }

            $rows = Recipe::query()
                ->where(function ($q) use ($excludeNames) {
                    foreach ($excludeNames as $name) {
                        if ($name !== '') {
                            $q->where('name', 'not like', '%'.$name.'%');
                        }
                    }
                })
                ->inRandomOrder()
                ->limit(5)
                ->get(['id', 'name']);

            if ($rows->isNotEmpty()) {
                $response['reply'] = 'Sure, here are more recipe ideas.';
                $response['suggestions'] = $formatRecipeSuggestions($rows);
                return response()->json($response);
            }
        }

        $nameMatches = Recipe::query()
            ->where('name', 'like', '%'.$msgRaw.'%')
            ->limit(5)
            ->get(['id', 'name']);
        if ($nameMatches->isNotEmpty()) {
            $response['reply'] = 'I found recipes related to your question.';
            $response['suggestions'] = $formatRecipeSuggestions($nameMatches);
            return response()->json($response);
        }

        $llm = $this->askGeminiAssistant($msgRaw, $conversation, $ingredientIds);
        if ($llm !== null) {
            return response()->json($llm);
        }

        $response['reply'] = 'I can still help. Try asking in this format: "what can I cook with garlic and egg", "ingredients of adobo", "substitute for milk", or "how many minutes for sinigang".';
        return response()->json($response);
    }

    /**
     * Sprint 9 Task 94 — personalized cooking insights.
     */
    public function personalizedInsights(Request $request)
    {
        $userId = (int) ($request->user()?->id ?? 0);
        if ($userId <= 0) {
            return response()->json(['data' => []]);
        }

        $favoriteCategories = DB::table('favorites')
            ->join('recipes', 'recipes.id', '=', 'favorites.recipe_id')
            ->where('favorites.user_id', $userId)
            ->whereNotNull('recipes.category')
            ->selectRaw('recipes.category, COUNT(*) as c')
            ->groupBy('recipes.category')
            ->orderByDesc('c')
            ->limit(3)
            ->get();

        $avgCooking = DB::table('user_activities')
            ->join('recipes', 'recipes.id', '=', 'user_activities.recipe_id')
            ->where('user_activities.user_id', $userId)
            ->where('user_activities.action', 'view_recipe')
            ->avg('recipes.cooking_time');

        $habit = 'balanced meals';
        if ($avgCooking !== null && (float) $avgCooking <= 30) {
            $habit = 'quick meals under 30 mins';
        } elseif ($avgCooking !== null && (float) $avgCooking >= 60) {
            $habit = 'slow and detailed cooking';
        }

        return response()->json([
            'data' => [
                'favorite_categories' => $favoriteCategories->map(static fn ($r) => [
                    'category' => (string) $r->category,
                    'count' => (int) $r->c,
                ])->values()->all(),
                'average_cooking_time' => $avgCooking !== null ? (int) round((float) $avgCooking) : null,
                'habit_message' => 'You prefer '.$habit.'.',
            ],
        ]);
    }

    /**
     * Sprint 9 Task 95 — smart notifications payload.
     */
    public function smartNotifications(Request $request)
    {
        $userId = (int) ($request->user()?->id ?? 0);
        $messages = [];

        if ($userId > 0) {
            $recentFavoriteCategory = DB::table('favorites')
                ->join('recipes', 'recipes.id', '=', 'favorites.recipe_id')
                ->where('favorites.user_id', $userId)
                ->whereNotNull('recipes.category')
                ->orderByDesc('favorites.id')
                ->value('recipes.category');

            if ($recentFavoriteCategory) {
                $messages[] = [
                    'type' => 'similar_recipes',
                    'title' => 'New recipes in '.$recentFavoriteCategory,
                    'body' => 'Fresh picks similar to your favorites are available.',
                ];
            }

            $lastActivityAt = UserActivity::query()
                ->where('user_id', $userId)
                ->max('created_at');

            if ($lastActivityAt && now()->diffInDays($lastActivityAt) >= 3) {
                $messages[] = [
                    'type' => 're_engage',
                    'title' => 'Ready to cook again?',
                    'body' => 'Your pantry matches may have new ideas today.',
                ];
            }
        }

        if ($messages === []) {
            $messages[] = [
                'type' => 'trending',
                'title' => 'Trending now',
                'body' => 'Check today\'s most cooked recipes.',
            ];
        }

        return response()->json(['data' => $messages]);
    }

    /**
     * Sprint 9 Task 98 — cook-now mode (strict ready recipes).
     */
    public function cookNow(Request $request)
    {
        $v = $request->validate([
            'ingredient_ids' => 'required|array|min:1',
            'ingredient_ids.*' => 'integer|min:1',
            'limit' => 'nullable|integer|min:1|max:30',
        ]);

        $ids = collect($v['ingredient_ids'])->map(static fn ($id): int => (int) $id)->filter()->unique()->values()->all();
        $limit = (int) ($v['limit'] ?? 12);
        if ($ids === []) {
            return response()->json(['data' => []]);
        }

        $recipes = Recipe::query()
            ->with(['ingredients:id,name'])
            ->withAvg('ratings as average_rating', 'rating')
            ->whereHas('ingredients', function ($q) use ($ids) {
                $q->whereIn('ingredients.id', $ids);
            }, '>=', count($ids))
            ->orderByDesc('average_rating')
            ->limit($limit)
            ->get();

        return response()->json([
            'data' => $recipes->map(fn (Recipe $r) => array_merge($this->toFeedRecipe($r), [
                'ready_to_cook' => true,
            ]))->values()->all(),
        ]);
    }

    /**
     * Sprint 9 Task 93 — auto-tagging helper for admin form.
     */
    public function autoTagRecipe(Request $request)
    {
        $v = $request->validate([
            'name' => 'nullable|string|max:255',
            'instructions' => 'nullable|string|max:10000',
            'ingredients' => 'nullable|array',
            'ingredients.*' => 'string|max:120',
        ]);

        $name = mb_strtolower((string) ($v['name'] ?? ''));
        $instructions = mb_strtolower((string) ($v['instructions'] ?? ''));
        $ingredients = collect($v['ingredients'] ?? [])->map(static fn ($x): string => mb_strtolower(trim((string) $x)))->filter()->values()->all();
        $text = $name.' '.$instructions.' '.implode(' ', $ingredients);

        $category = 'Dinner';
        if (str_contains($text, 'breakfast') || str_contains($text, 'omelette') || str_contains($text, 'pancake')) {
            $category = 'Breakfast';
        } elseif (str_contains($text, 'snack') || str_contains($text, 'sandwich')) {
            $category = 'Snack';
        } elseif (str_contains($text, 'dessert') || str_contains($text, 'cake') || str_contains($text, 'sweet')) {
            $category = 'Dessert';
        } elseif (str_contains($text, 'lunch')) {
            $category = 'Lunch';
        }

        $stepSignals = preg_match_all('/\b(step|mix|boil|fry|saute|bake|marinate|simmer)\b/u', $instructions);
        $ingredientCount = count($ingredients);
        $difficulty = 'easy';
        if ($ingredientCount >= 12 || $stepSignals >= 7 || str_contains($text, 'marinate')) {
            $difficulty = 'hard';
        } elseif ($ingredientCount >= 8 || $stepSignals >= 4) {
            $difficulty = 'medium';
        }

        $cookingTime = 20;
        if ($difficulty === 'medium') {
            $cookingTime = 35;
        } elseif ($difficulty === 'hard') {
            $cookingTime = 55;
        }

        return response()->json([
            'data' => [
                'category' => $category,
                'difficulty' => $difficulty,
                'cooking_time' => $cookingTime,
                'explain' => 'Auto-tag uses ingredient count + cooking-step signals + recipe keywords.',
            ],
        ]);
    }

    /**
     * Feedback for recommendation ranking (click vs save funnel).
     */
    public function recommendationFeedback(Request $request)
    {
        $v = $request->validate([
            'recipe_id' => 'required|integer|exists:recipes,id',
            'signal' => 'required|string|in:click,save',
        ]);

        // Graceful fallback for environments that don't have sprint-8 table yet.
        if (! Schema::hasTable('recipe_boost_scores')) {
            return response()->json([
                'success' => true,
                'skipped' => true,
                'reason' => 'recipe_boost_scores table is missing',
            ]);
        }

        $col = $v['signal'] === 'click' ? 'recommend_clicks' : 'recommend_saves';

        $exists = DB::table('recipe_boost_scores')->where('recipe_id', $v['recipe_id'])->exists();
        if ($exists) {
            DB::table('recipe_boost_scores')->where('recipe_id', $v['recipe_id'])->increment($col);
        } else {
            DB::table('recipe_boost_scores')->insert([
                'recipe_id' => $v['recipe_id'],
                'recommend_clicks' => $v['signal'] === 'click' ? 1 : 0,
                'recommend_saves' => $v['signal'] === 'save' ? 1 : 0,
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        }

        Cache::add('recommend_cache_version', 1);
        Cache::increment('recommend_cache_version');
        if ($request->user()?->id) {
            WarmRecommendationCacheJob::dispatch((int) $request->user()->id)->onQueue('default');
        }

        return response()->json(['success' => true]);
    }

    /**
     * GET SINGLE RECIPE + success prediction (Sprint 8 Task 89).
     */
    public function show(Request $request, $id)
    {
        $recipe = Recipe::with(['ingredients', 'ratings'])->findOrFail($id);
        $authUserId = $request->user()?->id;

        $views = UserActivity::query()
            ->where('recipe_id', $recipe->id)
            ->where('action', 'view_recipe')
            ->count();

        $prediction = $this->buildSuccessPrediction($recipe, $views);
        $personalizedDifficulty = $this->personalizedDifficultyLabel($recipe, (int) (Auth::id() ?? 0));
        $userRating = null;
        if ($authUserId) {
            $userRating = $recipe->ratings()
                ->where('user_id', (int) $authUserId)
                ->value('rating');
        }

        return response()->json([
            'id' => $recipe->id,
            'name' => $recipe->name,
            'category' => $recipe->category,
            'difficulty' => $recipe->difficulty ?? 'medium',
            'cooking_time' => (int) ($recipe->cooking_time ?? 30),
            'instructions' => $recipe->instructions,
            'image_url' => $recipe->image_url,
            'ingredients' => $recipe->ingredients->pluck('name'),
            'average_rating' => round((float) ($recipe->ratings()->avg('rating') ?? 0), 1),
            'user_rating' => $userRating !== null ? (int) $userRating : null,
            'success_score' => $prediction['score'],
            'success_label' => $prediction['label'],
            'personalized_difficulty' => $personalizedDifficulty,
        ]);
    }

    /**
     * @return array{score: int, label: string}
     */
    protected function buildSuccessPrediction(Recipe $recipe, int $viewCount): array
    {
        $score = 72;
        $d = strtolower((string) ($recipe->difficulty ?? 'medium'));
        if ($d === 'easy') {
            $score += 18;
        } elseif ($d === 'hard') {
            $score -= 22;
        } else {
            $score -= 4;
        }

        $minutes = (int) ($recipe->cooking_time ?? 30);
        if ($minutes <= 20) {
            $score += 8;
        } elseif ($minutes >= 90) {
            $score -= 18;
        } elseif ($minutes >= 60) {
            $score -= 8;
        }

        if ($viewCount > 40) {
            $score += 7;
        } elseif ($viewCount > 10) {
            $score += 4;
        }

        $ingCount = $recipe->ingredients()->count();
        if ($ingCount <= 5) {
            $score += 6;
        } elseif ($ingCount >= 14) {
            $score -= 10;
        }

        $score = (int) max(5, min(99, round($score)));

        $label = 'Moderate';
        if ($score >= 78) {
            $label = 'Beginner Friendly';
        } elseif ($score < 52) {
            $label = 'Challenging';
        }

        return ['score' => $score, 'label' => $label];
    }

    protected function personalizedDifficultyLabel(Recipe $recipe, int $userId): string
    {
        $base = strtolower((string) ($recipe->difficulty ?? 'medium'));
        $mapped = $base === 'easy' ? 'Beginner' : ($base === 'hard' ? 'Advanced' : 'Intermediate');
        if ($userId <= 0) {
            return $mapped;
        }

        $cookActions = UserActivity::query()
            ->where('user_id', $userId)
            ->whereIn('action', ['favorite_recipe', 'view_recipe', 'cook_now_open'])
            ->count();

        if ($cookActions >= 120 && $base !== 'hard') {
            return 'Beginner';
        }
        if ($cookActions <= 15 && $base === 'hard') {
            return 'Intermediate';
        }

        return $mapped;
    }

    /**
     * CREATE RECIPE
     */
    public function store(Request $request)
    {
        try {
            $validated = $request->validate([
                'name' => 'required|string|max:255',
                'category' => 'nullable|string|max:255',
                'difficulty' => 'nullable|string|in:easy,medium,hard',
                'cooking_time' => 'nullable|integer|min:1|max:1440',
                'instructions' => 'required|string',
                'ingredient_ids' => 'nullable|array',
                'ingredient_ids.*' => 'integer|min:1',
                'ingredient_names' => 'nullable|array',
                'ingredient_names.*' => 'string|max:100',
                'image' => 'nullable|image|mimes:jpeg,png,jpg,webp|max:4096',
            ]);

            $normalized = mb_strtolower(trim((string) $validated['name']));
            $duplicate = Recipe::query()
                ->whereRaw('LOWER(TRIM(name)) = ?', [$normalized])
                ->exists();
            if ($duplicate) {
                return response()->json([
                    'message' => 'A recipe with this name already exists.',
                    'errors' => ['name' => ['Duplicate recipe name.']],
                ], 422);
            }

            $imagePath = 'default_recipe.png';

            if ($request->hasFile('image')) {
                $imagePath = $request->file('image')->store('recipes', 'public');
            }

            $recipe = Recipe::create([
                'name' => $validated['name'],
                'category' => $validated['category'] ?? 'Uncategorized',
                'difficulty' => $validated['difficulty'] ?? 'medium',
                'cooking_time' => $validated['cooking_time'] ?? 30,
                'instructions' => $validated['instructions'],
                'image' => $imagePath,
            ]);

            $resolvedIngredientIds = $this->resolveIngredientIds($validated);
            if (! empty($resolvedIngredientIds)) {
                $recipe->ingredients()->attach($resolvedIngredientIds);
            }

            $this->bumpRecipeRelatedCache();
            ProcessRecipeImageJob::dispatch((int) $recipe->id)->onQueue('default');
            WarmRecommendationCacheJob::dispatch($request->user()?->id ? (int) $request->user()->id : null)->onQueue('default');

            return response()->json([
                'message' => 'Recipe created successfully',
                'recipe' => $recipe->load('ingredients'),
            ], 201);
        } catch (\Illuminate\Validation\ValidationException $e) {
            return response()->json([
                'message' => 'Validation failed',
                'errors' => $e->errors(),
            ], 422);
        } catch (\Exception $e) {
            return response()->json([
                'message' => 'Failed to create recipe',
                'error' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * UPDATE RECIPE
     */
    public function update(Request $request, $id)
    {
        try {
            $recipe = Recipe::findOrFail($id);

            $validated = $request->validate([
                'name' => 'required|string|max:255',
                'category' => 'nullable|string|max:255',
                'difficulty' => 'nullable|string|in:easy,medium,hard',
                'cooking_time' => 'nullable|integer|min:1|max:1440',
                'instructions' => 'required|string',
                'ingredient_ids' => 'nullable|array',
                'ingredient_ids.*' => 'integer|min:1',
                'ingredient_names' => 'nullable|array',
                'ingredient_names.*' => 'string|max:100',
                'image' => 'nullable|image|mimes:jpeg,png,jpg,webp|max:4096',
            ]);

            $normalized = mb_strtolower(trim((string) $validated['name']));
            $duplicate = Recipe::query()
                ->where('id', '!=', $recipe->id)
                ->whereRaw('LOWER(TRIM(name)) = ?', [$normalized])
                ->exists();
            if ($duplicate) {
                return response()->json([
                    'message' => 'A recipe with this name already exists.',
                    'errors' => ['name' => ['Duplicate recipe name.']],
                ], 422);
            }

            $updateData = [
                'name' => $validated['name'],
                'category' => $validated['category'] ?? null,
                'instructions' => $validated['instructions'],
            ];
            if ($request->filled('difficulty')) {
                $updateData['difficulty'] = $validated['difficulty'];
            }
            if ($request->filled('cooking_time')) {
                $updateData['cooking_time'] = $validated['cooking_time'];
            }

            if ($request->hasFile('image')) {
                if ($recipe->image && $recipe->image !== 'default_recipe.png') {
                    Storage::disk('public')->delete($recipe->image);
                }

                $updateData['image'] = $request->file('image')->store('recipes', 'public');
            }

            $recipe->update($updateData);

            if (array_key_exists('ingredient_ids', $validated) || array_key_exists('ingredient_names', $validated)) {
                $resolvedIngredientIds = $this->resolveIngredientIds($validated);
                $recipe->ingredients()->sync($resolvedIngredientIds);
            }

            $this->bumpRecipeRelatedCache();
            if ($request->hasFile('image')) {
                ProcessRecipeImageJob::dispatch((int) $recipe->id)->onQueue('default');
            }
            WarmRecommendationCacheJob::dispatch($request->user()?->id ? (int) $request->user()->id : null)->onQueue('default');

            return response()->json([
                'message' => 'Recipe updated successfully',
                'recipe' => $recipe,
            ]);
        } catch (\Exception $e) {
            return response()->json([
                'message' => 'Failed to update recipe',
                'error' => $e->getMessage(),
            ], 500);
        }
    }

    /**
     * DELETE RECIPE
     */
    public function destroy($id)
    {
        $recipe = Recipe::findOrFail($id);

        $recipe->ingredients()->detach();
        $recipe->ratings()->delete();

        if ($recipe->image && $recipe->image !== 'default_recipe.png') {
            Storage::disk('public')->delete($recipe->image);
        }

        $recipe->delete();

        $this->bumpRecipeRelatedCache();

        return response()->json([
            'success' => true,
            'message' => 'Recipe deleted successfully',
        ]);
    }

    public function getRecentBatch(Request $request)
    {
        $ids = array_map('intval', $request->input('ids', []));

        if (empty($ids)) {
            return response()->json([]);
        }

        $fetched = Recipe::whereIn('id', $ids)->get()->keyBy('id');

        $ordered = collect($ids)
            ->map(fn (int $id) => $fetched->get($id))
            ->filter()
            ->values();

        $ordered->each->append('image_url');

        return response()->json($ordered);
    }

    public function uploadImage(Request $request, int $id)
    {
        $request->validate([
            'image' => 'required|image|mimes:jpeg,png,jpg,webp|max:4096',
        ]);

        $recipe = Recipe::query()->findOrFail($id);
        if ($recipe->image && $recipe->image !== 'default_recipe.png') {
            Storage::disk('public')->delete($recipe->image);
        }

        $recipe->image = $request->file('image')->store('recipes', 'public');
        $recipe->save();

        $this->bumpRecipeRelatedCache();
        ProcessRecipeImageJob::dispatch((int) $recipe->id)->onQueue('default');

        return response()->json([
            'success' => true,
            'image_url' => $recipe->image_url,
        ]);
    }

    protected function toFeedRecipe(Recipe $recipe): array
    {
        return [
            'id' => $recipe->id,
            'name' => $recipe->name,
            'category' => $recipe->category,
            'difficulty' => $recipe->difficulty ?? 'medium',
            'cooking_time' => (int) ($recipe->cooking_time ?? 30),
            'instructions' => $recipe->instructions,
            'image_url' => $recipe->image_url,
            'ingredients' => $recipe->ingredients->pluck('name'),
            'average_rating' => $recipe->average_rating !== null ? round((float) $recipe->average_rating, 1) : 0.0,
        ];
    }
}
