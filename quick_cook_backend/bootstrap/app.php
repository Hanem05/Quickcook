<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__ . '/../routes/web.php',
        api: __DIR__ . '/../routes/api.php',
        commands: __DIR__ . '/../routes/console.php',
        health: '/up',

    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'admin' => \App\Http\Middleware\EnsureUserIsAdmin::class,
        ]);
        $middleware->api(append: [
            \App\Http\Middleware\MonitorApiUsage::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // Task 41: Capture server exceptions and store them
        $exceptions->reportable(function (\Throwable $e) {
            $severity = $e instanceof \Error ? 'critical' : 'error';
            try {
                \DB::table('system_errors')->insert([
                    'message' => $e->getMessage(),
                    'stack_trace' => substr($e->getTraceAsString(), 0, 1000),
                    'endpoint' => request()->path(),
                    'status_code' => 500,
                    'severity' => $severity,
                    'error_type' => (new \ReflectionClass($e))->getShortName(),
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            } catch (\Throwable $ignored) {
                // Avoid breaking the app if migration not run yet
            }
        });
    })->create();
