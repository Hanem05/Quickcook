<?php

namespace App\Http\Controllers;

use App\Models\Recipe;
use App\Models\User;
use App\Models\Ingredient;
use App\Models\UserActivity;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Cache; // ✅ ADDED

class AdminController extends Controller
{
    /**
     * TASK 31: Admin Analytics API
     */
    public function stats()
    {
        try {
            $version = (int) Cache::get('recipes_cache_version', 1);
            $data = Cache::remember('admin_stats:v'.$version, 300, function () {
                $totalUsers = User::count();
                $totalRecipes = Recipe::count();
                $categoryStats = Recipe::select('category', DB::raw('count(*) as count'))
                    ->groupBy('category')
                    ->get();

                return [
                    'total_users' => $totalUsers,
                    'total_recipes' => $totalRecipes,
                    'category_distribution' => $categoryStats,
                ];
            });

            return response()->json([
                'success' => true,
                'data' => $data,
            ], 200);
        } catch (\Exception $e) {
            return response()->json(['success' => false, 'error' => $e->getMessage()], 500);
        }
    }

    /**
     * TASK 32: Popular Recipes API
     */
    public function popularRecipes()
    {
        try {
            $version = (int) Cache::get('trending_cache_version', 1);
            $popular = Cache::remember('popular_recipes:v'.$version, 300, function () {
                return UserActivity::select('recipe_id', DB::raw('count(*) as views'))
                    ->where('action', 'view_recipe')
                    ->groupBy('recipe_id')
                    ->with(['recipe:id,name,category,image'])
                    ->orderBy('views', 'desc')
                    ->limit(5)
                    ->get();
            });

            return response()->json([
                'success' => true,
                'data' => $popular
            ], 200);
        } catch (\Exception $e) {
            return response()->json(['success' => false, 'error' => $e->getMessage()], 500);
        }
    }

    /**
     * TASK 33: User Activity Statistics
     */
    public function activityStats()
    {
        try {
            $stats = Cache::remember('activity_stats', 300, function () {
                return [
                    'views' => UserActivity::where('action', 'view_recipe')->count(),
                    'searches' => UserActivity::where('action', 'search_recipe')->count(),
                    'favorites' => UserActivity::where('action', 'favorite_recipe')->count(),
                ];
            });

            return response()->json([
                'success' => true,
                'data' => $stats
            ], 200);
        } catch (\Exception $e) {
            return response()->json(['success' => false, 'error' => $e->getMessage()], 500);
        }
    }

