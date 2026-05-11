<?php

namespace Tests\Feature;

use App\Models\Collection;
use App\Models\Favorite;
use App\Models\Ingredient;
use App\Models\Recipe;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

class ApiEndpointCoverageTest extends TestCase
{
    use RefreshDatabase;

    private User $user;
    private User $admin;
    private Recipe $recipe;
    private Ingredient $ingredient;
    private Collection $collection;
    private Favorite $favorite;

    protected function setUp(): void
    {
        parent::setUp();

        $this->ingredient = Ingredient::create(['name' => 'Garlic']);
        $this->recipe = Recipe::create([
            'name' => 'Coverage Recipe',
            'instructions' => 'Step 1 cook.',
            'category' => 'Lunch',
            'difficulty' => 'easy',
            'cooking_time' => 20,
            'image' => null,
        ]);
        $this->recipe->ingredients()->sync([$this->ingredient->id]);

        $this->user = User::create([
            'name' => 'Coverage User',
            'email' => 'coverage-user@example.com',
            'password' => Hash::make('password123'),
            'role' => 'user',
        ]);

        $this->admin = User::create([
            'name' => 'Coverage Admin',
            'email' => 'coverage-admin@example.com',
            'password' => Hash::make('password123'),
            'role' => 'admin',
        ]);

        $this->collection = Collection::create([
            'user_id' => $this->user->id,
            'name' => 'Coverage Collection',
        ]);
        $this->favorite = Favorite::create([
            'user_id' => $this->user->id,
            'recipe_id' => $this->recipe->id,
        ]);
    }

    public static function endpointMatrix(): array
    {
        return [
            // Public
            ['POST', '/api/register', 'public', ['name' => 'Reg User', 'email' => 'reg-user@example.com', 'password' => 'password123']],
            ['POST', '/api/login', 'public', ['email' => 'coverage-user@example.com', 'password' => 'password123']],
            ['POST', '/api/forgot-password', 'public', ['email' => 'coverage-user@example.com']],
            ['POST', '/api/reset-password', 'public', ['token' => 'invalid-token', 'email' => 'coverage-user@example.com', 'password' => 'password123', 'password_confirmation' => 'password123']],
            ['GET', '/api/ingredients', 'public', []],
            ['GET', '/api/recipes', 'public', ['per_page' => '10', 'page' => '1']],
            ['POST', '/api/match-recipes', 'public', ['ingredient_ids' => [1]]],
            ['GET', '/api/ratings/{recipe}', 'public', []],
            ['GET', '/api/search', 'public', ['q' => 'coverage']],
            ['GET', '/api/search/suggestions', 'public', ['q' => 'gar']],
            ['GET', '/api/app/version', 'public', []],

            // Auth
            ['POST', '/api/logout', 'auth', []],
            ['POST', '/api/rate', 'auth', ['recipe_id' => 1, 'rating' => 4]],
            ['GET', '/api/recipes/{id}', 'auth', []],
            ['POST', '/api/favorites', 'auth', ['recipe_id' => 1]],
            ['GET', '/api/favorites', 'auth', []],
            ['DELETE', '/api/favorites/{id}', 'auth', []],
            ['POST', '/api/activity', 'auth', ['action' => 'view_recipe', 'recipe_id' => 1]],
            ['GET', '/api/activities', 'auth', []],
            ['GET', '/api/recommended-recipes', 'auth', []],
            ['GET', '/api/home/feed', 'auth', []],
            ['POST', '/api/recommendation-feedback', 'auth', ['recipe_id' => 1, 'feedback' => 'click']],
            ['POST', '/api/ingredients/substitutions', 'auth', ['ingredients' => ['milk']]],
            ['POST', '/api/ingredients/substitutions/feedback', 'auth', ['ingredient' => 'milk', 'alternative' => 'water', 'score' => 1]],
            ['POST', '/api/ingredients/combo-suggestions', 'auth', ['ingredient_ids' => [1], 'limit' => 3]],
            ['POST', '/api/assistant/cook-help', 'auth', ['message' => 'what can i cook?', 'ingredient_ids' => [1]]],
            ['GET', '/api/user/cooking-insights', 'auth', []],
            ['GET', '/api/notifications/smart', 'auth', []],
            ['POST', '/api/cook-now', 'auth', ['ingredient_ids' => [1], 'limit' => 5]],
            ['GET', '/api/search/history', 'auth', []],
            ['DELETE', '/api/search/history', 'auth', []],
            ['GET', '/api/user/profile', 'auth', []],
            ['PUT', '/api/user/profile', 'auth', ['name' => 'Coverage User Updated', 'email' => 'coverage-user@example.com']],
            ['GET', '/api/collections', 'auth', []],
            ['POST', '/api/collections', 'auth', ['name' => 'New Collection']],
            ['POST', '/api/collections/add', 'auth', ['collection_id' => 1, 'recipe_id' => 1]],
            ['GET', '/api/collections/{id}', 'auth', []],
            ['POST', '/api/recipes/recent', 'auth', ['recipe_ids' => [1]]],
            ['POST', '/api/metrics', 'auth', ['endpoint' => 'GET /recipes', 'duration_ms' => 120, 'status' => 200]],

            // Admin
            ['POST', '/api/recipes', 'admin', ['name' => 'New Admin Recipe', 'instructions' => 'Cook well.', 'ingredient_ids' => [1]]],
            ['PUT', '/api/recipes/{id}', 'admin', ['name' => 'Updated Admin Recipe', 'instructions' => 'Updated.', 'ingredient_ids' => [1]]],
            ['DELETE', '/api/recipes/{id}', 'admin', []],
            ['POST', '/api/recipes/{id}/upload-image', 'admin', []],
            ['POST', '/api/admin/recipes/auto-tag', 'admin', ['name' => 'Auto Tag Recipe', 'instructions' => 'Step 1.']],
            ['GET', '/api/users', 'admin', ['page' => '1', 'per_page' => '20']],
            ['POST', '/api/users', 'admin', ['name' => 'Admin Created User', 'email' => 'admin-created@example.com', 'password' => 'password123', 'role' => 'user']],
            ['PUT', '/api/users/{id}', 'admin', ['name' => 'Updated User', 'email' => 'coverage-user@example.com']],
            ['DELETE', '/api/users/{id}', 'admin', []],
            ['POST', '/api/ingredients', 'admin', ['name' => 'Coverage New Ingredient']],
            ['GET', '/api/admin/stats', 'admin', []],
            ['GET', '/api/admin/popular', 'admin', []],
            ['GET', '/api/admin/activity-stats', 'admin', []],
            ['GET', '/api/admin/ingredient-usage', 'admin', []],
            ['GET', '/api/admin/api-usage', 'admin', []],
            ['GET', '/api/admin/error-logs', 'admin', []],
            ['GET', '/api/admin/ping', 'admin', []],
            ['GET', '/api/admin/activity-logs', 'admin', []],
            ['GET', '/api/admin/performance-metrics', 'admin', []],
            ['GET', '/api/admin/recipe-data-quality', 'admin', []],
            ['GET', '/api/admin/performance-bottlenecks', 'admin', []],
            ['GET', '/api/admin/top-searched-recipes', 'admin', []],
            ['GET', '/api/admin/user-activity-trends', 'admin', []],
        ];
    }

