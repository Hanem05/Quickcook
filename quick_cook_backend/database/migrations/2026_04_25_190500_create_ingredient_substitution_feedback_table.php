<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('ingredient_substitution_feedback')) {
            return;
        }

        Schema::create('ingredient_substitution_feedback', function (Blueprint $table) {
            $table->id();
            $table->string('ingredient', 100);
            $table->string('substitute', 100);
            $table->unsignedInteger('accepted_count')->default(0);
            $table->unsignedInteger('rejected_count')->default(0);
            $table->timestamps();

            $table->unique(['ingredient', 'substitute'], 'ingredient_substitute_unique');
            $table->index('ingredient');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('ingredient_substitution_feedback');
    }
};
