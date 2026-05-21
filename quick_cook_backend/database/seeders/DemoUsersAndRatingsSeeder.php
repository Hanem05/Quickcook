<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

class DemoUsersAndRatingsSeeder extends Seeder
{
    /** @var list<string> */
    public const FIRST_NAMES = [
        'Maria', 'Juan', 'Ana', 'Jose', 'Rosa', 'Carlos', 'Elena', 'Miguel', 'Sofia', 'Luis',
        'Isabella', 'Antonio', 'Camila', 'Francisco', 'Valentina', 'Rafael', 'Gabriela', 'Diego',
        'Mariana', 'Andres', 'Patricia', 'Fernando', 'Lucia', 'Ricardo', 'Adriana', 'Eduardo',
        'Daniela', 'Roberto', 'Paula', 'Sergio', 'Claudia', 'Manuel', 'Veronica', 'Jorge',
        'Natalia', 'Alberto', 'Monica', 'Raul', 'Teresa', 'Oscar', 'Beatriz', 'Hector', 'Silvia',
        'Enrique', 'Carmen', 'Arturo', 'Laura', 'Felipe', 'Diana', 'Victor', 'Alejandra',
    ];

    /** @var list<string> */
    public const LAST_NAMES = [
        'Santos', 'Reyes', 'Cruz', 'Bautista', 'Garcia', 'Mendoza', 'Torres', 'Flores', 'Rivera',
        'Gonzales', 'Ramos', 'Diaz', 'Morales', 'Aquino', 'Castillo', 'Fernandez', 'Lopez',
        'Martinez', 'Hernandez', 'Perez', 'Sanchez', 'Romero', 'Vargas', 'Jimenez', 'Ruiz',
        'Alvarez', 'Domingo', 'Salazar', 'Pascual', 'Velasco', 'Marquez', 'Navarro', 'Soriano',
        'Aguilar', 'Del Rosario', 'Ignacio', 'Padilla', 'Santiago', 'Mercado', 'Tolentino',
        'Manalo', 'Estrada', 'Panganiban', 'Villanueva', 'Corpuz', 'Magbanua', 'Ilagan', 'Bondoc',
    ];

    public function run(): void
    {
        $demoUserCount = (int) env('SEED_DEMO_USER_COUNT', 2000);
        /** Demo ratings per recipe (not one rating per demo user per recipe). */
        $ratingsPerRecipe = max(0, (int) env('SEED_RATINGS_PER_RECIPE', 12));
        $batchSize = 5000;

        $this->command?->info('Updating demo user display names to real names...');
        $this->renameExistingDemoUsers();

        $this->command?->info("Creating {$demoUserCount} demo users...");
        $now = now();
        $usersBatch = [];
        for ($i = 1; $i <= $demoUserCount; $i++) {
            $usersBatch[] = [
                'name' => $this->realNameForIndex($i),
                'email' => sprintf('demo_user_%04d@quickcook.demo', $i),
                'password' => Hash::make('password'),
                'role' => 'user',
                'created_at' => $now,
                'updated_at' => $now,
            ];

            if (count($usersBatch) >= 500) {
                DB::table('users')->insertOrIgnore($usersBatch);
                $usersBatch = [];
            }
        }
        if ($usersBatch !== []) {
            DB::table('users')->insertOrIgnore($usersBatch);
        }

        $demoUsers = DB::table('users')
            ->where('email', 'like', 'demo_user_%@quickcook.demo')
            ->orderBy('id')
            ->limit($demoUserCount)
            ->pluck('id')
            ->map(static fn ($id): int => (int) $id)
            ->values()
            ->all();

        $recipeIds = DB::table('recipes')
            ->orderBy('id')
            ->pluck('id')
            ->map(static fn ($id): int => (int) $id)
            ->values()
            ->all();

        if ($demoUsers === []) {
            $this->command?->warn('No demo users found; skipping ratings seed.');

            return;
        }
        if ($recipeIds === []) {
            $this->command?->warn('No recipes found; skipping ratings seed.');

            return;
        }

        if ($ratingsPerRecipe === 0) {
            DB::table('ratings')->whereIn('user_id', $demoUsers)->delete();
            $this->command?->info('Demo users seeded; demo ratings disabled (SEED_RATINGS_PER_RECIPE=0).');

            return;
        }

        $this->command?->info(sprintf(
            'Seeding ~%d demo ratings per recipe (%d recipes, %d demo users)...',
            $ratingsPerRecipe,
            count($recipeIds),
            count($demoUsers)
        ));

        DB::table('ratings')->whereIn('user_id', $demoUsers)->delete();

        DB::connection()->disableQueryLog();
        $rows = [];
        $seeded = 0;
        $raterCount = count($demoUsers);

        foreach ($recipeIds as $recipeId) {
            // Vary the typical score per recipe so admin charts are not flat at 3.0.
            $recipeAnchor = ($recipeId % 5) + 1;

            for ($slot = 0; $slot < $ratingsPerRecipe; $slot++) {
                $userId = $demoUsers[($recipeId + $slot) % $raterCount];
                $noise = ($slot % 3) - 1;
                $rating = max(1, min(5, $recipeAnchor + $noise));

                $rows[] = [
                    'user_id' => $userId,
                    'recipe_id' => $recipeId,
                    'rating' => $rating,
                    'created_at' => $now,
                    'updated_at' => $now,
                ];

                if (count($rows) >= $batchSize) {
                    DB::table('ratings')->insertOrIgnore($rows);
                    $seeded += count($rows);
                    $rows = [];
                }
            }
        }

        if ($rows !== []) {
            DB::table('ratings')->insertOrIgnore($rows);
            $seeded += count($rows);
        }

        $this->command?->info("Demo users + sparse ratings seeded. Inserted ratings rows: {$seeded}");
        $this->command?->info('Real user ratings will now visibly change recipe averages (re-seed required on existing DB).');
    }

    private function realNameForIndex(int $index): string
    {
        $first = self::FIRST_NAMES[($index - 1) % count(self::FIRST_NAMES)];
        $last = self::LAST_NAMES[(int) (($index - 1) / count(self::FIRST_NAMES) + ($index * 3)) % count(self::LAST_NAMES)];

        return $first.' '.$last;
    }

    private function renameExistingDemoUsers(): void
    {
        $rows = DB::table('users')
            ->where('email', 'like', 'demo_user_%@quickcook.demo')
            ->orderBy('id')
            ->get(['id', 'email']);

        $i = 1;
        foreach ($rows as $row) {
            if (preg_match('/demo_user_(\d+)@quickcook\.demo/i', (string) $row->email, $m) === 1) {
                $i = max(1, (int) $m[1]);
            }
            DB::table('users')->where('id', $row->id)->update([
                'name' => $this->realNameForIndex($i),
                'updated_at' => now(),
            ]);
            $i++;
        }
    }
}
