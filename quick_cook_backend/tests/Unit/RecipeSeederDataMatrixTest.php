<?php

namespace Tests\Unit;

use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

class RecipeSeederDataMatrixTest extends TestCase
{
    #[DataProvider('recipeDatasetProvider')]
    public function test_recipe_seed_row_has_required_fields(array $row): void
    {
        $this->assertArrayHasKey('name', $row);
        $this->assertArrayHasKey('category', $row);
        $this->assertArrayHasKey('instructions', $row);
        $this->assertArrayHasKey('ingredients', $row);

        $this->assertNotSame('', trim((string) $row['name']));
        $this->assertNotSame('', trim((string) $row['category']));
        $this->assertNotSame('', trim((string) $row['instructions']));
        $this->assertIsArray($row['ingredients']);
        $this->assertNotEmpty($row['ingredients']);
    }

    public static function recipeDatasetProvider(): array
    {
        $cases = [];
        for ($i = 1; $i <= 72; $i++) {
            $cases['seed_row_'.$i] = [[
                'name' => 'Recipe '.$i,
                'category' => $i % 5 === 0 ? 'Dinner' : 'Lunch',
                'instructions' => 'Step 1: Prepare. Step 2: Cook. Step 3: Serve.',
                'ingredients' => ['Ingredient A', 'Ingredient B'],
            ]];
        }

        return $cases;
    }
}
