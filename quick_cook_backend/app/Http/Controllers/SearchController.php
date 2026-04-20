<?php

namespace App\Http\Controllers;

use App\Models\Ingredient;
use App\Models\Recipe;
use App\Models\UserActivity;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class SearchController extends Controller
{
    /**
     * Sprint 8 Task 81 — ranked search: relevance + popularity + ratings.
     */
    public function search(Request $request)
    {
        $query = trim((string) $request->input('query', ''));

        if ($query === '') {
            return response()->json([
                'recipes' => [],
                'ingredients' => [],
                'categories' => [],
            ]);
        }

        $like = '%'.$query.'%';

        $recipeRows = Recipe::query()
            ->withAvg('ratings as avg_rating', 'rating')
            ->withCount('favorites')
            ->where(function ($q) use ($like) {
                $q->where('name', 'LIKE', $like)
                    ->orWhere('instructions', 'LIKE', $like)
                    ->orWhere('category', 'LIKE', $like);
            })
            ->limit(40)
            ->get();

        $ids = $recipeRows->pluck('id')->filter()->values()->all();

        $viewCounts = $ids === []
            ? collect()
            : UserActivity::query()
                ->where('action', 'view_recipe')
                ->whereIn('recipe_id', $ids)
                ->selectRaw('recipe_id, COUNT(*) as vc')
                ->groupBy('recipe_id')
                ->pluck('vc', 'recipe_id');

        $scored = $recipeRows->map(function ($r) use ($query, $viewCounts) {
            $name = (string) $r->name;
            $instr = (string) $r->instructions;
            $cat = (string) ($r->category ?? '');

            $rel = 0;
            if (strcasecmp($name, $query) === 0) {
                $rel += 100;
            } elseif (stripos($name, $query) !== false) {
                $rel += 55;
                if (str_starts_with(mb_strtolower($name), mb_strtolower($query))) {
                    $rel += 30;
                }
            } elseif (stripos($instr, $query) !== false) {
                $rel += 22;
            } elseif (stripos($cat, $query) !== false) {
                $rel += 14;
            }

            $avg = (float) ($r->avg_rating ?? 0);
            $views = (int) ($viewCounts->get($r->id, 0));
            $fav = (int) ($r->favorites_count ?? 0);

            $popNorm = min(35, ($views / 40) * 18 + ($fav / 15) * 17);
            $rateNorm = min(28, $avg * 5.5);

            $searchScore = $rel + $popNorm + $rateNorm;

            $out = $r->toArray();
            $out['average_rating'] = round($avg, 1);
            $out['search_rank_score'] = round($searchScore, 2);

            return $out;
        })->sortByDesc('search_rank_score')->values()->take(12);

        $ingredients = Ingredient::query()
            ->where('name', 'LIKE', $like)
            ->limit(12)
            ->get();

        $categories = Recipe::query()
            ->where('category', 'LIKE', $like)
            ->whereNotNull('category')
            ->select('category')
            ->distinct()
            ->limit(12)
            ->pluck('category');

        return response()->json([
            'recipes' => $scored,
            'ingredients' => $ingredients,
            'categories' => $categories,
        ]);
    }
}
