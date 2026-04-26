<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\IngredientController;
use App\Http\Controllers\RecipeController;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\FavoriteController;
use App\Http\Controllers\UserController;
use App\Http\Controllers\RatingController;
use App\Http\Controllers\ActivityController;
use App\Http\Controllers\AdminController;
use App\Http\Controllers\SearchController;
use App\Http\Controllers\CollectionController;

/*
|--------------------------------------------------------------------------
| PUBLIC ROUTES
|--------------------------------------------------------------------------
*/

Route::post('/register', [AuthController::class, 'register']);
Route::post('/login', [AuthController::class, 'login']);
Route::post('/forgot-password', [AuthController::class, 'forgotPassword']);
Route::post('/reset-password', [AuthController::class, 'resetPassword']);

Route::get('/ingredients', [IngredientController::class, 'index']);

Route::get('/recipes', [RecipeController::class, 'index']);
Route::post('/match-recipes', [RecipeController::class, 'match']);

Route::get('/ratings/{recipe}', [RatingController::class, 'average']);

Route::get('/search', [SearchController::class, 'search']);
Route::get('/search/suggestions', [SearchController::class, 'suggestions']);
Route::get('/app/version', [SearchController::class, 'appVersion']);

/*
|--------------------------------------------------------------------------
| AUTHENTICATED USERS
|--------------------------------------------------------------------------
*/

Route::middleware('auth:sanctum')->group(function () {

    Route::post('/logout', [AuthController::class, 'logout'])->middleware('throttle:20,1');

    Route::post('/rate', [RatingController::class, 'rate']);
    Route::get('/recipes/{id}', [RecipeController::class, 'show']);

    Route::post('/favorites', [FavoriteController::class, 'store'])->middleware('throttle:40,1');
    Route::get('/favorites', [FavoriteController::class, 'index']);
    Route::delete('/favorites/{id}', [FavoriteController::class, 'destroy'])->middleware('throttle:40,1');

    Route::post('/activity', [ActivityController::class, 'log'])->middleware('throttle:120,1');
    Route::get('/activities', [ActivityController::class, 'index']);

    Route::get('/recommended-recipes', [RecipeController::class, 'recommend']);
    Route::get('/home/feed', [RecipeController::class, 'homeFeed']);
    Route::post('/recommendation-feedback', [RecipeController::class, 'recommendationFeedback']);
    Route::post('/ingredients/substitutions', [RecipeController::class, 'ingredientSubstitutions']);
    Route::post('/ingredients/substitutions/feedback', [RecipeController::class, 'substitutionFeedback']);
    Route::post('/ingredients/combo-suggestions', [RecipeController::class, 'ingredientCombinationPredictor']);
    Route::post('/assistant/cook-help', [RecipeController::class, 'cookingAssistant']);
    Route::get('/user/cooking-insights', [RecipeController::class, 'personalizedInsights']);
    Route::get('/notifications/smart', [RecipeController::class, 'smartNotifications']);
    Route::post('/cook-now', [RecipeController::class, 'cookNow']);
    Route::get('/search/history', [SearchController::class, 'history']);
    Route::delete('/search/history', [SearchController::class, 'clearHistory']);

    Route::get('/user/profile', [UserController::class, 'profile']);
    Route::put('/user/profile', [UserController::class, 'updateProfile']);

    Route::get('/collections', [CollectionController::class, 'index']);
    Route::post('/collections', [CollectionController::class, 'store'])->middleware('throttle:30,1');
    Route::post('/collections/add', [CollectionController::class, 'addRecipe'])->middleware('throttle:60,1');
    Route::get('/collections/{id}', [CollectionController::class, 'show']);

    Route::post('/recipes/recent', [RecipeController::class, 'getRecentBatch']);

    Route::post('/metrics', [AdminController::class, 'storePerformanceMetric']);
});

/*
|--------------------------------------------------------------------------
| ADMINISTRATORS ONLY
|--------------------------------------------------------------------------
*/

Route::middleware(['auth:sanctum', 'admin'])->group(function () {

    Route::post('/recipes', [RecipeController::class, 'store']);
    Route::put('/recipes/{id}', [RecipeController::class, 'update']);
    Route::delete('/recipes/{id}', [RecipeController::class, 'destroy']);
    Route::post('/recipes/{id}/upload-image', [RecipeController::class, 'uploadImage']);
    Route::post('/admin/recipes/auto-tag', [RecipeController::class, 'autoTagRecipe']);

    Route::get('/users', [UserController::class, 'index']);
    Route::post('/users', [UserController::class, 'store']);
    Route::put('/users/{id}', [UserController::class, 'update']);
    Route::delete('/users/{id}', [UserController::class, 'destroy']);

    Route::post('/ingredients', [IngredientController::class, 'store']);

    Route::get('/admin/stats', [AdminController::class, 'stats']);
    Route::get('/admin/popular', [AdminController::class, 'popularRecipes']);
    Route::get('/admin/activity-stats', [AdminController::class, 'activityStats']);
    Route::get('/admin/ingredient-usage', [AdminController::class, 'ingredientUsage']);
    Route::get('/admin/api-usage', [AdminController::class, 'apiUsage']);
    Route::get('/admin/error-logs', [AdminController::class, 'errorLogs']);
    Route::get('/admin/ping', [AdminController::class, 'pingSystem']);
    Route::get('/admin/activity-logs', [AdminController::class, 'getActivityLogs']);
    Route::get('/admin/performance-metrics', [AdminController::class, 'performanceMetrics']);
    Route::get('/admin/recipe-data-quality', [AdminController::class, 'recipeDataQuality']);
    Route::get('/admin/performance-bottlenecks', [AdminController::class, 'performanceBottlenecks']);
    Route::get('/admin/top-searched-recipes', [AdminController::class, 'topSearchedRecipes']);
    Route::get('/admin/user-activity-trends', [AdminController::class, 'userActivityTrends']);
});
