# Architecture: Tech Debt & Unimplemented Subsystems

Tracking page for known architectural debt, incomplete features, missing schemas, and planned subsystems.

---

## AI Subsystem & LimboAI Behavior Tree Migration

**Status: Complete (Phases 1–5 Implemented, Legacy AI Dropped).**

- **Phase 1**: LimboAI GDExtension module integrated into `addons/limboai/`. Basic BT task suite (`BTActionNavigateTo`, `BTActionPerformWork`, `BTActionWander`, `BTConditionHasTool`, `BTConditionJobStillNeeded`, `BTConditionInGroup`) created.
- **Phase 2**: Fractional job system implemented (`JobInstance`, `WorkerClaim`, multi-worker claims, job blacklisting on `JobBoard`).
- **Phase 3**: Data-driven needs (`NeedDef`, `ColonistNeeds`) and Utility AI brain goal arbitration (`ColonistBrain`) with action commitment inertia (+0.30 bonus) implemented.
- **Phase 4**: Universal behavior trees (`colonist_root.tres`, `bt_generic_work.tres`, `bt_haul_single_trip.tres`, `enemy_swarmer.tres`) and programmatic tree factory (`BTTreeFactory`) created.
- **Phase 5**: Full SaveSystem persistence for `ColonistBrain`, `ColonistNeeds`, `JobBoard`, `JobInstance`, `WorkerClaim`, and LimboAI Blackboard state. Lazy tool retention and cleanup added.
- **Legacy AI Cleanup**: Legacy `ColonistAI` (`subsystems/colonists/colonist_ai.gd`) and procedural `JobLeg` (`data/jobs/job_leg.gd`) state machine methods have been **completely dropped and removed** from the codebase.

---

## Unimplemented Subsystems (Planned)

Combat, Equipment, and Raids have since moved from planned to implemented/in-progress — see
[Combat](combat.md), [Equipment](equipment.md), and [Raids](raids.md) for current status. What
remains genuinely unimplemented:

1. **Energy Subsystem** — no `BreathComponent` anywhere; `StaminaComponent` is a 5-line stub. See [Energy](energy.md).
2. **Permadeath & Memorial Subsystem** — no memorial registry, Day Summary, or Game Over screen. See [Permadeath & Memorial](permadeath-memorial.md).
3. **Loot Subsystem** — **Partially resolved.** `LootTable`, `LootEntry`, `LootRoller` and enemy drop-on-death exist (`data/loot/`, `subsystems/loot/`, `EnemyBase`). Still open: no enemy `.tres` references a `loot_table` yet, so nothing drops in the shipped game; no `LootContainer` or `KeyItemPool`; no mutually exclusive weighted pools. See [Loot](loot.md).
4. **Functional Rooms** — no `functional_counts` state or listeners on `Colony`. See [Functional Rooms](functional-rooms.md).
5. **Debug Console** — `debug/` is empty; no console autoload or commands exist. See [Debug Console](debug-console.md).
6. **Enemy Spawn Selection** — **Partially resolved.** `subsystems/raids/night_raid_controller.gd` now picks its enemy type per spawn via weighted random selection over `GameConfig.enemy_pool` (`Array[RaidSpawnEntry]`, see [Raids](raids.md)), so `EnemyBrawler`/`EnemyShooter` (GDD §5) are reachable through the night raid loop. Still open: `subsystems/maps/map_wiring.gd`'s static spawn-marker path (`wire_enemies`) still holds its own single hardcoded `PackedScene` reference to the swarmer, independent of the new pool — left untouched as a separate concern (authored map spawn points vs. continuous night pacing). Also still open: no day-based gating or wave composition (GDD's encounter templates like "2× Brawler + 1× Shooter") — the pool is flat and unconditioned on `GameState.current_day`.

---

## Furniture Capabilities & Pluggable Architecture

