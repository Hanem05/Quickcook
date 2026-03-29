<?php

namespace App\Http\Controllers;

use App\Models\UserActivity;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class ActivityController extends Controller
{
    public function log(Request $request)
    {
        $request->validate([
            'action' => 'required|string',
            'recipe_id' => 'nullable|integer'
        ]);

        if (!Auth::check()) {
            return response()->json(['error' => 'Unauthorized'], 401);
        }

        try {
            $activity = UserActivity::create([
                'user_id' => Auth::id(),
                'action' => $request->action,
                'recipe_id' => $request->recipe_id
            ]);

            return response()->json([
                'message' => 'Activity logged',
                'data' => $activity
            ], 201);

        } catch (\Exception $e) {
            return response()->json([
                'error' => 'Database error',
                'details' => $e->getMessage()
            ], 500);
        }
    }

    public function index()
    {
        $activities = UserActivity::with(['user', 'recipe'])
            ->latest()
            ->get();

        return response()->json($activities);
    }
}