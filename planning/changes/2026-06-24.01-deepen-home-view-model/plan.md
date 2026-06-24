---
status: draft
date: 2026-06-24
slug: deepen-home-view-model
spec: deepen-home-view-model
pr: null
---

# deepen-home-view-model — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move home-screen command coordination into a deep `HomeViewModel`
behind an intent + `CommandOutcome` interface, with the VM as the primary test
surface.

**Spec:** [`design.md`](./design.md)

**Branch:** `feat/deepen-home-view-model`

**Commit strategy:** Per-task commits.

Work TDD: each task writes the failing test first, then makes it pass. Run
`dart run build_runner build --delete-conflicting-outputs` after touching any
`@riverpod` provider. Final gate is `just lint-ci` (check-only) on a clean,
already-committed tree, then `just test`.

---

### Task 1: Pure `defaultCategoryId` rule

**Files:**
- Create: `lib/domain/default_category.dart`
- Create: `test/domain/default_category_test.dart`

Extract the quick-add default rule as a pure function — the deep, fake-free
core of remembered-category.

- [ ] **Step 1: Write the test (red)**

  `defaultCategoryId(int? stored, List<Category> cats)`: returns `stored` when
  it exists in `cats`; the first category id when `stored` is null or absent;
  `null` when `cats` is empty.

- [ ] **Step 2: Implement (green)**

  Pure function, no Flutter/Drift imports beyond the `Category` type. `flutter
  test test/domain/default_category_test.dart` passes.

- [ ] **Step 3: Commit**

  ```bash
  git add lib/domain/default_category.dart test/domain/default_category_test.dart
  git commit -m "feat(domain): pure defaultCategoryId quick-add rule

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 2: `RememberedCategory` persistence module

**Files:**
- Create: `lib/data/repositories/remembered_category.dart`
- Create: `test/data/remembered_category_test.dart`

Thin module over `SettingsRepository` owning read / write / forget of the
stored id, exposed as a `keepAlive` provider.

- [ ] **Step 1: Write the test (red)**

  Round-trip read/write/forget against a `SettingsRepository(mockPrefs)`.

- [ ] **Step 2: Implement + generate (green)**

  `RememberedCategory(this._settings)` with `read()/write(id)/forget()`;
  `@Riverpod(keepAlive: true) RememberedCategory rememberedCategory(Ref)` over
  `settingsRepositoryProvider`. Run build_runner. Test passes.

- [ ] **Step 3: Commit**

  ```bash
  git add lib/data/repositories/remembered_category.dart lib/data/repositories/remembered_category.g.dart test/data/remembered_category_test.dart
  git commit -m "feat(data): RememberedCategory persistence module

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 3: `CommandOutcome` + deepened `HomeViewModel` intents

**Files:**
- Modify: `lib/ui/home/home_view_model.dart`
- Create: `test/ui/home_view_model_test.dart`

Add `CommandOutcome`, the private `_run` helper, and the coordinating intents.
This is the core of the change — the VM becomes the test surface.

- [ ] **Step 1: Write the VM tests (red)**

  Against a `ProviderContainer` with `appDatabaseProvider` (in-memory
  `NativeDatabase.memory`) + mock prefs. Relocate the `_Throwing*Repo` doubles
  from `home_screen_test.dart` here. Cover: `addTask` remembers on success;
  **failed `addTask` does not remember (M4)**; `deleteCategory` forgets (**M2**);
  `dropTask` within / across / noop-on-stale / collapsed-auto-expand (**H3/H4**);
  `completeTask`→archive; `restoreTask` re-append; `editTask` rename + move;
  `quickAddDefault()`; `failure` outcomes from throwing doubles.

- [ ] **Step 2: Implement + generate (green)**

  Add `enum CommandOutcome { success, failure }` and `_run`. Add intents:
  `dropTask`, `reorderCategories(old,new)`, `addTask` (remembers),
  `deleteCategory` (forgets), `editTask`, `completeTask`, `restoreTask`,
  `quickAddDefault`, plus existing `addCategory`/`updateCategory`/
  `toggleCollapsed`/`purgeExpired`/`clearArchive` returning outcomes. VM reads
  `rememberedCategoryProvider` via `ref.read`; intents read their own
  `state.value`; null snapshot → `success` no-op. Run build_runner. Tests pass.

- [ ] **Step 3: Commit**

  ```bash
  git add lib/ui/home/home_view_model.dart lib/ui/home/home_view_model.g.dart test/ui/home_view_model_test.dart
  git commit -m "feat(home): deepen HomeViewModel with coordinating intents + CommandOutcome

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 4: Thin `_HomeScreenState` to render + dispatch

**Files:**
- Modify: `lib/ui/home/home_screen.dart`
- Modify: `test/ui/home_screen_test.dart`

Move coordination out of the widget; keep only `BuildContext`-bound UI. Migrate
logic assertions down (already covered by Task 3) and keep widget-level cases.

- [ ] **Step 1: Rewire the widget**

  Drop `settings_repository` import + `_lastCategoryId` field + `initState`
  seed. Replace `_onItemReorder`/`_onExpandToggle`/`_addTask`'s coordination
  with calls to VM intents. Add one `outcome → actionFailed SnackBar` mapping;
  remove `_guard`. `_complete`/`_restore` await intents, map outcome, show undo
  toast only on success. Drag callbacks forward raw indices. `quickAddDefault()`
  feeds the dialog. Keep `_showUndoToast`, dialogs, sheets, haptics.

- [ ] **Step 2: Thin the widget tests (green)**

  Remove logic assertions now covered at the VM level (M2/M4/H3/H4). Keep:
  failure → `actionFailed` SnackBar, undo toast floating + auto-dismiss,
  quick-add stays open, Russian plural, header/menu alignment, collapse/expand,
  stream-error message. Move the `_Throwing*Repo` doubles needed only for the
  SnackBar-mapping test (or keep a minimal local one). `flutter test` green.

- [ ] **Step 3: Commit**

  ```bash
  git add lib/ui/home/home_screen.dart test/ui/home_screen_test.dart
  git commit -m "refactor(home): thin _HomeScreenState to render + dispatch

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 5: Architecture promotion + ship bookkeeping

**Files:**
- Create: `architecture/home-coordination.md`
- Modify: `architecture/error-handling.md`
- Modify: `architecture/README.md`
- Modify: `planning/changes/2026-06-24.01-deepen-home-view-model/design.md`

Promote the new truth into `architecture/` in this same PR (project hard rule).

- [ ] **Step 1: Write `home-coordination.md`**

  The deepened VM: coordinating intents, the `CommandOutcome` channel, and the
  remembered-category quick-add default (currently undocumented — shipped in
  change `2026-06-18.06`) incl. the pure `defaultCategoryId` rule.

- [ ] **Step 2: Rewrite `error-handling.md`**

  Replace the `_HomeScreenState._guard` paragraph with the VM-returns-
  `CommandOutcome` / widget-maps-`failure`→SnackBar story. Keep startup / zone /
  stream-error paragraphs.

- [ ] **Step 3: Update README index + ship frontmatter**

  Add `home-coordination.md` to `architecture/README.md`'s capability index.
  Set the design's frontmatter `status: shipped`, fill `pr` + `outcome`. Run
  `just index` to confirm the listing renders.

- [ ] **Step 4: Final gate + commit**

  ```bash
  just lint-ci && just test
  git add architecture/ planning/changes/2026-06-24.01-deepen-home-view-model/
  git commit -m "docs(architecture): promote home-coordination + outcome error handling

  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  ```
