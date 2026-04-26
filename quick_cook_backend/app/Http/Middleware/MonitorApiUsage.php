<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Schema;
use Symfony\Component\HttpFoundation\Response;

class MonitorApiUsage
{
    /**
     * Handle an incoming request.
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     */
    public function handle(Request $request, Closure $next)
    {
        $startTime = microtime(true); // 1. START STOPWATCH

        $response = $next($request);

        $endTime = microtime(true);   // 2. STOP STOPWATCH
        // Calculate difference in milliseconds
        $latency = (int) round(($endTime - $startTime) * 1000);

        // Keep hot endpoints fast and avoid logging overhead failures.
        $hot = [
            'api/recipes',
            'api/ingredients',
            'api/recommended-recipes',
            'api/home/feed',
        ];
        if (in_array($request->path(), $hot, true)) {
            return $response;
        }

        try {
            if (Schema::hasTable('api_logs')) {
                \DB::table('api_logs')->insert([
                    'endpoint' => $request->path(),
                    'method' => $request->method(),
                    'status_code' => $response->getStatusCode(),
                    'latency_ms' => $latency, // 3. MUST MATCH DATABASE COLUMN NAME
                    'created_at' => now(),
                ]);
            }
        } catch (\Throwable $e) {
            // Intentionally swallow logging failures so API responses stay fast.
        }

        return $response;
    }
}
