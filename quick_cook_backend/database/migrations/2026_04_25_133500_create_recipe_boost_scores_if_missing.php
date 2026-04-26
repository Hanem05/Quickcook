<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('recipe_boost_scores')) {
            return;
        }

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
    }
};
