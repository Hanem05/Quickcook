<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class UserActivity extends Model
{
    protected $fillable = [
        'user_id', 
        'action', 
        'recipe_id',
        'ingredient_id' // FIX: This MUST be here to fix Task 34
    ];

    public function user() {
        return $this->belongsTo(User::class);
    }

    public function recipe() {
        return $this->belongsTo(Recipe::class);
    }

    // FIX: Added for Ingredient Tracking
    public function ingredient() {
        return $this->belongsTo(Ingredient::class);
    }

    
}