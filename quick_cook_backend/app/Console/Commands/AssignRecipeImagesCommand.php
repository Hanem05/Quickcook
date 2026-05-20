<?php

namespace App\Console\Commands;

use Database\Seeders\RecipeSeeder;
use Illuminate\Console\Command;

class AssignRecipeImagesCommand extends Command
{
    protected $signature = 'recipes:assign-images
                            {--sync-only : Only copy imgs/ into storage, do not update the database}';

    protected $description = 'Copy recipe photos from the repo imgs/ folder and assign them to all recipes (rotating).';

    public function handle(): int
    {
        $seeder = new RecipeSeeder;
        $seeder->setCommand($this);

        $copied = $seeder->syncRepoImgsToPublicStorage();
        $this->info("Synced {$copied} image(s) to storage/app/public/recipes/seed/.");

        if ($this->option('sync-only')) {
            return self::SUCCESS;
        }

        $assigned = $seeder->assignImagesFromPoolToAllRecipes();
        $this->info("Updated image on {$assigned} recipe(s).");

        return self::SUCCESS;
    }
}
