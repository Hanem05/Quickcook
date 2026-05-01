<?php

namespace App\Services;

use App\Models\Ingredient;

class IngredientResolverService
{
    /**
     * Resolve ingredient IDs from both provided IDs and free-text names.
     * Existing names are reused (case-insensitive), new ones are created.
     *
     * @param array<string,mixed> $validated
     * @return array<int>
     */
    public function resolve(array $validated): array
    {
        $ids = collect($validated['ingredient_ids'] ?? [])
            ->map(static fn ($id): int => (int) $id)
            ->filter(static fn (int $id): bool => $id > 0)
            ->values()
            ->all();

        $rawNames = collect($validated['ingredient_names'] ?? [])
            ->map(static fn ($name): string => trim((string) $name))
            ->filter(static fn (string $name): bool => $name !== '')
            ->values()
            ->all();

        foreach ($rawNames as $name) {
            $normalized = mb_strtolower(trim($name));
            $existing = Ingredient::query()
                ->whereRaw('LOWER(TRIM(name)) = ?', [$normalized])
                ->first();

            if ($existing) {
                $ids[] = (int) $existing->id;
                continue;
            }

            $created = Ingredient::create(['name' => $name]);
            $ids[] = (int) $created->id;
        }

        return collect($ids)->unique()->values()->all();
    }
}
