<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SearchHistory extends Model
{
    protected $fillable = [
        'user_id',
        'query',
        'hits',
        'last_searched_at',
    ];

    protected $casts = [
        'last_searched_at' => 'datetime',
    ];
}
