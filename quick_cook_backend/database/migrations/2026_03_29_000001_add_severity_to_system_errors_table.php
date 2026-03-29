<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('system_errors', function (Blueprint $table) {
            $table->string('severity', 24)->default('error')->after('status_code');
            $table->string('error_type', 120)->nullable()->after('severity');
        });
    }

    public function down(): void
    {
        Schema::table('system_errors', function (Blueprint $table) {
            $table->dropColumn(['severity', 'error_type']);
        });
    }
};