    #[DataProvider('endpointMatrix')]
    public function test_each_endpoint_has_expected_auth_contract(
        string $method,
        string $uri,
        string $scope,
        array $payload
    ): void {
        $resolved = $this->resolveUri($uri);
        $response = $this->callEndpoint($method, $resolved, $payload);

        if ($scope === 'public') {
            $this->assertNotContains($response->getStatusCode(), [401, 403], $method.' '.$uri.' should be public.');
            return;
        }

        $this->assertSame(401, $response->getStatusCode(), $method.' '.$uri.' should require auth.');
    }

    #[DataProvider('endpointMatrix')]
    public function test_each_endpoint_is_reachable_with_valid_context(
        string $method,
        string $uri,
        string $scope,
        array $payload
    ): void {
        if ($scope === 'auth') {
            Sanctum::actingAs($this->user);
        } elseif ($scope === 'admin') {
            Sanctum::actingAs($this->admin);
        }

        $resolved = $this->resolveUri($uri);
        $response = $this->callEndpoint($method, $resolved, $payload);
        $status = $response->getStatusCode();

        $this->assertNotSame(404, $status, $method.' '.$uri.' unexpectedly returned 404.');
        if (! $this->allowsServerErrorForReachability($uri)) {
            $this->assertLessThan(500, $status, $method.' '.$uri.' should not crash (5xx).');
        }
    }

    private function resolveUri(string $uri): string
    {
        return str_replace(
            ['{recipe}', '{id}'],
            [(string) $this->recipe->id, (string) $this->idForGenericPlaceholder($uri)],
            $uri
        );
    }

    private function idForGenericPlaceholder(string $uri): int
    {
        if (str_contains($uri, '/collections/{id}')) {
            return $this->collection->id;
        }
        if (str_contains($uri, '/users/{id}')) {
            return $this->user->id;
        }
        if (str_contains($uri, '/favorites/{id}')) {
            return $this->favorite->id;
        }
        return $this->recipe->id;
    }

    private function allowsServerErrorForReachability(string $uri): bool
    {
        return in_array($uri, [
            '/api/forgot-password',
            '/api/admin/recipe-data-quality',
        ], true);
    }

    private function callEndpoint(string $method, string $uri, array $payload)
    {
        return match (strtoupper($method)) {
            'GET' => $this->getJson($uri.(empty($payload) ? '' : '?'.http_build_query($payload))),
            'POST' => $this->postJson($uri, $payload),
            'PUT' => $this->putJson($uri, $payload),
            'DELETE' => $this->deleteJson($uri, $payload),
            default => throw new \InvalidArgumentException("Unsupported method: {$method}"),
        };
    }
}

