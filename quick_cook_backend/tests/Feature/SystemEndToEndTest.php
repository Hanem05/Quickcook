<?php

namespace Tests\Feature;

use App\Models\Ingredient;
use App\Models\Recipe;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class SystemEndToEndTest extends TestCase
{
    use RefreshDatabase;

    private function createUser(array $overrides = []): User
    {
        return User::create(array_merge([
            'name' => 'Regular User',
            'email' => 'user@example.com',
            'password' => Hash::make('password123'),
            'role' => 'user',
        ], $overrides));
    }

    private function createAdmin(array $overrides = []): User
    {
        return User::create(array_merge([
            'name' => 'Admin User',
            'email' => 'admin@example.com',
            'password' => Hash::make('password123'),
            'role' => 'admin',
        ], $overrides));
    }

    private function createRecipe(string $name = 'Chicken Adobo', array $ingredientNames = ['Chicken', 'Soy Sauce']): Recipe
    {
        $recipe = Recipe::create([
            'name' => $name,
            'category' => 'Dinner',
            'difficulty' => 'medium',
            'cooking_time' => 35,
            'instructions' => 'Cook and season well.',
            'image' => 'default_recipe.png',
        ]);

        foreach ($ingredientNames as $ingredientName) {
            $ingredient = Ingredient::firstOrCreate(['name' => $ingredientName]);
            $recipe->ingredients()->attach($ingredient->id);
        }

        return $recipe->fresh(['ingredients']);
    }

    public function test_public_endpoints_return_data(): void
    {
        $this->createRecipe();

        $this->getJson('/api/ingredients')->assertOk();
        $this->getJson('/api/recipes')
            ->assertOk()
            ->assertHeader('X-Request-ID')
            ->assertJsonStructure(['data']);
        $this->getJson('/api/search')->assertOk();
    }

    public function test_register_and_login_endpoints_work(): void
    {
        $this->postJson('/api/register', [
            'name' => 'Jane User',
            'email' => 'jane@example.com',
            'password' => 'password123',
        ])->assertOk()->assertJsonStructure(['user', 'token']);

        $this->postJson('/api/login', [
            'email' => 'jane@example.com',
            'password' => 'password123',
        ])->assertOk()->assertJsonStructure(['user', 'token', 'role']);
    }

    public function test_login_fails_with_wrong_password(): void
    {
        $this->createUser(['email' => 'jane@example.com']);

        $this->postJson('/api/login', [
            'email' => 'jane@example.com',
            'password' => 'wrong-password',
        ])->assertStatus(401)->assertJson(['message' => 'Invalid credentials']);
    }

    public function test_protected_user_endpoints_require_authentication(): void
    {
        $this->getJson('/api/favorites')->assertStatus(401);
        $this->getJson('/api/user/profile')->assertStatus(401);
        $this->postJson('/api/assistant/cook-help', ['message' => 'hello'])->assertStatus(401);
    }

    public function test_user_can_read_and_update_profile(): void
    {
        $user = $this->createUser();
        Sanctum::actingAs($user);

        $this->getJson('/api/user/profile')->assertOk()->assertJson(['email' => $user->email]);

        $this->putJson('/api/user/profile', [
            'name' => 'Updated User',
            'email' => 'updated@example.com',
        ])->assertOk()->assertJsonPath('user.email', 'updated@example.com');
    }

    public function test_user_can_add_list_and_remove_favorites(): void
    {
        $user = $this->createUser();
        $recipe = $this->createRecipe();
        Sanctum::actingAs($user);

        $this->postJson('/api/favorites', ['recipe_id' => $recipe->id])
            ->assertStatus(201)
            ->assertJsonPath('duplicate', false);

        $this->postJson('/api/favorites', ['recipe_id' => $recipe->id])
            ->assertOk()
            ->assertJsonPath('duplicate', true);

        $this->getJson('/api/favorites')->assertOk();

        $this->deleteJson('/api/favorites/'.$recipe->id)
            ->assertOk()
            ->assertJson(['message' => 'Removed from favorites']);
    }

    public function test_match_recipes_returns_expected_payload_shape(): void
    {
        $user = $this->createUser();
        $recipe = $this->createRecipe('Garlic Chicken', ['Garlic', 'Chicken']);
        Sanctum::actingAs($user);

        $ingredientIds = $recipe->ingredients->pluck('id')->values()->all();

        $this->postJson('/api/match-recipes', [
            'ingredient_ids' => $ingredientIds,
            'per_page' => 10,
        ])->assertOk()->assertJsonStructure([
            'data',
            'current_page',
            'last_page',
            'per_page',
            'total',
            'meta' => ['pantry_size', 'strict_and_match'],
        ]);
    }

    public function test_rating_flow_saves_and_returns_average(): void
    {
        $user = $this->createUser();
        $recipe = $this->createRecipe();
        Sanctum::actingAs($user);

        $this->postJson('/api/rate', [
            'recipe_id' => $recipe->id,
            'rating' => 5,
        ])->assertOk()->assertJson(['message' => 'Rating saved']);

        $this->getJson('/api/ratings/'.$recipe->id)
            ->assertOk()
            ->assertJsonPath('average_rating', 5);
    }

    public function test_compact_browse_search_matches_recipe_name_and_ingredient(): void
    {
        $this->createRecipe('Ginatans', ['Coconut Milk', 'Shrimp']);
        $adobo = $this->createRecipe('Chicken Adobo', ['Chicken', 'Soy Sauce', 'Vinegar']);

        $byName = $this->getJson('/api/recipes?compact=1&per_page=10&q=adobo')
            ->assertOk()
            ->json('data');

        $this->assertNotEmpty($byName);
        $this->assertTrue(
            collect($byName)->contains(fn (array $row): bool => (int) ($row['id'] ?? 0) === $adobo->id)
        );
        $this->assertFalse(
            collect($byName)->contains(fn (array $row): bool => str_contains(
                strtolower((string) ($row['name'] ?? '')),
                'ginatans'
            ))
        );

        $byIngredient = $this->getJson('/api/recipes?compact=1&per_page=10&q=shrimp')
            ->assertOk()
            ->json('data');

        $this->assertTrue(
            collect($byIngredient)->contains(fn (array $row): bool => str_contains(
                strtolower((string) ($row['name'] ?? '')),
                'ginatans'
            ))
        );
    }

    public function test_recommendation_and_feed_endpoints_are_available_for_user(): void
    {
        $user = $this->createUser();
        $this->createRecipe();
        Sanctum::actingAs($user);

        $this->getJson('/api/recommended-recipes')->assertOk();
        $this->getJson('/api/home/feed')->assertOk()->assertJsonStructure([
            'recommended_for_you',
            'based_on_your_activity',
            'trending',
        ]);
    }

    public function test_ai_assistant_and_substitution_endpoints_work(): void
    {
        $user = $this->createUser();
        $this->createRecipe();
        Sanctum::actingAs($user);

        $this->postJson('/api/assistant/cook-help', ['message' => 'hello'])
            ->assertOk()
            ->assertJsonStructure(['reply', 'suggestions']);

        $this->postJson('/api/ingredients/substitutions', ['ingredients' => ['garlic']])
            ->assertOk()
            ->assertJsonStructure(['data']);
    }

    public function test_cook_now_and_combo_suggestions_work(): void
    {
        $user = $this->createUser();
        $recipe = $this->createRecipe('Egg Garlic Rice', ['Egg', 'Garlic', 'Rice']);
        Sanctum::actingAs($user);

        $ingredientIds = $recipe->ingredients->pluck('id')->values()->all();

        $this->postJson('/api/cook-now', ['ingredient_ids' => [$ingredientIds[0]]])
            ->assertOk()
            ->assertJsonStructure(['data']);

        $this->postJson('/api/ingredients/combo-suggestions', ['ingredient_ids' => [$ingredientIds[0]]])
            ->assertOk()
            ->assertJsonStructure(['data']);
    }

    public function test_admin_endpoints_are_forbidden_for_regular_user(): void
    {
        $user = $this->createUser();
        Sanctum::actingAs($user);

        $this->getJson('/api/users')->assertStatus(403);
        $this->postJson('/api/ingredients', ['name' => 'Pepper'])->assertStatus(403);
        $this->postJson('/api/admin/recipes/auto-tag', ['name' => 'Test'])->assertStatus(403);
    }

    public function test_admin_can_list_and_create_users(): void
    {
        $admin = $this->createAdmin();
        Sanctum::actingAs($admin);

        $this->getJson('/api/users')->assertOk();

        $this->postJson('/api/users', [
            'name' => 'New QA User',
            'email' => 'qa-user@example.com',
            'password' => 'password123',
            'role' => 'user',
        ])->assertStatus(201)->assertJsonPath('email', 'qa-user@example.com');
    }

    public function test_admin_can_create_ingredient(): void
    {
        $admin = $this->createAdmin();
        Sanctum::actingAs($admin);

        $this->postJson('/api/ingredients', ['name' => 'Paprika'])
            ->assertStatus(201)
            ->assertJsonPath('name', 'Paprika');
    }

    public function test_admin_can_create_recipe_using_ingredient_names_without_duplicates(): void
    {
        $admin = $this->createAdmin();
        Ingredient::create(['name' => 'Garlic']);
        Sanctum::actingAs($admin);

        $this->postJson('/api/recipes', [
            'name' => 'Admin Test Recipe',
            'category' => 'Dinner',
            'difficulty' => 'easy',
            'cooking_time' => 20,
            'instructions' => 'Mix and cook.',
            'ingredient_names' => ['Garlic', 'NewSpice123'],
        ])->assertStatus(201);

        $this->assertDatabaseCount('ingredients', 2);
        $this->assertDatabaseHas('ingredients', ['name' => 'NewSpice123']);
    }

    public function test_admin_auto_tag_endpoint_returns_ai_fields(): void
    {
        $admin = $this->createAdmin();
        Sanctum::actingAs($admin);

        $this->postJson('/api/admin/recipes/auto-tag', [
            'name' => 'Breakfast Omelette',
            'instructions' => 'Mix eggs and fry quickly.',
            'ingredients' => ['Egg', 'Onion'],
        ])->assertOk()->assertJsonStructure([
            'data' => ['category', 'difficulty', 'cooking_time', 'explain'],
        ]);
    }

    public function test_admin_metrics_endpoints_are_accessible(): void
    {
        $admin = $this->createAdmin();
        Sanctum::actingAs($admin);

        $this->getJson('/api/admin/stats')->assertOk();
        $this->getJson('/api/admin/api-usage')->assertOk();
        $this->getJson('/api/admin/error-logs')->assertOk();
        $this->getJson('/api/admin/performance-metrics')->assertOk();
    }

    public function test_admin_can_delete_recipe(): void
    {
        $admin = $this->createAdmin();
        $recipe = $this->createRecipe('Delete Me');
        Sanctum::actingAs($admin);

        $this->deleteJson('/api/recipes/'.$recipe->id)
            ->assertOk()
            ->assertJsonPath('success', true);
    }
}
