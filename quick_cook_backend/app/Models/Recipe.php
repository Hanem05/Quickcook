<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Recipe extends Model
{
    use HasFactory;

    protected $fillable = [
        'name',
        'category',
        'difficulty',
        'cooking_time',
        'instructions',
        'image',
    ];

    public function ingredients()
    {
        return $this->belongsToMany(
            Ingredient::class,
            'recipe_ingredient',
            'recipe_id',
            'ingredient_id'
        );
    }

    public function favorites()
    {
        return $this->hasMany(Favorite::class);
    }

    public function getImageUrlAttribute()
    {
        if (! $this->image) {
            return null;
        }

        return static::publicImageUrl($this->image);
    }

    public static function publicImageUrl(?string $path): ?string
    {
        if ($path === null || trim($path) === '') {
            return null;
        }

        $raw = ltrim($path, '/');
        $encoded = implode('/', array_map('rawurlencode', explode('/', $raw)));
        $cdnBase = rtrim((string) env('APP_CDN_URL', ''), '/');
        if ($cdnBase !== '') {
            return $cdnBase.'/'.$encoded;
        }

        $publicBase = rtrim((string) env('APP_STORAGE_PUBLIC_BASE_URL', ''), '/');
        if ($publicBase !== '') {
            return $publicBase.'/storage/'.$encoded;
        }

        return asset('storage/'.$encoded);
    }

    public function ratings()
    {
        return $this->hasMany(Ratings::class);
    }
}