**Status: Complete.**
- `FurnitureDef` capability composition migrated from an ad-hoc if-ladder in `FurnitureLayer` to a static capability factory registry with property introspection.
- `FurnitureCapability` base resource established with virtual `collect_action_options()` hook.
- `ICapabilityComponent` protocol established for automatic per-component state serialization/deserialization.
- `TestParams` removed. `BedParams` added, introducing `BedComponent` and `colonist_bed.tres`.
- Farm plot capability expanded with `FarmPlotParams` (`crop_slots`, `growth_rate_multiplier`, `hydration_mode`).

---

## EnemyBase / BT Combat Task Backward-Compatibility Shims (2026-09-19, updated 2026-09-22)

**Status: Mixed — item 1 has zero remaining callers and is ready to cut; item 2 still has one real caller.**

The EnemyDef/EnemyLibrary data-driven enemy work (see [Combat](combat.md))
introduced two dual-path "old standalone value vs. new EnemyDef-driven
value" branches, each originally kept only because a specific existing test
constructed an actor without an `EnemyDef` and depended on the old
standalone behavior. Per this repo's no-backward-compat default
(pre-release, `main`-only), these should not become permanent:

1. **`EnemyBase.enemy_def` is nullable, not mandatory.** `_setup_health_component`,
   `_setup_ai_components`, `_follow_path`, and `get_active_moodlets` all branch
   on `enemy_def != null`, falling back to whatever was configured directly on
   child nodes (or a bare `5.0` move-speed constant) when it's unset. Originally
   kept for `test_melee_action_params_windup_and_active_hitbox`
   (`test/suite_equippable_schema_test.gd`), `test_player_gun_fire_damages_enemy`,
   and `test_enemy_lethal_damage_triggers_death_and_free` (the latter two moved
   to `test/suite_combat_test.gd`). The 2026-09-22 test-suite remediation (R9)
   migrated all three off bare `EnemyBase.new()` construction — they now
   instantiate a real `SwarmerScene` and duplicate its (non-null) `enemy_def`
   before overriding synthetic stats. **Verified zero remaining test callers**
   of the null-fallback branch (`grep -rn "EnemyBase.new()" test/` shows only
   `suite_map_wiring_test.gd`, which never exercises health/attack setup, and
   5 calls in `suite_ai_tasks_test.gd`, all 5 of which set `enemy.enemy_def`
   explicitly on the next line). This branch can be cut now.
2. **`BTActionMeleeAttack.use_agent_attack_params`** (`subsystems/ai/tasks/actions/bt_action_melee_attack.gd`)
   is an opt-in flag; when `false` (the default) the task falls back to its
   own `damage`/`attack_range`/`windup_duration`/`cooldown_duration` exports
   instead of the agent's `EnemyDef.attack_params`. Still has exactly one real
   caller: `test_melee_attack_damages_target` (`test/suite_ai_tasks_test.gd`)
   drives the task with a bare `CharacterBody3D` agent and asserts against
   those exports directly (a second test in the same file exercises the
   `true` / agent-params path and does not need this branch). Not migrated by
   R9; still needed.

**To remove:** for item 1, delete the null branches in the four methods listed
above and make `enemy_def` mandatory on `EnemyBase` — no test migration
needed, it is already safe. For item 2, first migrate
`test_melee_attack_damages_target` to drive the task through a real (or
minimal in-memory) `EnemyDef.attack_params` instead of the task's own
exports, then delete the `false` branch and make `use_agent_attack_params`
implicit (always-on).

---

## Inventory & Equipment Leftovers (2026-09-20)

Found while reworking the inventory, equipment and storage UI (see [Inventory](inventory.md), [Equipment](equipment.md), [UI](ui.md)). Tracked here so they get cut or finished instead of calcifying.

