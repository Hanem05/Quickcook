<?php

namespace App\Jobs;

use App\Http\Controllers\RecipeController;
use App\Models\User;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class WarmRecommendationCacheJob implements ShouldQueue
{
    use Queueable;

    public function __construct(
        public readonly ?int $userId = null
    ) {}

    public function handle(): void
    {
        $controller = app(RecipeController::class);
        $request = Request::create('/api/recommended-recipes', 'GET', ['limit' => 15]);

        if ($this->userId) {
            $user = User::query()->find($this->userId);
            if ($user) {
                $request->setUserResolver(static fn () => $user);
            }
        }

        try {
            $controller->recommend($request);
        } catch (\Throwable $e) {
            Log::warning('WarmRecommendationCacheJob failed', [
                'user_id' => $this->userId,
                'error' => $e->getMessage(),
            ]);
        }
    }
}
