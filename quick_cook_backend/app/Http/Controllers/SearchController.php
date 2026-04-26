<?php

namespace App\Http\Controllers;

use App\Models\Ingredient;
use App\Models\Recipe;
use App\Models\SearchHistory;
use App\Models\UserActivity;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Cache;
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

        if (Auth::check()) {
            $history = SearchHistory::query()->firstOrNew([
                'user_id' => Auth::id(),
                'query' => mb_strtolower($query),
            ]);
            $history->hits = ((int) $history->hits) + 1;
            $history->last_searched_at = now();
            $history->save();
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

    public function suggestions(Request $request)
    {
        $q = trim((string) $request->query('query', ''));
        $like = $q === '' ? null : '%'.$q.'%';

        $trending = Cache::remember(
            'search_suggestions_trending_'.($q === '' ? 'all' : md5($q)),
            120,
            function () use ($like) {
                $rq = Recipe::query()->select('name')->whereNotNull('name');
                if ($like) {
                    $rq->where('name', 'LIKE', $like);
                }

                return $rq->orderBy('name')->limit(8)->pluck('name')->values()->all();
            }
        );

        $categories = Recipe::query()
            ->whereNotNull('category')
            ->when($like, fn ($qq) => $qq->where('category', 'LIKE', $like))
            ->select('category')
            ->distinct()
            ->limit(6)
            ->pluck('category')
            ->values()
            ->all();

        $recent = [];
        if (Auth::check()) {
            $recent = SearchHistory::query()
                ->where('user_id', Auth::id())
                ->when($like, fn ($qq) => $qq->where('query', 'LIKE', $like))
                ->orderByDesc('last_searched_at')
                ->limit(8)
                ->pluck('query')
                ->values()
                ->all();
        }

        return response()->json([
            'recent' => $recent,
            'suggested_keywords' => array_values(array_unique(array_merge($categories, $trending))),
        ]);
    }

    public function history()
    {
        $rows = SearchHistory::query()
            ->where('user_id', Auth::id())
            ->orderByDesc('last_searched_at')
            ->limit(25)
            ->get(['query', 'hits', 'last_searched_at']);

        return response()->json(['data' => $rows]);
    }

    public function clearHistory()
    {
        SearchHistory::query()->where('user_id', Auth::id())->delete();

        return response()->json(['success' => true]);
    }

    public function appVersion()
    {
        return response()->json([
            'latest_version' => env('APP_CLIENT_LATEST_VERSION', '1.0.0'),
            'minimum_supported_version' => env('APP_CLIENT_MIN_VERSION', '1.0.0'),
            'force_update' => filter_var(env('APP_CLIENT_FORCE_UPDATE', false), FILTER_VALIDATE_BOOL),
            'store_url' => env('APP_CLIENT_STORE_URL', ''),
            'message' => 'A new app version is available.',
        ]);
    }
}
