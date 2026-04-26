<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use App\Models\User;
use Illuminate\Support\Facades\Hash;

class UserController extends Controller
{
    // For Admin: Get all users
    public function index()
    {
        return response()->json(User::select('id', 'name', 'email', 'role', 'created_at')->get());
    }

    // NEW: Get current logged in user (This is what Flutter is looking for)
    public function profile(Request $request)
    {
        return response()->json($request->user());
    }

    // NEW: Update profile (This is for the Save button)
    public function updateProfile(Request $request)
    {
        $user = $request->user();

        $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|string|email|max:255|unique:users,email,' . $user->id,
            'password' => 'nullable|string|min:6',
        ]);

        $user->name = $request->name;
        $user->email = $request->email;

        if ($request->filled('password')) {
            $user->password = Hash::make($request->password);
        }

        $user->save();

        return response()->json([
            'message' => 'Profile updated successfully',
            'user' => $user
        ]);
    }

    // --- UPDATE USER (ADMIN) ---
    public function update(Request $request, $id)
    {
        $user = User::find($id);

        if (!$user) {
            return response()->json(['message' => 'User not found'], 404);
        }

        // Validate the incoming data
        $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|string|email|max:255|unique:users,email,' . $id,
            // The 'unique:users,email,' . $id part is crucial! It lets the user keep their existing email without throwing a "this email is already taken" error.
        ]);

        // Update the user
        $user->name = $request->name;
        $user->email = $request->email;
        $user->save();

        return response()->json([
            'message' => 'User updated successfully',
            'user' => $user
        ]);
    }

    // --- DELETE USER (ADMIN) ---
    public function destroy($id)
    {
        $user = User::find($id);

        if (!$user) {
            return response()->json(['message' => 'User not found'], 404);
        }

        // IMPORTANT: Clean up related data first to prevent foreign key constraint errors!
        // Uncomment these if you have these relationships set up in your User model:

        // $user->favorites()->delete(); 
        // $user->ratings()->delete();
        // $user->activities()->delete(); 

        $user->delete();

        return response()->json(['message' => 'User deleted successfully']);
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'name' => 'required|string|max:255',
            'email' => 'required|string|email|max:255|unique:users',
            'password' => 'required|string|min:8',
            'role' => 'required|string|in:admin,user',
        ]);

        $user = User::create([
            'name' => $validated['name'],
            'email' => $validated['email'],
            'password' => Hash::make($validated['password']),
            'role' => strtolower($validated['role']),
        ]);

        return response()->json($user, 201);
    }

}
