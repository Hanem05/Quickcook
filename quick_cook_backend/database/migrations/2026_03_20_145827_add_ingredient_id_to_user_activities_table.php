<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        if (Schema::hasColumn('user_activities', 'ingredient_id')) {
            return;
        }

        Schema::table('user_activities', function (Blueprint $table) {
            $table->foreignId('ingredient_id')->nullable()->constrained()->onDelete('cascade');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        if (!Schema::hasColumn('user_activities', 'ingredient_id')) {
            return;
        }

        Schema::table('user_activities', function (Blueprint $table) {
            $table->dropConstrainedForeignId('ingredient_id');
        });
    }
};
