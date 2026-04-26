<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected function hasIndex(string $table, string $index): bool
    {
        $driver = DB::getDriverName();
        if ($driver === 'sqlite') {
            $rows = DB::select("PRAGMA index_list('$table')");
            foreach ($rows as $row) {
                $name = is_array($row) ? ($row['name'] ?? null) : ($row->name ?? null);
                if ($name === $index) {
                    return true;
                }
            }
            return false;
        }

        $db = DB::getDatabaseName();
        $rows = DB::select(
            'SELECT 1 FROM information_schema.statistics WHERE table_schema = ? AND table_name = ? AND index_name = ? LIMIT 1',
            [$db, $table, $index]
        );
        return $rows !== [];
    }

    public function up(): void
    {
        Schema::table('recipes', function (Blueprint $table) {
            if (! app()->runningUnitTests()) {
                // no-op: index checks are handled outside closure
            }
        });

        if (! $this->hasIndex('recipes', 'recipes_category_idx')) {
            Schema::table('recipes', fn (Blueprint $table) => $table->index('category', 'recipes_category_idx'));
        }
        if (! $this->hasIndex('recipes', 'recipes_difficulty_idx')) {
            Schema::table('recipes', fn (Blueprint $table) => $table->index('difficulty', 'recipes_difficulty_idx'));
        }
        if (! $this->hasIndex('recipes', 'recipes_cooking_time_idx')) {
            Schema::table('recipes', fn (Blueprint $table) => $table->index('cooking_time', 'recipes_cooking_time_idx'));
        }

        if (! $this->hasIndex('user_activities', 'user_activities_user_id_idx')) {
            Schema::table('user_activities', fn (Blueprint $table) => $table->index('user_id', 'user_activities_user_id_idx'));
        }
        if (! $this->hasIndex('user_activities', 'user_activities_recipe_id_idx')) {
            Schema::table('user_activities', fn (Blueprint $table) => $table->index('recipe_id', 'user_activities_recipe_id_idx'));
        }
        if (! $this->hasIndex('user_activities', 'user_activities_action_created_idx')) {
            Schema::table('user_activities', fn (Blueprint $table) => $table->index(['action', 'created_at'], 'user_activities_action_created_idx'));
        }

        if (! $this->hasIndex('favorites', 'favorites_user_recipe_idx')) {
            Schema::table('favorites', fn (Blueprint $table) => $table->index(['user_id', 'recipe_id'], 'favorites_user_recipe_idx'));
        }
        if (! $this->hasIndex('favorites', 'favorites_recipe_user_idx')) {
            Schema::table('favorites', fn (Blueprint $table) => $table->index(['recipe_id', 'user_id'], 'favorites_recipe_user_idx'));
        }

        if (! $this->hasIndex('collection_recipe', 'collection_recipe_recipe_collection_idx')) {
            Schema::table('collection_recipe', fn (Blueprint $table) => $table->index(['recipe_id', 'collection_id'], 'collection_recipe_recipe_collection_idx'));
        }

        if (! $this->hasIndex('recipe_ingredient', 'recipe_ingredient_recipe_ing_idx')) {
            Schema::table('recipe_ingredient', fn (Blueprint $table) => $table->index(['recipe_id', 'ingredient_id'], 'recipe_ingredient_recipe_ing_idx'));
        }
        if (! $this->hasIndex('recipe_ingredient', 'recipe_ingredient_ing_recipe_idx')) {
            Schema::table('recipe_ingredient', fn (Blueprint $table) => $table->index(['ingredient_id', 'recipe_id'], 'recipe_ingredient_ing_recipe_idx'));
        }
    }

    public function down(): void
    {
        $drops = [
            ['recipes', 'recipes_category_idx'],
            ['recipes', 'recipes_difficulty_idx'],
            ['recipes', 'recipes_cooking_time_idx'],
            ['user_activities', 'user_activities_user_id_idx'],
            ['user_activities', 'user_activities_recipe_id_idx'],
            ['user_activities', 'user_activities_action_created_idx'],
            ['favorites', 'favorites_user_recipe_idx'],
            ['favorites', 'favorites_recipe_user_idx'],
            ['collection_recipe', 'collection_recipe_recipe_collection_idx'],
            ['recipe_ingredient', 'recipe_ingredient_recipe_ing_idx'],
            ['recipe_ingredient', 'recipe_ingredient_ing_recipe_idx'],
        ];

        foreach ($drops as [$table, $index]) {
            if ($this->hasIndex($table, $index)) {
                Schema::table($table, fn (Blueprint $t) => $t->dropIndex($index));
            }
        }
    }
};
