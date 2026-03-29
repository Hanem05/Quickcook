<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Collection extends Model
{
    use HasFactory;

    protected $fillable = [
        'user_id',
        'name',
    ];

    // 🔥 relationship with recipes
    public function recipes()
    {
        return $this->belongsToMany(Recipe::class);
    }

    // 🔥 relationship with user
    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
