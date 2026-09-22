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

## EnemyBase / BT Combat Task Backward-Compatibility Shims (2026-09-19)

**Status: Deliberately kept for now — real current callers, but should be removed once those callers are migrated.**

The EnemyDef/EnemyLibrary data-driven enemy work (see [Combat](combat.md))
introduced two dual-path "old standalone value vs. new EnemyDef-driven
value" branches, each kept only because a specific existing test constructs
an actor without an `EnemyDef` and depends on the old standalone behavior.
Per this repo's no-backward-compat default (pre-release, `main`-only), these
should not become permanent — they're tracked here so they get cut instead
of quietly calcifying:

1. **`EnemyBase.enemy_def` is nullable, not mandatory.** `_setup_health_component`,
   `_setup_ai_components`, `_follow_path`, and `get_active_moodlets` all branch
   on `enemy_def != null`, falling back to whatever was configured directly on
   child nodes (or a bare `5.0` move-speed constant) when it's unset. Exists
   solely because `test_melee_action_params_windup_and_active_hitbox`,
   `test_player_gun_fire_damages_enemy`, and
   `test_enemy_lethal_damage_triggers_death_and_free`
   (`test/suite_equippable_schema_test.gd`) construct a bare `EnemyBase.new()`
   with a hand-configured `HealthComponent`, independent of any archetype.
2. **`BTActionMeleeAttack.use_agent_attack_params`** (`subsystems/ai/tasks/actions/bt_action_melee_attack.gd`)
   is an opt-in flag; when `false` (the default) the task falls back to its
   own `damage`/`attack_range`/`windup_duration`/`cooldown_duration` exports
   instead of the agent's `EnemyDef.attack_params`. Exists solely because
   `test_melee_attack_damages_target` (`test/suite_ai_tasks_test.gd`) drives
   the task with a bare `CharacterBody3D` agent and asserts against those
   exports directly.

**To remove:** migrate the tests above to construct their actors with a real
(or minimal in-memory) `EnemyDef`/`attack_params` instead of hand-configuring
`HealthComponent`/task exports directly, then delete the null/false branches
— making `enemy_def` mandatory on `EnemyBase` and `use_agent_attack_params`
implicit (always-on) — collapsing each pair back down to a single path.

---

## Inventory & Equipment Leftovers (2026-09-20)

Found while reworking the inventory, equipment and storage UI (see [Inventory](inventory.md), [Equipment](equipment.md), [UI](ui.md)). Tracked here so they get cut or finished instead of calcifying.

1. **`EventBus.item_picked_up` is declared but unwired.** `subsystems/autoloads/event_bus.gd` declares it, but nothing emits or connects it; the docs used to describe an inventory-to-HUD flow that never existed. Emit it from the pickup path when something needs it, or delete it from the registry.
2. **`Colonist.equip_item()` / `unequip_item()` and `Equipment.equip_preferring_main_hand()` overwrite a slot without stowing anything or touching inventory.** Only tests call them now: the Player equips through `Equipment.equip_from_inventory` and colonist AI through `stow_and_equip`. Kept because `suite_colonist_combat_test` and `suite_equippable_schema_test` arm colonists with them. Migrate those tests to `Equipment.equip`, then delete the three methods.
3. **`Inventory.transfer_to` keeps a defensive add-back path** (`if unplaced > 0: add(item_id, unplaced)`). It is unreachable while every target's `add` agrees with its `max_addable`, and is kept on purpose so a stricter subclass can never make a transfer swallow items. Remove it if that guarantee is ever enforced by a test.
4. **Orphaned stacks are invisible.** An inventory stack whose `ItemDef` no longer exists (a removed item, an old save) stays in `items` and in saves, but every item list (inventory panel, transfer panel, crate card) skips it, so it cannot be seen, moved or dropped.
5. **The storage transfer panel has no search box.** Large crates need scrolling. Optional; the Storage Options panel already has a search field to reuse.
6. **Known failing tests, not caused by the work above (causes not investigated):** `suite_world_item_test` (9 hauling and pickup tests), `suite_furniture_test` `test_furniture_layer_attaches_bed_component_when_bed_params_present` (`BedParams.rest_rate_per_second` missing), `suite_food_ai_test` `test_find_food_ignores_blacklisted_crate` (fails only when run after other suites). `suite_fetch_equipment_job_test` does not parse (`EquipmentSlotRow.SLOT_DISPLAY_NAMES` moved to `GearText`), and a suite that fails to parse aborts the whole gdUnit run.

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

## Map Editor Shipped Maps in Unit Tests (2026-09-21)

**Status: Open (Progressive migration).**

18 unit tests in `test/suite_map_editor_test.gd` still call `load_map("base")` or `load_map("dev")`, loading shipped maps directly from `res://data/maps/`. All newer suites and Phase 1-9 tests use `test/helpers/sandbox.gd` (`Sandbox.map_id(...)`, `Sandbox.blocky_only_payload(...)`, `Sandbox.heightmap_payload(...)`, and `Sandbox.dispose(...)`) to create and clean up isolated test maps under `res://data/maps/zz_sandbox_*/`.

**To resolve:** Migrate the remaining 18 `load_map("base")` and `load_map("dev")` test cases in `test/suite_map_editor_test.gd` to sandbox fixtures so unit tests remain fully content-agnostic and resilient to changes in shipped map definitions.

---

## Committed Content References Gitignored `res://tmp/` Assets (2026-09-22)

**Status: Open.**

Eight committed `.tres` files under `res://data/items/materials/` and `res://data/furniture/storage/` reference meshes and a texture under `res://tmp/...`, which `tmp/` gitignores (found while auditing the test suite): `coal.tres`, `copper_ore.tres`, `dirt.tres`, `gold_ore.tres`, `iron_ore.tres`, `rock.tres`, `sulfur.tres` (all via one shared `ArrayMesh` at `res://tmp/AAA-save/Polygon-Mega Survival Kit/SM_Stone_01.SM_Stone_01.mesh`), and `storage_crate.tres` (an `ArrayMesh` and a `Texture2D` under `res://tmp/Polygon-Mega Survival Construction/`). The AAA-save mesh exists only in checkouts that happen to still have that scratch download; the two `storage_crate.tres` assets are missing even here. A clean checkout or a fresh git worktree cannot load any of these seven material defs, and `storage_crate.tres` fails everywhere until its assets are restored.

**To resolve:** Move the referenced meshes and textures into `res://assets/` (provenance recorded in `docs/art.md`, per the Layout rule that `assets/` is art-only) and repoint the `ext_resource` paths; for `storage_crate.tres`, first recover or replace the two missing files. Until resolved, do not rely on these defs in a fresh checkout or worktree.