1. **`EventBus.item_picked_up` is declared but unwired.** `subsystems/autoloads/event_bus.gd` declares it, but nothing emits or connects it; the docs used to describe an inventory-to-HUD flow that never existed. Emit it from the pickup path when something needs it, or delete it from the registry.
2. **`Colonist.equip_item()` / `unequip_item()` and `Equipment.equip_preferring_main_hand()` overwrite a slot without stowing anything or touching inventory.** Only tests call them now: the Player equips through `Equipment.equip_from_inventory` and colonist AI through `stow_and_equip`. Kept because `suite_colonist_combat_test` and `suite_equippable_schema_test` arm colonists with them. Migrate those tests to `Equipment.equip`, then delete the three methods.
3. **`Inventory.transfer_to` keeps a defensive add-back path** (`if unplaced > 0: add(item_id, unplaced)`). It is unreachable while every target's `add` agrees with its `max_addable`, and is kept on purpose so a stricter subclass can never make a transfer swallow items. Remove it if that guarantee is ever enforced by a test.
4. **Orphaned stacks are invisible.** An inventory stack whose `ItemDef` no longer exists (a removed item, an old save) stays in `items` and in saves, but every item list (inventory panel, transfer panel, crate card) skips it, so it cannot be seen, moved or dropped.
5. **The storage transfer panel has no search box.** Large crates need scrolling. Optional; the Storage Options panel already has a search field to reuse.

Item 6 ("Known failing tests," logged 2026-09-20) is removed: the 2026-09-22 test-suite remediation phases R1-R3 fixed all of it — the `suite_world_item_test` hauling/pickup tests, the `suite_furniture_test` bed-params test, the `suite_food_ai_test` order-dependent blacklist test, and the `suite_fetch_equipment_job_test` parse error are all fixed and green, alone and in both run orders.

---

## Map Editor Terrain Undo Decal Marker Stale Limit (2026-09-21)

**Status: Open.**

When undoing a smooth terrain `add_material` operation in the Map Editor (`tools/map_editor/map_editor.gd`), `restore_snapshot` restores prior SDF density samples and block metadata sidecars in `terrain.sqlite`. However, it does not remove the F14 visual Decal markers spawned under `SmoothGrid._marker_root` during the edit (the known stale-marker limit documented in `docs/architecture/mining.md`).

**To resolve:** On `restore_snapshot`, identify any block origins whose material metadata was reverted or removed and prune the corresponding `"origin|id"` keys and Decal instances from `_marker_keys` and `_marker_root`.

---

## Map Editor HUD Block Palette Test Helper (2026-09-21)

**Status: Kept for unit tests.**

`EditorHUD.populate_block_list(defs_by_index: Dictionary, selected_idx: int = -1)` in `tools/map_editor/editor_hud.gd` is retained specifically for test fixtures (`test/suite_map_editor_test.gd`). Production code populates via `populate_block_library(BlockLibrary)`. Kept so unit tests can evaluate palette search, filtering, and cycling with arbitrary in-memory dictionaries without creating temporary `.tres` files on disk.

---

## StructureBrowser Composition over EditorPalettePanel (2026-09-21)

**Status: Open (Deferred follow-up).**

`StructureBrowser` (`tools/map_editor/structure_browser.gd`) was factored out during early editor work and manages category tabs and an ItemList. `EditorPalettePanel` (`tools/map_editor/editor_palette_panel.gd`) was later extracted to centralize cyclic index stepping, query search predicates, and defensive array filtering across HUD palettes. While `StructureBrowser` now shares the unified `EditorPalettePanel.query_matches` predicate, full composition of `StructureBrowser` over `EditorPalettePanel` is deferred.

**To resolve:** Refactor `StructureBrowser` to embed or delegate to `EditorPalettePanel` for category item list management, index navigation, and filtering.

---

## Map Editor Shipped Maps in Unit Tests (2026-09-21, resolved 2026-09-22)

**Status: Resolved (R12B, 2026-09-22 test-suite remediation).**

18 unit tests in `test/suite_map_editor_test.gd` used to call `load_map("base")` or `load_map("dev")`, loading shipped maps directly from `res://data/maps/`. All suites now use `test/helpers/map_editor_sandbox.gd` (imported as `const Sandbox = preload(...)`; `Sandbox.map_id(...)`, `.blocky_only_payload(...)`, `.heightmap_payload(...)`, `.sweep_stale()`, and `.dispose(...)`) to create and clean up isolated test maps under `res://data/maps/zz_sandbox_*/` — note the helper's real filename is `map_editor_sandbox.gd`, not `sandbox.gd` as an earlier version of this entry said. `grep -rn 'load_map("dev")\|load_map("base")' test/` now returns zero hits. `suite_map_editor_test.gd` itself no longer exists — R12D split it into 9 cluster suites (`suite_map_editor_hud`, `_palette`, `_launcher`, `_lifecycle`, `_blocks`, `_terrain`, `_furniture_spawn`, `_save`, `_undo`), all built on the same sandbox.

