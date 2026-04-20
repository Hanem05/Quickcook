# Sprint 8 — Plan (10 tasks · 64h · 2 developers)

**Sprint goal:** Ship production-oriented improvements (UX, automation, ops, polish) on top of the existing QuickCook stack (Laravel API + Flutter app).

**Capacity:** Dev A **32h** · Dev B **32h** · **Total 64h**  
**Cadence:** ~2 weeks at 16h/week per developer (adjust if your sprint length differs).

---

## Hours overview

| Developer | Allocation |
|-----------|------------|
| **Dev A** | 32h — tasks **80, 82, 84, 86, 88** |
| **Dev B** | 32h — tasks **81, 83, 85, 87, 89** |

Hour mix: **two 8h** anchors (collections, deployment) + **eight 6h** tasks → **64h** total.

---

## Task breakdown

| ID | Task | Owner | Hours | Summary deliverables |
|----|------|-------|-------|----------------------|
| **80** | **Collections 2.0** | Dev A | **8** | Rename collection; duplicate-name validation; stable add/remove recipes; optional recipe order or “cover” MVP; Flutter: collection list + detail polish, empty/error states. |
| **81** | **Weekly meal planner** | Dev B | **6** | Persist week (Mon–Sun) per user (DB + API + Flutter): assign recipe IDs per day; prev/next week; load/save; optional “suggest week” stub from recommend/random. |
| **82** | **Grocery list from recipes** | Dev A | **6** | API: merge ingredients for `recipe_ids[]` (dedupe by name); Flutter: checklist UI + “done” state (local state or prefs). |
| **83** | **Voice → search** | Dev B | **6** | `speech_to_text` (or platform ASR): mic on home/search → fills query → reuse existing global search; Android/iOS permissions. |
| **84** | **Push-ready pipeline** | Dev A | **6** | Backend: store FCM tokens per user/device; Flutter: obtain token + `POST` register (Firebase optional if time-boxed); short doc for sending via Firebase Console. |
| **85** | **Profile insights** | Dev B | **6** | API: aggregates (saved count, top categories from activity, recent ids); Flutter: small dashboard on profile (cards/chips). |
| **86** | **Dark mode & motion polish** | Dev A | **6** | Audit theme toggle; spacing/typography pass on 2–3 main screens; one consistent page transition / loading pattern. |
| **87** | **Deployment pack** | Dev B | **8** | `DEPLOYMENT.md`: Laravel + MySQL (Docker or PaaS), `API_BASE_URL` / `dart-define`, `php artisan migrate`, storage link; `flutter build apk` / app bundle; env checklist. |
| **88** | **Admin hardening** | Dev A | **6** | Confirm admin-only routes; one high-value add: user search filter, recipe delete confirmation, or analytics summary card from existing endpoints. |
| **89** | **QA matrix + docs** | Dev B | **6** | Test checklist (auth, match, favorites, collections, planner, grocery, voice, admin); fix **P0/P1** bugs; short **system flow** for defense. |

---

## Dependencies & sequencing

1. **Early:** Task **87** (deployment) can run in parallel — aligns API URL for device builds.  
2. **81 + 82:** Planner outputs recipe IDs → grocery merge reuses them (sync API shapes mid-sprint).  
3. **84:** Add DB + `POST` token API before Flutter registration.  
4. **89** in **second half** — stabilize after merges.

**Mid-sprint sync:** agree JSON for week key (`week_start`), grocery `recipe_ids`, push `token` + `platform`.

---

## Definition of Done (shared)

- [ ] No **P0** regressions on login, home, recipe detail.  
- [ ] New/changed endpoints noted in README or minimal OpenAPI.  
- [ ] `dart analyze` clean on touched Flutter files (or documented waivers).  
- [ ] `php artisan migrate` succeeds on fresh DB when new migrations exist.

---

## Optional stretch (if ahead of schedule)

- Monetization placeholder (IAP/ads stub).  
- Smarter meal “suggest” using real recommendation scores.  
- One funnel metric to existing admin pipeline (e.g. `match_recipes` success).

---

## Capacity check

| Dev | Tasks | Hours |
|-----|--------|-------|
| **A** | 80 + 82 + 84 + 86 + 88 | 8 + 6 + 6 + 6 + 6 = **32** |
| **B** | 81 + 83 + 85 + 87 + 89 | 6 + 6 + 6 + 8 + 6 = **32** |
| **Σ** | 10 tasks | **64** |
