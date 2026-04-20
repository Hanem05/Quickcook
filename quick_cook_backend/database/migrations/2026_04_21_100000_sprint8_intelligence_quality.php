<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('recipes', function (Blueprint $table) {
            if (! Schema::hasColumn('recipes', 'difficulty')) {
                $table->string('difficulty', 16)->default('medium')->after('category');
            }
            if (! Schema::hasColumn('recipes', 'cooking_time')) {
                $table->unsignedSmallInteger('cooking_time')->default(30)->after('difficulty');
            }
        });

        Schema::table('favorites', function (Blueprint $table) {
            $table->unique(['user_id', 'recipe_id']);
        });

        Schema::table('collections', function (Blueprint $table) {
            $table->unique(['user_id', 'name']);
        });

        Schema::create('recipe_boost_scores', function (Blueprint $table) {
            $table->foreignId('recipe_id')->primary()->constrained()->cascadeOnDelete();
            $table->unsignedInteger('recommend_clicks')->default(0);
            $table->unsignedInteger('recommend_saves')->default(0);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('recipe_boost_scores');

        Schema::table('collections', function (Blueprint $table) {
            $table->dropUnique(['user_id', 'name']);
        });

        Schema::table('favorites', function (Blueprint $table) {
            $table->dropUnique(['user_id', 'recipe_id']);
        });

        Schema::table('recipes', function (Blueprint $table) {
            if (Schema::hasColumn('recipes', 'cooking_time')) {
                $table->dropColumn('cooking_time');
            }
            if (Schema::hasColumn('recipes', 'difficulty')) {
                $table->dropColumn('difficulty');
            }
        });
    }
};
