# Sprint 9 — AI Enhancement, Innovation & Next-Level Features

This document explains the Sprint 9 implementation logic and how to defend each feature during demo/Q&A.

## Implemented Tasks

- **Task 90 — AI Recipe Recommendation**
  - Enhanced recommendation scoring in `RecipeController@recommend`.
  - Added interaction-frequency weighting (`view_recipe`, `favorite_recipe`, `cook_now_open`) so repeated behavior impacts ranking.

- **Task 91 — Ingredient Combination Predictor**
  - Endpoint: `POST /api/ingredients/combo-suggestions`
  - Uses co-occurrence frequency from `recipe_ingredient` to suggest "Try adding" ingredients.

- **Task 92 — AI Cooking Assistant (rule-based)**
  - Endpoint: `POST /api/assistant/cook-help`
  - Supports prompts like substitution, quick meals, and "what can I cook?"
  - Returns text reply plus optional recipe suggestions.

- **Task 93 — Smart Recipe Auto-Tagging (Admin AI Tool)**
  - Endpoint: `POST /api/admin/recipes/auto-tag`
  - Admin UI trigger added in `admin_recipes_screen.dart` ("AI Auto-Tag" button).
  - Heuristic inference for category, difficulty, and cooking time estimate.

- **Task 94 — Personalized Cooking Insights**
  - Endpoint: `GET /api/user/cooking-insights`
  - Returns favorite categories, average cooking time, and habit message.
  - Home screen renders habit insight card.

- **Task 95 — Smart Notifications (Behavior-Based)**
  - Endpoint: `GET /api/notifications/smart`
  - Local notification bridge added: `NotificationService.maybeShowSmartMessage`.
  - Uses behavior context (favorites category, inactivity) to build smart messages.

- **Task 96 — Recipe Difficulty Auto-Adjustment**
  - `RecipeController@show` now returns `personalized_difficulty`.
  - Based on user's cooking activity volume + base recipe difficulty.

- **Task 97 — Ingredient Substitution Learning**
  - Endpoint: `POST /api/ingredients/substitutions/feedback`
  - Migration added for learning table:
    - `ingredient_substitution_feedback`
  - `ingredientSubstitutions` now prioritizes learned alternatives before static rules.

- **Task 98 — Smart Cook Now Mode**
  - Endpoint: `POST /api/cook-now`
  - Returns recipes fully ready with selected ingredients (`AND` matching).
  - Home UI adds `Cook Now Mode` toggle.

- **Task 99 — Innovation Documentation**
  - This file serves as logic/algorithm documentation and demo defense notes.

## Core AI Justification

- **Why "semi-AI" instead of pure ML?**
  - Current implementation is deterministic + explainable and production-safe for existing data volume.
  - It combines behavior signals, co-occurrence, and adaptive feedback (online learning style).

- **How personalization works**
  - Weighted ranking from historical interactions and affinity features.
  - User-level insights and contextual notification messages are generated from activity trends.

- **How learning works (Task 97)**
  - Users submit accepted/rejected substitution feedback.
  - Future substitution responses prioritize highest accepted alternatives.

## Demo Talking Points

- "Recommendations adapt to interaction frequency, not just one-time events."
- "Ingredient combo suggestions come from real recipe co-occurrence patterns."
- "Assistant handles cooking intent and substitutions with grounded rule logic."
- "Admin has AI-assisted auto-tagging to speed recipe moderation."
- "Cook Now mode instantly filters to recipes that are truly ready."

## Suggested Next Step (Post-Sprint)

- Replace heuristic weights with tunable config table or online-learned parameters.
- Add A/B switch to compare baseline vs Sprint 9 ranking quality.
- Add explicit push-token pipeline if remote push notifications are required.
