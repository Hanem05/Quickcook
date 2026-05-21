<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('recipes', function (Blueprint $table) {
            $table->index('name');
            $table->index('category');
        });

        Schema::table('ingredients', function (Blueprint $table) {
            $table->index('name');
        });

        Schema::table('recipe_ingredient', function (Blueprint $table) {
            $table->index(['recipe_id', 'ingredient_id']);
        });
    }

    public function down(): void
    {
        Schema::table('recipes', function (Blueprint $table) {
            $table->dropIndex(['name']);
            $table->dropIndex(['category']);
        });

        Schema::table('ingredients', function (Blueprint $table) {
            $table->dropIndex(['name']);
        });

        Schema::table('recipe_ingredient', function (Blueprint $table) {
            $table->dropIndex(['recipe_id', 'ingredient_id']);
        });
    }
};
