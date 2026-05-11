<?php

namespace Tests\Unit;

use App\Models\AdminStats;
use App\Models\ApiUsage;
use App\Models\Collection;
use App\Models\Favorite;
use App\Models\Ingredient;
use App\Models\Ratings;
use App\Models\Recipe;
use App\Models\SearchHistory;
use App\Models\User;
use App\Models\UserActivity;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Foundation\Auth\User as Authenticatable;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

class ModelCoverageTest extends TestCase
{
    public static function modelClassProvider(): array
    {
        return [
            [Recipe::class],
            [Collection::class],
            [Ingredient::class],
            [User::class],
            [SearchHistory::class],
            [ApiUsage::class],
            [UserActivity::class],
            [AdminStats::class],
            [Ratings::class],
            [Favorite::class],
        ];
    }

    #[DataProvider('modelClassProvider')]
    public function test_model_class_is_instantiable(string $modelClass): void
    {
        $instance = new $modelClass();
        $this->assertInstanceOf($modelClass, $instance);
    }

    #[DataProvider('modelClassProvider')]
    public function test_model_class_extends_expected_base(string $modelClass): void
    {
        $instance = new $modelClass();

        if ($instance instanceof User) {
            $this->assertInstanceOf(Authenticatable::class, $instance);
            return;
        }

        $this->assertInstanceOf(Model::class, $instance);
    }

    #[DataProvider('modelClassProvider')]
    public function test_model_reports_non_empty_table_name(string $modelClass): void
    {
        $instance = new $modelClass();
        $this->assertIsString($instance->getTable());
        $this->assertNotSame('', trim($instance->getTable()));
    }

    #[DataProvider('modelClassProvider')]
    public function test_model_has_mass_assignment_configuration(string $modelClass): void
    {
        $instance = new $modelClass();
        $fillable = $instance->getFillable();
        $guarded = $instance->getGuarded();

        $this->assertIsArray($fillable);
        $this->assertIsArray($guarded);
        $this->assertTrue(
            count($fillable) > 0 || count($guarded) > 0,
            $modelClass.' should define fillable or guarded fields.'
        );
    }
}