---

## Map Editor Sandbox Writes Into `res://data/maps` (2026-09-22)

**Status: Accepted, intentional exception to Hard rule 4 — hardened in place, not redirected.**

`test/helpers/map_editor_sandbox.gd` authors throwaway maps under `res://data/maps/zz_sandbox_*/` instead of `user://`, because `MapRepository.MAPS_DIR`, `MapEditor`, and `MapTerrainAuthoring.persist_owned` are hardcoded to `res://data/maps/` in production and a map created any other way would not exercise the real save/load path. The 2026-09-22 test-suite remediation's D1 decision (user-confirmed) was to harden this in place rather than redirect the editor to `user://`: R12A added `Sandbox.sweep_stale()`, called at the start of every map-editor suite, which deletes any `zz_sandbox_*` folder a crashed earlier run left behind, so a leak cannot silently accumulate or contaminate `git status`. This is a deliberate, documented exception — not a violation to fix — and is called out in code at the two lines carrying `# hygiene-ok:` waivers in `test/helpers/map_editor_sandbox.gd`: the `MAPS_DIR` constant (line 9) and the `sweep_stale()` doc comment (line 16). A crash mid-test can still leave a `zz_sandbox_*` folder on disk between runs; `sweep_stale()` and `T4`'s `ls data/maps` check are the guard, not a redirect.

**To resolve:** not open work — this is the accepted design. If the user ever overrides D1 to "redirect," that is R12E (never run): point `MapRepository.MAPS_DIR`, `MapEditor`, `MapTerrainAuthoring`, and `MapLibrary._DIR` at `user://`, after a feasibility spike confirming the map editor tolerates a `user://` map path.

---

## Committed Content References Gitignored `res://tmp/` Assets (2026-09-22)

**Status: Open.**

Eight committed `.tres` files under `res://data/items/materials/` and `res://data/furniture/storage/` reference meshes and a texture under `res://tmp/...`, which `tmp/` gitignores (found while auditing the test suite): `coal.tres`, `copper_ore.tres`, `dirt.tres`, `gold_ore.tres`, `iron_ore.tres`, `rock.tres`, `sulfur.tres` (all via one shared `ArrayMesh` at `res://tmp/AAA-save/Polygon-Mega Survival Kit/SM_Stone_01.SM_Stone_01.mesh`), and `storage_crate.tres` (an `ArrayMesh` and a `Texture2D` under `res://tmp/Polygon-Mega Survival Construction/`). The AAA-save mesh exists only in checkouts that happen to still have that scratch download; the two `storage_crate.tres` assets are missing even here. A clean checkout or a fresh git worktree cannot load any of these seven material defs, and `storage_crate.tres` fails everywhere until its assets are restored.

**To resolve:** Move the referenced meshes and textures into `res://assets/` (provenance recorded in `docs/art.md`, per the Layout rule that `assets/` is art-only) and repoint the `ext_resource` paths; for `storage_crate.tres`, first recover or replace the two missing files. Until resolved, do not rely on these defs in a fresh checkout or worktree.

---

## Behaviour-Tree Resources vs. `BTTreeFactory` (2026-09-22)

**Status: Open — regeneration source undefined.**

