<?php

namespace App\Http\Controllers;

use App\Models\Ingredient;
use App\Models\Recipe;
use App\Models\UserActivity;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

class RecipeController extends Controller
{
    /**
     * GET ALL RECIPES (Admin Panel)
     */
    public function index()
    {
        $recipes = Cache::remember('recipes_all', 300, function () {
            return Recipe::with('ingredients')
                ->withAvg('ratings as average_rating', 'rating')
                ->get();
        });

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

        if ($request->filled('category')) {
            $cat = $request->string('category');
            $allowedIds = Recipe::query()->where('category', $cat)->pluck('id')->map(static fn ($id): int => (int) $id)->all();
            $allowedFlip = array_fill_keys($allowedIds, true);
            $rankedRows = array_values(array_filter($rankedRows, static function ($row) use ($allowedFlip) {
                return isset($allowedFlip[(int) $row->recipe_id]);
            }));
        }

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
                'image_url' => $recipe->image ? url('storage/'.$recipe->image) : null,
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

        $sql = <<<'SQL'
SELECT recipes.id AS recipe_id,
  (
    COALESCE(rbs.recommend_clicks, 0) * 3
    + COALESCE(rbs.recommend_saves, 0) * 5
    + (SELECT COUNT(*) FROM favorites f WHERE f.recipe_id = recipes.id) * 2
    + COALESCE((SELECT AVG(rating) FROM ratings r WHERE r.recipe_id = recipes.id), 0) * 8
  ) AS rank_score
FROM recipes
LEFT JOIN recipe_boost_scores rbs ON rbs.recipe_id = recipes.id
ORDER BY rank_score DESC, recipes.id DESC
LIMIT ?
SQL;

        $rows = DB::select($sql, [$limit]);
        $ids = collect($rows)->pluck('recipe_id')->map(static fn ($id): int => (int) $id)->values()->all();

        if ($ids === []) {
            return response()->json([]);
        }

        $recipes = Recipe::query()
            ->with(['ingredients:id,name'])
            ->withAvg('ratings as average_rating', 'rating')
            ->whereIn('id', $ids)
            ->get()
            ->sortBy(static fn ($r) => array_search($r->id, $ids, true))
            ->values();

        return response()->json($recipes->map(function (Recipe $recipe) {
            $avg = $recipe->average_rating;

            return [
                'id' => $recipe->id,
                'name' => $recipe->name,
                'category' => $recipe->category,
                'difficulty' => $recipe->difficulty ?? 'medium',
                'cooking_time' => (int) ($recipe->cooking_time ?? 30),
                'instructions' => $recipe->instructions,
                'image_url' => $recipe->image ? url('storage/'.$recipe->image) : null,
                'image' => $recipe->image ? url('storage/'.$recipe->image) : null,
                'ingredients' => $recipe->ingredients->pluck('name'),
                'average_rating' => $avg !== null ? round((float) $avg, 1) : 0,
            ];
        }));
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

        return response()->json(['success' => true]);
    }

    /**
     * GET SINGLE RECIPE + success prediction (Sprint 8 Task 89).
     */
    public function show($id)
    {
        $recipe = Recipe::with(['ingredients', 'ratings'])->findOrFail($id);

        $views = UserActivity::query()
            ->where('recipe_id', $recipe->id)
            ->where('action', 'view_recipe')
            ->count();

        $prediction = $this->buildSuccessPrediction($recipe, $views);

        return response()->json([
            'id' => $recipe->id,
            'name' => $recipe->name,
            'category' => $recipe->category,
            'difficulty' => $recipe->difficulty ?? 'medium',
            'cooking_time' => (int) ($recipe->cooking_time ?? 30),
            'instructions' => $recipe->instructions,
            'image_url' => $recipe->image ? url('storage/'.$recipe->image) : null,
            'ingredients' => $recipe->ingredients->pluck('name'),
            'average_rating' => round((float) ($recipe->ratings()->avg('rating') ?? 0), 1),
            'success_score' => $prediction['score'],
            'success_label' => $prediction['label'],
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
                'image' => 'nullable|image|mimes:jpeg,png,jpg,webp|max:4096',
            ]);

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

            if (! empty($validated['ingredient_ids'])) {
                $recipe->ingredients()->attach($validated['ingredient_ids']);
            }

            Cache::forget('recipes_all');

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
                'image' => 'nullable|image|mimes:jpeg,png,jpg,webp|max:4096',
            ]);

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

            if (isset($validated['ingredient_ids'])) {
                $recipe->ingredients()->sync($validated['ingredient_ids']);
            }

            Cache::forget('recipes_all');

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

        Cache::forget('recipes_all');

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
}
