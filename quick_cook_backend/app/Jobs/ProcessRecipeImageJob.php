<?php

namespace App\Jobs;

use App\Models\Recipe;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

class ProcessRecipeImageJob implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public readonly int $recipeId
    ) {}

    public function handle(): void
    {
        $recipe = Recipe::query()->find($this->recipeId);
        if (! $recipe || ! $recipe->image) {
            return;
        }

        if (! Storage::disk('public')->exists($recipe->image)) {
            Log::warning('ProcessRecipeImageJob: image missing', [
                'recipe_id' => $this->recipeId,
                'image' => $recipe->image,
            ]);
            return;
        }

        // Placeholder queue task: this is where resizing/watermarking/CDN sync can run.
        // Keeping it lightweight avoids runtime failures on hosts without GD/Imagick.
        Log::info('ProcessRecipeImageJob completed', [
            'recipe_id' => $this->recipeId,
            'image' => $recipe->image,
        ]);
    }
}