The committed `.tres` files under `data/ai/trees/` differ from what `BTTreeFactory` (`subsystems/ai/bt_tree_factory.gd`) produces programmatically: regenerating a tree from the factory drops the `BlackboardPlan` sub-resource and every UID the committed resource carries (verified during the 2026-09-22 test-suite remediation audit, decision D4). No test writes these files: R5 deleted the save half of the old `test_tree_factory_generates_and_saves_trees` (which called `ResourceSaver.save()` against `res://data/ai/trees/`, a Hard rule 4 violation), keeping only in-memory assertions against the factory's output — `suite_ai_tasks_test.gd` now says so directly in a comment ("the committed `data/ai/trees/*.tres` are authored content and are never written by a test"). No bake tool (`tools/bake_bt_trees.gd`, modeled on `tools/bake_voxel_library.gd`) was written, because clobbering the hand-authored trees with factory output is a real risk until it's decided which source wins when the two disagree.

**To resolve:** decide whether the committed `.tres` files or `BTTreeFactory`'s output is authoritative. If the committed files win, document `BTTreeFactory` as dev/prototyping-only and stop treating drift as a bug. If the factory should win, first fix it to preserve `BlackboardPlan` and UIDs, then write a bake tool and re-author the committed trees from it deliberately (not silently).

---

## Test Hygiene Guards (2026-09-22)

**Status: Installed and in active use (R0); one known checker limitation, not yet fixed (see below).**

`tools/check_test_hygiene.sh` greps `test/suite_*_test.gd` and `test/helpers/*.gd` for seven patterns the 2026-09 test audit found recurring: H1 writes into `res://` (Hard rule 4), H2 reads shipped `.tres`/`.sqlite`/`.vox`/`.tscn` content, H3 tautological asserts, H4 wall-clock waits, H5 loads a shipped map by id, H6 a hardcoded `res://data/maps/` path, H7 a test name pinning legacy/back-compat behavior (Hard rule 10). Exit 0 means clean; exit 1 prints every hit. Waive a single line with a trailing `# hygiene-ok: <reason>` comment — the checker skips any line containing that marker. `tools/run_test_orders.sh [forward|reversed|both] [suites...]` runs a suite list through `addons/gdUnit4/runtest.sh` in ascending and/or descending `-a` order to expose cross-suite leaks; `DRY_RUN=1` prints the command instead of running it.