    /**
     * TASK 34: Ingredient Usage Tracking
     */
    public function ingredientUsage(Request $request)
    {
        try {
            $query = UserActivity::select('ingredient_id', DB::raw('count(*) as count'))
                ->where('action', 'select_ingredient');

            // ✅ FILTER BY DATE
            if ($request->has('date') && !empty($request->date)) {
                $query->whereDate('created_at', date('Y-m-d', strtotime($request->date)));
            }

            // ✅ FILTER BY MONTH
            if ($request->has('month') && !empty($request->month)) {
                $month = date('m', strtotime($request->month));
                $year = date('Y', strtotime($request->month));

                $query->whereMonth('created_at', $month)
                    ->whereYear('created_at', $year);
            }

            $usage = $query
                ->groupBy('ingredient_id')
                ->with('ingredient:id,name')
                ->orderBy('count', 'desc')
                ->limit(5)
                ->get();

            return response()->json([
                'success' => true,
                'data' => $usage
            ], 200);
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'error' => $e->getMessage()
            ], 500);
        }
    }

    // -----------------------------
    // BELOW = UNCHANGED
    // -----------------------------

    public function index()
    {
        $recipes = Recipe::withAvg('ratings as avg_rating', 'rating')->get();
        return view('admin.dashboard', compact('recipes'));
    }

    public function create()
    {
        $ingredients = Ingredient::all();
        return view('admin.create', compact('ingredients'));
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'category' => 'required|string',
            'instructions' => 'required|string',
            'ingredient_ids' => 'required|array',
        ]);

        $recipe = Recipe::create($validated);
        $recipe->ingredients()->attach($request->ingredient_ids);

        return redirect()->route('admin.dashboard')->with('success', 'Recipe created!');
    }

    public function apiUsageStats()
    {
        $stats = \DB::table('api_logs')
            ->select(
                'endpoint',
                \DB::raw('count(*) as hits'),
                \DB::raw('avg(latency_ms) as latency_ms')
            )
            ->groupBy('endpoint')
            ->get();

        return response()->json(['success' => true, 'data' => $stats]);
    }

    public function errorLogs(Request $request)
    {
        $query = \DB::table('system_errors')->orderBy('created_at', 'desc');

        if ($request->filled('severity')) {
            $query->where('severity', $request->string('severity'));
        }

        if ($request->filled('error_type')) {
            $query->where('error_type', 'like', '%' . $request->string('error_type') . '%');
        }

        if ($request->filled('start_date')) {
            $query->whereDate('created_at', '>=', $request->string('start_date'));
        }

        if ($request->filled('end_date')) {
            $query->whereDate('created_at', '<=', $request->string('end_date'));
        }

        $perPage = min((int) $request->get('per_page', 50), 200);

        $errors = $query->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $errors->items(),
            'meta' => [
                'current_page' => $errors->currentPage(),
                'last_page' => $errors->lastPage(),
                'per_page' => $errors->perPage(),
                'total' => $errors->total(),
            ],
        ]);
    }

    public function storePerformanceMetric(Request $request)
    {
        $validated = $request->validate([
            'kind' => 'required|string|max:32',
            'name' => 'required|string|max:255',
            'duration_ms' => 'required|integer|min:0|max:600000',
            'meta' => 'nullable|array',
        ]);

        \DB::table('performance_metrics')->insert([
            'user_id' => $request->user()?->id,
            'kind' => $validated['kind'],
            'name' => $validated['name'],
            'duration_ms' => $validated['duration_ms'],
            'meta' => isset($validated['meta']) ? json_encode($validated['meta']) : null,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        return response()->json(['success' => true]);
    }

    public function performanceMetrics(Request $request)
    {
        $query = \DB::table('performance_metrics')
            ->leftJoin('users', 'users.id', '=', 'performance_metrics.user_id')
            ->select(
                'performance_metrics.*',
                'users.name as user_name',
                'users.email as user_email'
            )
            ->orderBy('performance_metrics.created_at', 'desc');

        if ($request->filled('kind')) {
            $query->where('performance_metrics.kind', $request->string('kind'));
        }

        if ($request->filled('start_date')) {
            $query->whereDate('performance_metrics.created_at', '>=', $request->string('start_date'));
        }

        if ($request->filled('end_date')) {
            $query->whereDate('performance_metrics.created_at', '<=', $request->string('end_date'));
        }

        $perPage = min((int) $request->get('per_page', 50), 200);
        $rows = $query->paginate($perPage);

        return response()->json([
            'success' => true,
            'data' => $rows->items(),
            'meta' => [
                'current_page' => $rows->currentPage(),
                'last_page' => $rows->lastPage(),
                'per_page' => $rows->perPage(),
                'total' => $rows->total(),
            ],
        ]);
    }

    public function pingSystem()
    {
        return response()->json([
            'success' => true,
            'message' => 'Backend is officially connected and working!'
        ]);
    }

    public function getActivityLogs(Request $request)
    {
        $perPage = $request->get('per_page', 10); // Changed default to 10 for your pagination

        // 1. Start building the query
        $query = \App\Models\UserActivity::with([
            'user:id,name',
            'recipe:id,name',
            'ingredient:id,name'
        ])->orderBy('created_at', 'desc');

        // 2. 🌿 THIS IS THE NEW PART: Check if Flutter sent a specific date
        if ($request->has('date') && !empty($request->date)) {
            $query->whereDate('created_at', date('Y-m-d', strtotime($request->date)));
        }

        if ($request->has('month') && !empty($request->month)) {
            $month = date('m', strtotime($request->month));
            $year = date('Y', strtotime($request->month));

            $query->whereMonth('created_at', $month)
                ->whereYear('created_at', $year);
        }

        // 3. Execute the query with pagination
        $logs = $query->paginate($perPage);

        // 4. Transform the data for Flutter
        $logs->getCollection()->transform(function ($log) {
            return [
                'user_name' => $log->user->name ?? 'User',
                'action' => $log->action,
                'recipe_name' => $log->recipe->name ?? null,
                'ingredient_name' => $log->ingredient->name ?? null,
                'created_at' => $log->created_at,
            ];
        });

        return response()->json([
            'success' => true,
            'data' => $logs
        ]);
    }

    public function exportActivities()
    {
        return response()->streamDownload(function () {

            $handle = fopen('php://output', 'w');

            fputcsv($handle, [
                'User',
                'Action',
                'Recipe',
                'Ingredient',
                'Date'
            ]);

            \App\Models\UserActivity::with(['user', 'recipe', 'ingredient'])
                ->orderBy('created_at', 'desc')
                ->chunk(1000, function ($activities) use ($handle) {

                    foreach ($activities as $log) {
                        fputcsv($handle, [
                            $log->user->name ?? 'User',
                            $log->action,
                            $log->recipe->name ?? '',
                            $log->ingredient->name ?? '',
                            $log->created_at
                        ]);
                    }
                });

            fclose($handle);
        }, 'activity_logs.csv');
    }

    public function apiUsage(Request $request)
    {
        $perPage = min((int) $request->get('per_page', 10), 100);
        $rows = \DB::table('api_logs')
            ->select(
                'endpoint',
                \DB::raw('COUNT(*) as hits'),
                \DB::raw('AVG(latency_ms) as avg_latency')
            )
            ->groupBy('endpoint')
            ->orderByDesc('hits')
            ->paginate($perPage);

        return response()->json([
            'data' => $rows->items(),
            'meta' => [
                'current_page' => $rows->currentPage(),
                'last_page' => $rows->lastPage(),
                'per_page' => $rows->perPage(),
                'total' => $rows->total(),
            ],
        ]);
    }

    /**
     * Sprint 8 Task 85 — duplicate names, missing ingredients, thin instructions.
     */
    public function recipeDataQuality()
    {
        $duplicateNames = Recipe::query()
            ->select('name', DB::raw('COUNT(*) as count'))
            ->groupBy('name')
            ->havingRaw('COUNT(*) > 1')
            ->orderByDesc('count')
            ->get();

        $withoutIngredients = Recipe::query()
            ->doesntHave('ingredients')
            ->get(['id', 'name', 'category']);

        $shortInstructions = Recipe::query()
            ->whereRaw('CHAR_LENGTH(TRIM(instructions)) < 15')
            ->get(['id', 'name']);

        return response()->json([
            'success' => true,
            'duplicate_names' => $duplicateNames,
            'recipes_without_ingredients' => $withoutIngredients,
            'very_short_instructions' => $shortInstructions,
        ]);
    }

    /**
     * Sprint 8 Task 87 — aggregate slow client-reported calls (uses existing performance_metrics).
     */
    public function performanceBottlenecks(Request $request)
    {
        $threshold = min(600000, max(100, (int) $request->get('threshold_ms', 1500)));

        $rows = DB::table('performance_metrics')
            ->select(
                'kind',
                'name',
                DB::raw('AVG(duration_ms) as avg_ms'),
                DB::raw('MAX(duration_ms) as max_ms'),
                DB::raw('COUNT(*) as samples')
            )
            ->where('duration_ms', '>=', $threshold)
            ->groupBy('kind', 'name')
            ->orderByDesc('avg_ms')
            ->limit(40)
            ->get();

        return response()->json([
            'success' => true,
            'threshold_ms' => $threshold,
            'data' => $rows,
        ]);
    }

    public function topSearchedRecipes()
    {
        $rows = UserActivity::query()
            ->with('recipe:id,name,category,image')
            ->where('action', 'search_recipe')
            ->whereNotNull('recipe_id')
            ->selectRaw('recipe_id, COUNT(*) as searches')
            ->groupBy('recipe_id')
            ->orderByDesc('searches')
            ->limit(10)
            ->get();

        return response()->json([
            'success' => true,
            'data' => $rows,
        ]);
    }

    public function userActivityTrends(Request $request)
    {
        $days = min(90, max(7, (int) $request->get('days', 14)));
        $start = now()->subDays($days - 1)->startOfDay();

        $rows = UserActivity::query()
            ->where('created_at', '>=', $start)
            ->selectRaw('DATE(created_at) as date, action, COUNT(*) as total')
            ->groupByRaw('DATE(created_at), action')
            ->orderBy('date')
            ->get();

        return response()->json([
            'success' => true,
            'days' => $days,
            'data' => $rows,
        ]);
    }
}
