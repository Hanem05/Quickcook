<?php

namespace App\Console\Commands;

use Database\Seeders\DemoUsersAndRatingsSeeder;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

class RenameDemoUserNamesCommand extends Command
{
    protected $signature = 'users:rename-demo-display-names';

    protected $description = 'Replace Demo User NNN names with realistic first/last names (emails unchanged)';

    public function handle(): int
    {
        $first = DemoUsersAndRatingsSeeder::FIRST_NAMES;
        $last = DemoUsersAndRatingsSeeder::LAST_NAMES;
        $count = 0;

        $rows = DB::table('users')
            ->where('email', 'like', 'demo_user_%@quickcook.demo')
            ->orderBy('id')
            ->get(['id', 'email']);

        foreach ($rows as $row) {
            $i = 1;
            if (preg_match('/demo_user_(\d+)@quickcook\.demo/i', (string) $row->email, $m) === 1) {
                $i = max(1, (int) $m[1]);
            }
            $firstName = $first[($i - 1) % count($first)];
            $lastName = $last[(int) (($i - 1) / count($first) + ($i * 3)) % count($last)];
            DB::table('users')->where('id', $row->id)->update([
                'name' => $firstName.' '.$lastName,
                'updated_at' => now(),
            ]);
            $count++;
        }

        $this->info("Updated {$count} demo user display names.");

        return self::SUCCESS;
    }
}