As of this entry, exactly 8 lines across the whole `test/` tree carry a `# hygiene-ok:` waiver: 3 in `test/suite_stream_persistence_test.gd` (asserting the committed `dev` map's real on-disk stream layout — the redirect/copy-branch test genuinely needs a file that exists) plus 1 more in the same file (a synthetic `res://data/maps/missing_map_fixture/...` path that never exists on disk, used only as the missing-source branch), 1 in `test/suite_ai_tasks_test.gd` (`test_perform_work_unassigns_legacy_job_after_cycle` — "legacy Job" names the live `Job` class, not a save-format shim; a false positive on the H7 name pattern), 1 in `test/suite_map_editor_blocks_test.gd` (the eyedropper's bounded production retry loop, not a wall-clock wait), and 2 in `test/helpers/map_editor_sandbox.gd` (the `MAPS_DIR` constant and `sweep_stale()`'s doc comment — see "Map Editor Sandbox Writes Into `res://data/maps`" above for why that sandbox is allowed to author into `res://data/maps`).

**Known checker limitation (unwaived, not a real violation):** the H2/H6 regexes match any occurrence of a `res://data/...` path shape anywhere on a line, including inside `##` doc comments and inside a plain `String` literal that merely looks like a path but is never loaded. As of this entry a whole-tree run is NOT clean (exit 1) for exactly this reason, on four lines in two files: `test/suite_stream_persistence_test.gd` lines 7-8 and 12 (the file-header doc comment, added by R11 alongside that file's real `# hygiene-ok:` waivers, explains in prose the two committed-`dev`-map paths and the synthetic missing-source path — it is explanatory text, not a new load) and `test/suite_structure_data_test.gd` lines 94 and 103 (a file no R0-R17 phase touched; `StructureDef.vox_file_path` is a plain `String` property, and the test round-trips a synthetic id, `"ruin_tower"`, that is not a real shipped structure — `find data -iname '*ruin_tower*'` returns nothing — the value is never `load`ed or `preload`ed). R18 has no file-scope over `test/` (docs-only phase), so these are reported here rather than fixed.

**To resolve:** either make the checker comment-aware (skip lines whose only match is inside a `##`/`#` comment, or require the matched path to appear inside a `load(`/`preload(`/`ResourceLoader.load(` call for H2), or add explicit `# hygiene-ok:` waivers to the four specific lines above the next time a phase has file-scope over `suite_stream_persistence_test.gd` and `suite_structure_data_test.gd`.

---

## Private-Member-Access Tests and Two Left-As-Is Production Constants (2026-09-22)

**Status: Open (LOW severity) — deliberately not touched by the 2026-09-22 test-suite remediation.**

Consolidating several small items the remediation's phases surfaced but did not fix, none individually worth its own entry:

1. **Private-member-access tests** call a `_`-prefixed method or field directly instead of the class's public contract, so they pin an implementation detail the class could otherwise refactor freely:
   - `test/suite_player_interaction_test.gd` reads `player.interactor._current_interactable` directly (two call sites).
   - `test/suite_squad_and_deploy_test.gd` calls `CommandController._calculate_cluster_formation`, `._calculate_line_formation`, sets `._last_calculated_positions`, and calls `._commit_command()` directly — `CommandController`'s public raycast-to-formation-to-`EventBus.deploy_orders_issued` flow (GAP-5 in the original audit) is otherwise untested.
   - `test/suite_colonist_debug_visualizer_test.gd` calls `_visualizer._resolve_colonist_state()`, `._resolve_colonist_job()`, `._resolve_path_info()`, and `._resolve_carried_items()` directly instead of asserting on the visualizer's public billboard/mesh output.
   - **To resolve:** rewrite each to exercise the class's public API and assert on its observable output (the formation markers' transforms, the visualizer's rendered label text, the interactor's public "current target" accessor if one is added), one suite at a time.
2. **`BlockLibrary.LEGACY_BLOCK_ORDER`** (`subsystems/voxel/block_library.gd:39`) is a production fallback sort order for the 13 locked blocks, used by `_get_block_sort_rank` only when a block's `fixed_index` is unset. Left untouched — it is real save-format-relevant behavior, not dead code, and no test currently pins its ordering (only `fixed_index` is tested). **To resolve:** add a test asserting the fallback order for a block with no `fixed_index`, or fold it into `fixed_index` if the two are meant to be the same mechanism.
3. **`VoxelBlockEncoder.YAW_ORTHOS`** (`subsystems/voxel/voxel_block_encoder.gd:23`) is declared but has zero other references anywhere in the codebase (`grep -rn "YAW_ORTHOS" --include="*.gd" .` matches only its own declaration) — genuinely dead. **To resolve:** delete it, or if it documents an invariant worth keeping visible, add a test asserting it matches `BlockDef.YAW_INDICES` (or whatever the mesher's actual yaw-order source is) and reference it from there instead of leaving it orphaned.
4. **The `res://tmp/` asset dependency** described above under "Committed Content References Gitignored `res://tmp/` Assets" is cross-referenced here only — see that entry for detail, not duplicated.

---

## Order-Dependent Leak: `MapWiring.wire_colonists` Poisons `Colony._container` (2026-09-22, resolved same day)

**Status: Resolved. Found and fixed live during R18, after its own full-tree reversed run first found it — this entry originally recorded it as open with a docs-only phase unable to fix it, but the fix turned out to be exactly this entry's own "To resolve" recommendation, so R18 applied it directly rather than leave a known regression undocumented-but-unfixed for a future phase.**

`test_wire_colonists_wires_predicates_and_returns_container` (`test/suite_map_wiring_test.gd`,
added by R15, commit `22806e6`) calls `MapWiring.wire_colonists(map)` twice, which internally
calls `Colony.on_map_wired(container, [])` and sets the autoload's private `_container` field to
`map.get_colonist_container()` — a node that belongs to the test's own `_template_map()` fixture
and is freed (via `auto_free()`) when the test ends. The test restores `Colony.colonists`,
`Colony._pending_colonist_records`, and calls `ColonySandbox.restore()` (which covers the six
map-wiring *predicate/bounds* caches — walkability, stand hint, cell cost, ground query, terrain
predicate, world bounds — but not `_container`, which is a separate field `ColonySandbox` does not
manage), so `Colony._container` is left pointing at a soon-to-be-freed node with nothing to put it
back.

Three OTHER suites each hand-roll their own `_real_container = Colony._container` /
`Colony._container = _real_container` swap-and-restore around their own direct
`Colony.on_map_wired(...)` calls (`test/suite_colony_roster_test.gd`,
`test/suite_colony_management_test.gd`, `test/suite_colonist_namer_test.gd`) — that idiom works
fine on its own, but it captures whatever `Colony._container` happens to be AT THE START of their
own `before_test`, with no way to know that value is already a dangling reference left by an
earlier suite. In alphabetically FORWARD suite order this never surfaces, because all three land
before `suite_map_wiring_test.gd` runs. In REVERSED order, `suite_map_wiring_test.gd` runs first
and poisons `Colony._container`; `suite_colony_roster_test.gd`, `suite_colony_management_test.gd`,
and `suite_colonist_namer_test.gd` (in that execution order) then all fail their very first test
with `Invalid assignment of property or key '_container' with value of type 'previously freed' on
a base object of type 'Node (colony.gd)'` — confirmed via `tools/run_test_orders.sh reversed`
(2026-09-22, R18): 1550/1558 test cases, 45 errors, 3 failures, exit 100. The FORWARD run on the
same tree is fully green (1558/1558, 0 errors, 0 failures) — this is purely an order leak, not a
correctness regression in `MapWiring.wire_colonists` itself.

R15's own T3 order-check only ran its own four modified suites (`suite_blocky_grid_test`,
`suite_smooth_grid_test`, `suite_map_wiring_test`, `suite_save_system_test`) forward and reversed
against EACH OTHER, per the plan's phase-scoped file ownership — it had no reason to include the
three `_container`-touching suites, which its file list never names. Only R18's whole-tree
reversed run (129 suites) surfaces the cross-suite interaction.

**Fix applied:** `ColonySandbox._snapshot_and_reset_map_caches()` (`test/helpers/colony_sandbox.gd`)
now also snapshots `Colony._container`, normalizing a dead reference to `null` on capture
(`is_instance_valid(Colony._container)`, so a freed node can never round-trip forward into a
later suite's `restore()` and crash there the way it crashed `suite_colony_roster_test.gd`'s
`after_test`), and resets `Colony._container = null` for the duration of the sandboxed test, same
as the six predicate/bounds fields. `_restore_map_caches()` puts the normalized value back.
`test_wire_colonists_wires_predicates_and_returns_container` already builds its own local
`ColonySandbox` and calls `.restore()`, so it needed no change — the fix in the shared helper
covers it. The three victim suites' own hand-rolled `_real_container` capture/restore (which
worked in isolation but had no way to know an inherited value was already dead) were removed as
redundant now that the sandbox handles it: `suite_colony_roster_test.gd` and
`suite_colony_management_test.gd` already constructed a `ColonySandbox`, so only their duplicate
manual `_container` lines were deleted; `suite_colonist_namer_test.gd` did not use `ColonySandbox`
at all (a separate hand-rolled `storage_registry` swap plus manual `_container` capture) and was
converted to use it, both fixing the same class of bug at its root for that suite and removing a
second, independent ad-hoc swap-and-restore pattern per AGENTS.md's "extend
`test/helpers/*_fixtures.gd` / `*_sandbox.gd` before hand-rolling a new one."

Verified: `tools/run_test_orders.sh reversed` and `forward` both now report 1558/1558, 0 errors,
0 failures, 0 orphans (confirmed on two independent full runs of each order, after the fix, from a
clean `git status --short data/`). Files changed: `test/helpers/colony_sandbox.gd`,
`test/suite_colony_roster_test.gd`, `test/suite_colony_management_test.gd`,
`test/suite_colonist_namer_test.gd`.

