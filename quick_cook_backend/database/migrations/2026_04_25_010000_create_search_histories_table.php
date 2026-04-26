<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('search_histories', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('query', 255);
            $table->unsignedInteger('hits')->default(0);
            $table->timestamp('last_searched_at')->nullable();
            $table->timestamps();

            $table->unique(['user_id', 'query']);
            $table->index(['user_id', 'last_searched_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('search_histories');
    }
};
