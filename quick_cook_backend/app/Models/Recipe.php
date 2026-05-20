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

    protected $appends = [
        'image_url',
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
        $resolved = static::publicImageUrl($this->image);
        if ($resolved !== null && trim($resolved) !== '') {
            return $resolved;
        }

        return static::defaultImageUrl();
    }

    public static function publicImageUrl(?string $path): ?string
    {
        if ($path === null || trim($path) === '') {
            return null;
        }

        $trimmed = trim($path);
        if (preg_match('/^https?:\/\//i', $trimmed) === 1 || str_starts_with($trimmed, '//')) {
            return $trimmed;
        }

        $raw = ltrim($path, '/');
        $encoded = implode('/', array_map('rawurlencode', explode('/', $raw)));

        if (str_starts_with($raw, 'images/')) {
            $request = request();
            if ($request !== null) {
                return $request->getSchemeAndHttpHost().'/'.$encoded;
            }

            return asset($encoded);
        }

        // Prefer current request origin (works for emulator host 10.0.2.2 and web localhost).
        $request = request();
        if ($request !== null) {
            return $request->getSchemeAndHttpHost().'/storage/'.$encoded;
        }

        $cdnBase = rtrim((string) env('APP_CDN_URL', ''), '/');
        if ($cdnBase !== '') {
            return $cdnBase.'/'.$encoded;
        }

        $publicBase = rtrim((string) env('APP_STORAGE_PUBLIC_BASE_URL', ''), '/');
        if ($publicBase !== '' && ! str_contains($publicBase, '://nginx')) {
            return $publicBase.'/storage/'.$encoded;
        }

        $appUrl = rtrim((string) config('app.url'), '/');
        if ($appUrl !== '' && ! str_contains($appUrl, '://nginx')) {
            return $appUrl.'/storage/'.$encoded;
        }

        return asset('storage/'.$encoded);
    }

    public static function defaultImageUrl(): string
    {
        return asset('images/recipe-placeholder.svg');
    }

    public function ratings()
    {
        return $this->hasMany(Ratings::class);
    }
}
