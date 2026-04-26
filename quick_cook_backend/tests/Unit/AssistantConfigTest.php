<?php

namespace Tests\Unit;

use PHPUnit\Framework\TestCase;

class AssistantConfigTest extends TestCase
{
    public function test_default_assistant_prompt_is_not_empty(): void
    {
        $defaultPrompt = 'QuickCook Assistant';

        $this->assertIsString($defaultPrompt);
        $this->assertNotSame('', trim($defaultPrompt));
    }
}
