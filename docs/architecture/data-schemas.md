# Data Schemas

## `data/game_config.tres` (Resource: `game_config.gd`)

| Field | Type | Description |
|---|---|---|
| `gravity` | `float` | 9.8 (Y). |
| `target_fps` | `int` | 60 (floor 30). |
| `loop_length_minutes` | `float` | 30 (1 in-game day). |
| `max_enemies_on_screen` | `int` | 24. |

## `data/maps/<id>/map_def.tres` (Resource: `map_def.gd`)

One `MapDef` per loadable map. Scanned from `data/maps/*/map_def.tres` by `MapLibrary`. The catalog entry that picks which scene to load and where actors spawn; the `.tscn` is the runtime contract. **`id` must equal the folder name** — `SceneManager` derives the runtime sqlite path from it. Maps are hybrid: per-map `.tscn` for visual layout/nodes (terrain stream + furniture markers), this `.tres` for metadata + spawn config. Authored via the Voxel Paint "+ New Map" button (see `docs/HOWTO-create-a-map.md`).

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Map id; **must match the folder name** (`data/maps/<id>/`). Drives the runtime sqlite path. |
| `display_name` | `String` | Player-facing name (world map list). |
| `description` | `String` | One-liner shown under the name in the world map. |
| `scene_path` | `String` | The `Map` scene to instantiate. POIs → per-map `res://data/maps/<id>/map.tscn`; base → `res://data/maps/base/map.tscn`. |
| `map_type` | `MapType` enum | `BASE` / `POI` / `BUILDING` / `TOWN`. `POI` maps are auto-discovered by the New Game flow (main menu) and listed in the world map. |
| `player_spawn` | `Vector3` | Fallback player spawn (default `(0, 5, 0)`). Overridden by a `SpawnPoints/PlayerSpawn` Marker3D if present. |
| `enemy_spawns` | `Array[Dictionary]` | `[{ "pos": Vector3, "count": int }]`. Overridden by `SpawnPoints/EnemySpawn_*` markers. |
| `unlock_condition` | `String` | *(Unused — reserved for gated discovery.)* |
| `difficulty` | `int` | 1–N; shown in the world map row. |

## `data/characters/<type>.tres` (Resource: `character_def.gd`) — *(planned)*

> **Status: planned, not yet implemented.** `data/characters/` is empty; `character_def.gd` and the `CharacterType` enum do not exist. The intended union schema (GDD §6) is `display_name` / `character_type` / `max_hp` / `max_durability` / `base_move_speed` / `sprint_multiplier` / `stamina_drain_rate` / `breath_*` costs + regen / `detection_range` / `damage` / `attack_range`. `player.gd` still sources its stats from `@export` vars (TODO: source from a CharacterDef once it lands). The only actor def implemented today is `ColonistDef` (below).

## `data/colonists/<id>.tres` (Resource: `colonist_def.gd`) — `ColonistDef`

The implemented actor definition (e.g. `default_colonist.tres`). `ColonistDef extends Resource`.

| Field | Type | Description |
|---|---|---|
| `display_name` | `String` | `[export default "Colonist"]` UI label. |
| `max_hp` | `int` | `[export default 100]` |
| `default_raid_stance` | `int` | `[export default 0]` Stored as int (`RaidStance` enum deferred). |
| `base_move_speed` | `float` | `[export default 3.5]` |
| `sprint_multiplier` | `float` | `[export default 1.5]` |
| `stamina_drain_rate` | `float` | `[export default 1.0]` |
| `breath_costs` | `Dictionary` | `[export]` Per-action Breath costs keyed by name (default `{"sprint": 1.0, "jump": 1.0}`). |
| `starting_skills` | `Dictionary` | `[export]` Starting skill xp/level per labor (default mining + farming at L1). |
| `default_labor_priorities` | `Dictionary` | `[export]` Default labor-priority weights per labor (ships `construction`/`crafting`/`hauling`/`harvesting` at 1). |

## `data/labors/<id>.tres` (Resource: `labor_def.gd`) — `LaborDef`

The canonical declaration of which labor ids exist. `LaborDef extends Resource`. Labors are referenced elsewhere by their String `id` — a `Colonist`'s `labor_priorities` Dict and a `Job`'s `labor_id` — so these resources are the single source of truth for labor identity + display metadata. Eight instances ship today: `construction`, `crafting`, `hauling`, `harvesting`, `farming`, `mechanics`, `mining` (consumed by the player's dig action; no colonist mining job yet), `smelting` (Repair/Cooking post-MVP; mechanics/smelting have no job defs yet). They are inert data for now — there is no registry autoload; the colony-management labors tab scans them for the priority matrix; future skill gates / UI load them by path.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | `[export]` The labor id (e.g. `"construction"`) — the key everything else references. |
| `display_name` | `String` | `[export]` UI label (e.g. `"Construction"`). |
| `description` | `String` | `[export default ""]` Short blurb, unused in MVP UI. |

## `data/jobs/<id>.tres` (Resource: `job_def.gd`) — `JobDef`

Reusable template for one kind of colonist work — one subclass per Labor, authored as a `.tres` via `script_class` (`construction.tres` → `ConstructionJobDef`, `hauling.tres` → `HaulingJobDef`). Unlike the pure-data defs above, a `JobDef` also carries **leg behaviour**: a job is a sequence of `JobLeg`s (walk-to → act) that `ColonistAI` walks. A `Job` instance holds a `def` back-ref (like `Furniture.def`) plus the per-placement binding (which blueprint, where) and the multi-assign claim bookkeeping. This mirrors the behaviour-bearing Resource precedent (`GameAction`, `Condition`). The behaviour lives here, not on the Furniture, because it depends on Job parameters the Furniture doesn't know (e.g. a craft job's duration = `recipe.base_time × quantity`). See [Colonists](colonists.md).

| Field | Type | Description |
|---|---|---|
| `id` | `String` | `[export]` Identifies this template (e.g. `"construction"`, `"hauling"`). |
| `display_name` | `String` | `[export]` Job Log / UI label. |
| `labor_id` | `String` | `[export]` A `LaborDef.id`; gates `JobBoard.get_best_job_for`'s filter. |
| `max_assignees` | `int` | `[export default 1]` Max colonists that may join one Job of this def at once. 1 for single-colonist labors (construction); >1 lets a job be divvied (hauling). |
| `conditions` | `Array[Condition]` | `[export default []]` Actor requirements (skill/item gates — e.g. `MinSkillCondition`), evaluated hot every poll by `get_best_job_for` + `try_assign`. Author actor-inherent facts only; world-checkable facts belong in the virtual methods below. See [Jobs](jobs.md). |

**Virtual methods** (overridden per Labor; `ColonistAI` drives them in its leg loop):
- `get_next_leg(actor: Node, job: Job) -> JobLeg` — the next leg for this colonist, or `null` when it has no further work (called at claim and after each leg). Base default `null`.
- `begin(actor: Node, leg: JobLeg, job: Job) -> float` — this leg's work duration in seconds (`0` = instant → `complete` fires the same tick). Divide by `skill_set.get_multiplier(labor_id)` for skill-scaled work. Base default `0.0`.
- `complete(actor: Node, leg: JobLeg, job: Job) -> void` — apply this leg's effect when its duration elapses. Base default no-op.
- `on_end(success: bool, actor: Node, leg: JobLeg, job: Job, elapsed: float) -> void` — cleanup when a colonist leaves the job (finish or abort). Base default no-op.
- `is_available(job: Job) -> bool` — labor-specific acceptability gate (combined with the slot count on `Job.is_available`). Base default `true`.
- `should_close(job: Job) -> bool` — whether the job is dead (leave the board), independent of claimability so a temporarily-unclaimable job can stay registered. Base default `not is_available`.
- `job_complete(job: Job) -> bool` — whether a null `get_next_leg` is a clean finish (success/XP) versus a stall. Base default `true`.
- `meets_requirements(actor: Node, job: Job) -> bool` — every `conditions` entry `is_met(actor, job.target_node)`, fresh each call. Base default `true` (empty conditions).

**`JobLeg`** (`data/jobs/job_leg.gd`, `RefCounted`) — one leg of a job's walk→act sequence; pure routing data. `location: Vector3` (walk-target), `target_node: Node` (the per-leg node — crate/blueprint; weak, freed-detectable), `kind: int` (opaque, def-owned discriminator, e.g. `HaulingJobDef.FETCH`/`DELIVER`).

**Subclass — `ConstructionJobDef`** (`data/jobs/construction_job_def.gd`): construction labor, a **one-leg job** (`max_assignees=1`). `get_next_leg` returns the blueprint leg once then `null`; `begin` returns `BuildLibrary.get_def(bp.target_def_id).build_time / skill_set.get_multiplier(labor_id)` (the bare `build_time` for a non-Colonist actor; 0 if not a `Blueprint`/unknown def); `complete` resets `bp.work_done = 0` and calls `bp.complete(actor)`; `on_end(false)` persists `bp.work_done = elapsed` so a later attempt resumes; `is_available` = the blueprint still exists. Headless twin of the player's `BuildAction` (no gauge / mouse unlock / `set_busy`); skill-scaled (Stamina factor deferred).

**Subclass — `HaulingJobDef`** (`data/jobs/hauling_job_def.gd`): hauling labor, a **multi-leg, multi-colonist job** (`max_assignees=3`). Targets a **MaterialSink** (`subsystems/furniture/material_sink.gd` — the duck-typed `needed_item_ids`/`remaining_need`/`deposit_from`/`has_complete_materials` contract; `Blueprint` is the implementer today). Each hauler independently loops FETCH (`crate.transfer_to(colonist.inventory, …)` per still-needed item, read via `sink.needed_item_ids`/`remaining_need`) → DELIVER (`sink.deposit_from(actor)`) until `has_complete_materials()`; phase is derived from carry state, legs are instant. `get_next_leg`: sink gone/satisfied → `null`; carrying a needed material → DELIVER; no `remaining_capacity()` (carried tool / orphan items clogging it) → `null` — self-heals, since `on_end` dumps the surplus to a crate and the next claim retries clean; else FETCH from `StorageRegistry.find_source`, or `null` if no source. `on_end` returns surplus to `StorageRegistry.nearest_crate` **except tool-tagged items** (`ItemDef.tags` — a carried tool stays with the colonist). `is_available` = sink valid + unsatisfied + a crate holds a needed material. Haulers divvy through the sink's shared deposit counter (no per-colonist slices); the DELIVER that crosses the threshold emits the sink's materials-ready signal (`blueprint_materials_ready` for blueprints) → `Colony` spawns the follow-on job.

## `data/energy_config.tres` (Resource: `energy_config.gd`) — *(planned)*

> **Status: planned — `energy_config.gd`/`.tres` do not exist yet.** Field table below is the intended schema (Energy subsystem, GDD §17).

Global Energy values (shared across all characters). Per-character rates (Stamina drain, Breath costs) live in `data/characters/`.

| Field | Type | Description |
|---|---|---|
| `work_threshold` | `float` | 0.45 — Stamina below this triggers Tired band (work penalty). |
| `move_threshold` | `float` | 0.25 — Stamina below this triggers Exhausted band (move penalty too). |
| `collapse_threshold` | `float` | 0.0 — Stamina at this triggers Collapsed band. |
| `work_floor` | `float` | 0.6 — minimum work-speed multiplier (at collapse). |
| `move_floor` | `float` | 0.4 — minimum move-speed multiplier (at collapse). |
| `stamina_work_multiplier` | `float` | 2.0 — drain multiplier while `working == true`. |
| `sprint_gate` | `float` | 0.20 — Breath below this blocks sprint. |

## `data/blocks/<type>.tres` (Resource: `block_def.gd`)

`BlockDef` `extends BuildableDef` — voxel blocks. Inherits `id` / `display_name` / `icon` / `hp` / `mesh` / `texture` / `texture_variation` / `material_cost` / `unlocked_by_default` from `BuildableDef`. The string id is also referred to as "block_id" throughout the voxel subsystem (`BlockyGrid`, `BlockLibrary`).

| Field | Type | Description |
|---|---|---|
| `is_terrain` | `bool` | `[export default false]` BlockDef's own field. True for the indestructible terrain block (forced to voxel-tool library index 1 by `BlockLibrary`). |
| `id` | `String` | *(inherited)* e.g. `"wood"`, `"scrap"`, `"stone"`. |
| `hp` | `int` | *(inherited)* Block HP (50/100/300/600/1200). |
| `mesh` | `Mesh` | *(inherited)* Blocky-mode mesh (unit cube). |
| `material_cost` | `Array[ItemAmount]` | *(inherited)* Materials consumed when building (see `ItemAmount`). |

## `data/terrain/<id>.tres` (Resource: `terrain_gen_def.gd`) — `TerrainGenDef`

Dual-voxel natural-terrain generator params (conversion D2/D4). A `MapDef.terrain_gen` pointing at one of these opts a map into smooth terrain; **null = no smooth grid at all** (the map's `SmoothGrid` frees itself). Fields: `id`, `display_name`, `noise_seed`, `noise_frequency`, `height_start`, `height_range` (1:1 with `VoxelGeneratorNoise2D`, F8-verified names), and `max_walk_slope_deg` (the D4 slope gate, <= 45, consumed in Phase 3). `SceneManager` injects the def into the `SmoothGrid` before the map enters the tree.

## `data/terrain/materials/<id>.tres` (Resource: `terrain_material_def.gd`) — `TerrainMaterialDef`

Identity/stats for a natural material. F8 verdict: `VoxelMesherTransvoxel` has **no material API** in this build — voxel values are pure SDF density, so there is deliberately **no mesh/material reference** here (the terrain has one fixed visual appearance). Fields: `id`, `display_name`, `hardness` (relative dig-effort multiplier for the mining dig action), and `yields: Array[ItemAmount]` (what one completed dig drops into the digger's inventory — v1 caveat: every dig reports the map's `default_material`, so yields are effectively per-map until real material representation lands).

## `data/mining/dig_tool.tres` (Resource: `dig_tool_params.gd`) — `DigToolParams`

Stats for the mining dig action (Phase 5). Fields: `work_time` (seconds before hardness/skill scaling — `DigAction` multiplies by the target material's hardness, divides by the actor's mining skill multiplier) and `carve_radius` (the carved sphere's radius; also the ghost sphere's — the preview shows exactly what the carve removes; fixed size in v1, owner decision). Preloaded as `BuildLibrary.DIG_TOOL` and handed to `DigAction.begin(...)` by whatever triggers the dig — a future equipped tool item references (or overrides) the same bundle so the build-menu tool and an LMB tool-equip path share one code path.

## `data/buildables/<id>.tres` (Resource: `buildable_def.gd`)

Base `BuildableDef` — player-placed objects not on the voxel grid (e.g. `pole`). Also the parent class of `BlockDef` and `FurnitureDef`, which is where `id` / `display_name` / `icon` / `hp` / `mesh` / `texture` / `texture_variation` / `material_cost` / `unlocked_by_default` are inherited from.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Unique buildable id (e.g. `"pole"`, `"workbench"`, `"wood"`). Catalog key for `BuildLibrary`. |
| `display_name` | `String` | UI label. `Furniture.label` exposes this to the interaction menu via a getter. |
| `icon` | `Texture2D` | UI icon for the build menu (nullable; entries render without it). Inherited by `BlockDef` and `FurnitureDef`. |
| `hp` | `int` | Durability-before-HP buffer (GDD §6.11). |
| `mesh` | `Mesh` | Preview/placement mesh; for voxel blocks MUST occupy `(0,0,0)→(1,1,1)`. |
| `texture` | `Texture2D` | Albedo texture. `BlockLibrary` builds a `StandardMaterial3D` from this (no separate material `.tres` per type); the furniture authoring path does the same inline. |
| `texture_variation` | `bool` | `[export default false]` Block-only: opts into a per-block UV/brightness randomization shader so repeating textures don't tile visibly (handled in `BlockLibrary`). |
| `material_cost` | `Array[ItemAmount]` | Materials consumed to build (each entry = an `ItemDef` + count; see `ItemAmount`). Enforced by the blueprint deposit flow (`BlueprintPlacementStrategy`); the `InstantPlacementStrategy` debug fallback still defers it. |
| `build_time` | `float` | `[export default 0.0]` Seconds of WORK for a construction Job / player `BuildAction` (divided by the builder's skill multiplier). |
| `unlocked_by_default` | `bool` | Available without earning an unlock this run; seeded by `BuildLibrary`. |

_(No cost-helper methods — `material_cost` is read directly as an `Array[ItemAmount]`.)_

## `data/furniture/<id>.tres` (Resource: `furniture_def.gd`)

`FurnitureDef` `extends BuildableDef` — free-standing buildables (Workbench, Growing Trough, Storage Crate, Clinic Bed, etc.). Inherits all `BuildableDef` fields. Partial (C1) — see [Actions & Interaction](actions.md) and [Build](build.md). Eight defs ship today (workbench, instant_workbench, storage_crate, growing_trough, shelf1, tree1, wood_block_dispenser, test_block_furniture_with_interaction).

> **Workbench** (`workbench.tres`) — `dimensions = Vector3i(2, 1, 1)`, `unlocked_by_default = true`, `build_time = 10.0`, a plank `material_cost`, plus `crafting_params` (board + axe recipes). It is the colonist sprint's build-job proof target: placing its blueprint is what produces the construction Job a colonist walks to (see [Colonists](colonists.md)).

| Field | Type | Description |
|---|---|---|
| `dimensions` | `Vector3i` | `[export default ONE]` Cell-box the item occupies: x=width, y=height, z=depth (GDD §7.2). Rotation (R) swaps x/z; even-sized x or z shift the placement pivot 0.5m (GDD §7.4). |
| `action_options` | `Array[ActionOption]` | `[export default []]` Interaction options offered on E-press. Each entry is an `ActionOption` `.tres` (see below). Empty (default) means non-interactable — `FurnitureLayer` attaches no `InteractionComponent`. |
| `test_params` | `TestParams` | `[export, nullable]` Composition-pattern placeholder for capability-specific parameters. Null = no capability data. See "FurnitureDef capability parameters" below. |
| `item_dispenser_params` | `ItemDispenserParams` | `[export, nullable]` Capability sub-resource consumed by `GiveItemAction` (the items it dispenses, as `Array[ItemAmount]`). Schema in `data/capability_params/`. |
| `storage_params` | `StorageParams` | `[export, nullable]` Capability sub-resource consumed by `StorageInventory` (its `capacity`, default 100.0). Schema in `data/capability_params/`. |
| `crafting_params` | `CraftingParams` | `[export, nullable]` Capability sub-resource: the station's `recipes: Array[RecipeDef]`. Non-null → FurnitureLayer attaches a `CraftingStation` child. Schema in `data/capability_params/`; recipes in `data/recipes/`. |
| `harvest_params` | `HarvestParams` | `[export, nullable]` Capability sub-resource: the node's `yields`, `work_time`, and `respawn_time`. Non-null → FurnitureLayer attaches a `Harvestable` child component. Schema in `data/capability_params/`. |
| `farm_plot_params` | `FarmPlotParams` | `[export, nullable]` Capability sub-resource: the plot's `allowed_crops`. Non-null → FurnitureLayer attaches a `Growable` child component (the farm-plot lifecycle). Schema at the bottom of this page; see [Farming](farming.md). |

> **FurnitureDef capability parameters** *(built: `crafting_params`, `storage_params`, `harvest_params`; `test_params` is not yet read by any GameAction)*
>
> When two furniture defs differ only in parameters a `GameAction` reads (e.g. a Workbench vs Workbench-T2 differing in craft speed and max recipe tier), those parameters live on **nullable sub-resources referenced from `FurnitureDef`**, not on the def itself. The pattern: each capability gets a small `Resource` subclass (`CraftingParams`, `StorageParams`, …) exposed as a nullable `@export` on `FurnitureDef`; a placed furniture reads it via `def.crafting` (null if absent). Param schemas live in `data/capability_params/`; `test_params` is the seed of this pattern.
>
> **Why this shape:**
> - **Over `CrafterDef extends FurnitureDef`** — single inheritance dead-ends when a station needs two capabilities (a Workbench that crafts *and* stores ingredients). Composition composes.
> - **Over a flat `params: Dictionary`** on the base — loses typing, inspector ergonomics, and discoverability (a `Dictionary` field is a key-value table of `Variant`; typos like `work_sped` fail silently at runtime, and the UI can't show a tier badge without knowing the magic key). Typed sub-resources give autocompleteable, named fields per capability.
> - **Chosen for the multi-capability case specifically.** For a single capability on a single furniture type, a `CrafterDef` subclass would also be fine; composition wins once combinations are plausible (Workbench, Clinic Bed, Storage Crate per GDD §7.9–§7.11).
>
> **Escape hatch:** a `params: Dictionary` on the base `FurnitureDef` remains valid for genuinely one-off, action-local values that no other system will ever read (e.g. a signal fire's smoke color). Typed, named, cross-consumer data goes on a sub-resource; truly bespoke single-action data goes in the dict.


### `data/capability_params/harvest_params.gd` (Resource: `HarvestParams`)

Capability sub-resource for harvestable furniture (trees, resources).

| Field | Type | Description |
|---|---|---|
| `yields` | `Array[ItemAmount]` | List of items and counts produced when harvested. |
| `work_time` | `float` | Base work duration in seconds (default 4.0). Scaled by actor harvesting skill multiplier. |
| `respawn_time` | `float` | Respawn interval in seconds (default 0.0 = permanent removal). |
| `required_tool_tag` | `String` | Optional tag for required equipment (default empty). |

## `data/actions/<id>.tres` (Resource: `game_action.gd`)

One `.tres` per concrete `GameAction` — "what happens" when the player picks the option. Subclasses override `execute(actor, target)`. Thirteen concrete subclasses ship (each in `data/actions/`): `PrintAction` (smoke test), `BuildAction`, `InstantBuildAction`, `AddMaterialsAction`, `GiveItemAction`, `OpenStorageAction`, `OpenCraftingAction`, `CraftAction`, `HarvestAction`, `ToggleHarvestAction`, `FarmManualAction`, `InspectCropAction`, `SelectCropAction`. See [Actions & Interaction](actions.md).

| Field | Type | Description |
|---|---|---|
| `label` | `String` | `[export]` Button text shown in the interaction menu. |

**Virtual method:** `execute(actor: Node, target: Node) -> void` — override in a subclass. `actor` is the player; `target` is the interactable node.

## Condition resources (Resource: `condition.gd`)

`Condition` `extends Resource` — gates an `ActionOption`. One `.tres` per condition instance. Composites (`AnyOf`/`AllOf`/`NotCondition`) live in `subsystems/actions/`; leaf conditions live in `data/conditions/` (`MinSkillCondition`, `HasItemCondition`, `CanCarryDispensedItems`, plus the authored `true.tres`/`false.tres`). See [Actions & Interaction](actions.md).

| Class | File | Fields | Semantics |
|---|---|---|---|
| `Condition` (base) | `subsystems/actions/condition.gd` | — | Virtual `is_met(actor, target) -> bool` (default `true`). |
| `AnyOf` | `subsystems/actions/any_of.gd` | `conditions: Array[Condition]` | true if **any** child `is_met`. |
| `AllOf` | `subsystems/actions/all_of.gd` | `conditions: Array[Condition]` | true only if **all** children `is_met` (redundant inside an option, which already ANDs). |
| `NotCondition` | `subsystems/actions/not.gd` | `condition: Condition` | Inverts a single child. |
| `MinSkillCondition` | `data/conditions/min_skill_condition.gd` | `skill_id: String`, `min_level: int` | Actor's skill level gate (`actor.skill_set.meets_requirement`). |
| `HasItemCondition` | `data/conditions/has_item_condition.gd` | `item_id` XOR `item_tag`, `count: int` | Actor carries N of an item (by id or tag). |

## `data/action_options/<id>.tres` (Resource: `action_option.gd`)

One `.tres` per `ActionOption` — one row in the interaction menu. Binds a `GameAction` to its gating `Condition`s. Ten ship today: `build_action_option`, `instant_build_action_option`, `add_materials_action_option`, `give_item_action_option`, `open_storage_action_option`, `open_crafting_action_option`, `toggle_harvest_action_option`, `inspect_crop_action_option`, `select_crop_action_option`, `test_action_option`. See [Actions & Interaction](actions.md); authoring walkthrough: `docs/HOWTO-author-interactions.md`.

| Field | Type | Description |
|---|---|---|
| `action` | `GameAction` | `[export]` The action to execute when the button is pressed. |
| `conditions` | `Array[Condition]` | `[export default []]` Gates the option. All must be met for the button to be enabled. |

**Method:** `is_available(actor: Node, target: Node) -> bool` — returns `false` on the first failing condition; `true` if empty. Drives each button's `disabled` state.

## `data/raid_curve.tres` (Resource: `raid_curve.gd`) — *(planned)*

> **Status: planned — `raid_curve.gd`/`.tres` do not exist yet** (Raids subsystem). Intended schema below.

Array of `{day_threshold, waves, enemies_per_wave, shooter_percent}` rows. See GDD §17 Raids for values.

## `data/items/<id>.tres` (Resource: `item_def.gd`)

One `ItemDef` per item type. The **canonical item identity is the `id` field** (e.g. `"wood_block"`) — what `ItemDB` keys by, inventories store, and `material_cost` references. The `.tres` filename is just the file location. Scanned at startup by the `ItemDB` autoload.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Canonical item identity (e.g. `"wood_block"`, `"axe"`). Keyed by `ItemDB`; the dict key in inventories and in blueprint `_given` material progress. |
| `weight` | `float` | Weight per unit (kg). Used by `Inventory` for capacity enforcement. Author tools low-weight so one doesn't clog carry capacity. |
| `icon` | `Texture2D` | UI icon (nullable). |
| `tags` | `Array[String]` | `[export default []]` Loose categorization (e.g. `axe.tres`: `["tool", "axe"]`). Read via `Inventory.has_item_tag` and `HasItemCondition`; the `"tool"` tag exempts an item from hauling's surplus dump (carried tools stay with the colonist). |

## `data/items/item_amount.gd` (Resource: `ItemAmount`)

A counted item reference — the element type of `BuildableDef.material_cost` (and any other "N of this item" list).

| Field | Type | Description |
|---|---|---|
| `item_def` | `ItemDef` | Direct reference to the item definition (read `.id` for the identity). |
| `count` | `int` | `[export default 1]` How many of the item. |

## `data/loot/<table>.tres` (Resource: `loot_table.gd`) — *(planned)*

> **Status: planned — `data/loot/` is empty; `loot_table.gd`/`loot_entry.gd` do not exist yet** (Loot subsystem). Intended schema below.

One per container type: `standard.tres` (Zones A/B), `deep.tres` (Zone C). Each table is an array of `LootEntry` resources (see `loot_entry.gd`). See GDD §17 "Loot tables" for the MVP values.

| Field | Type | Description |
|---|---|---|
| `table_id` | `String` | `"standard"` or `"deep"`. |
| `entries` | `Array[LootEntry]` | One per rollable item. See below. |

**LootEntry** (`loot_entry.gd extends Resource`) — one row of a loot table:

| Field | Type | Description |
|---|---|---|
| `item_id` | `String` | What this entry rolls (e.g. `"scrap"`, `"components"`, `"key_item_pending"`). |
| `min_count` | `int` | Minimum stack if the roll succeeds. |
| `max_count` | `int` | Maximum stack if the roll succeeds. |
| `drop_chance` | `float` | 0.0–1.0 probability per container roll. `1.0` = "always included". |

**Standard container values** (GDD §17): scrap 20–50 (1.0), components 5–15 (0.7), fuel 5–15 (0.4), med_supplies 1–3 (0.25), key_item_pending — — (0.05).
**Deep container values**: scrap 40–90 (1.0), components 10–25 (0.85), fuel 10–20 (0.55), med_supplies 2–5 (0.40), key_item_pending — — (0.20).

## `data/loot/key_items.tres` (Resource: `key_item_pool_def.gd`) — *(planned)*

> **Status: planned — `key_item_pool_def.gd`/`key_item_def.gd` do not exist yet.** Intended schema below.

The Key Item pool. Each Key Item drops at most once per playthrough (enforced by `KeyItemPool.found` on the Colony autoload). See GDD §17 "Key Item Table".

| Field | Type | Description |
|---|---|---|
| `items` | `Array[KeyItemDef]` | The 7 MVP Key Items. See below. |

**KeyItemDef** (`key_item_def.gd extends Resource`):

| Field | Type | Description |
|---|---|---|
| `item_id` | `String` | e.g. `"radio_transceiver_unit"`. |
| `display_name` | `String` | UI label. |
| `upgrade_target` | `String` | The T2 base upgrade this item gates (e.g. `"command_center_t2"`). |

**MVP Key Items** (GDD §17): Radio Transceiver Unit (Command Center T2), Portable Generator (Workshop T2), Water Pump Motor (Farm T2), Medical Fridge Unit (Infirmary T2), Heavy Jack Lift (Garage T2), Insulation Panels (Living Quarters T2), Welding Gas Cylinders (Defenses T2).

## `data/skills/skills.tres` (Resource: `skill_def_list.gd`)

Global skill definitions: the 8 shipped skills, their Labor mappings, use-curves, and per-level work-speed multipliers. Loaded once (preloaded by `SkillSet`) and shared by all `SkillSet` components. See [Skills](skills.md).

| Field | Type | Description |
|---|---|---|
| `skills` | `Array[SkillDef]` | The 8 skills. See below. |

**SkillDef** (`skill_def.gd extends Resource`) — one skill:

| Field | Type | Description |
|---|---|---|
| `skill_id` | `String` | `"medical"`, `"mechanical"`, `"construction"`, `"crafting"`, `"combat"`, `"farming"`, `"tree_chopping"`. |
| `display_name` | `String` | UI label (medical/combat/tree_chopping ship without one). |
| `labor` | `String` | The LaborDef.id this skill governs. Shipped mappings: `construction`/`crafting`/`mechanical`/`farming` → their same-named Labors; medical/combat/tree_chopping ship `""` (action-based). A Labor with no governing skill (hauling, harvesting) reads multiplier 1.0. |
| `multipliers` | `Array[float]` | Work-speed multiplier per level, index 0–4 = L1–L5. Default `[1.0, 1.2, 1.4, 1.7, 2.0]`. |
| `use_curve` | `Array[int]` | Cumulative successful uses required to reach each level, index 0–3 = L2–L5. Default `[20, 50, 100, 200]`. |

**MVP skills** (GDD §6.3): Medical (Clinic Bed), Mechanical (Vehicle Lift), Construction (build/repair blocks), Crafting (Workbench + Forge), Combat (raids/expeditions), Farming (Growing Trough — progression tracked; its Labor arrives with the farming jobs).

## `data/recipes/<id>.tres` (Resource: `recipe_def.gd`)

> **Status: built — `RecipeDef` + `CraftingParams`** (Crafting subsystem, GDD §7.9; see [Crafting](crafting.md)). Shipped recipes: `planks.tres` (1 wood_block → 4 plank) and `axe.tres` (2 plank + 1 stone_block → 1 axe) in `data/recipes/`, plus `wooden_board.tres` (3 plank → 1 wooden_board) in `data/crafting/` — all gated L1 Crafting. The workbench offers wooden_board + axe (planks is not referenced by any station yet). The Forge's smelting recipes land with the Forge furniture + smelting skill.

One `RecipeDef` resource per recipe, referenced from the station furniture def's `crafting_params` sub-resource (`CraftingParams.recipes: Array[RecipeDef]`, `data/capability_params/crafting_params.gd`) — not a per-station RecipeList (superseded: the station *is* the furniture def, so no `station_id` matching is needed).

**RecipeDef** (`data/crafting/recipe_def.gd extends Resource`) — one craftable output:

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Unique; e.g. `"planks"`, later `"clinic_bed"`, `"knife"`, `"bullet"`, `"smelt_metal"`. |
| `display_name` | `String` | Craft panel + log label (`label()` falls back to `id`). |
| `inputs` | `Array[ItemAmount]` | Consumed per craft (hauled to the station through the MaterialSink contract). |
| `outputs` | `Array[ItemAmount]` | Produced per craft (to the crafter's carry, overflow to storage). Multi-output supported. |
| `base_time` | `float` | Base craft seconds; CraftingJobDef divides by the crafter's skill multiplier (Stamina factor deferred). |
| `conditions` | `Array[Condition]` | Recipe-level actor gates (e.g. `MinSkillCondition` crafting L1), ANDed hot by `CraftingJobDef.meets_requirements`. |

**MVP recipe sources** (GDD values, modeled as RecipeDefs when their items exist):
- **Furniture** (GDD §7.2 Buildables `Materials` column): Clinic Bed `{scrap: 100}`, Workbench `{scrap: 60, components: 10}`, Forge `{scrap: 80, components: 20}`, Colonist Bed `{scrap: 40, components: 5}`, Command Desk `{scrap: 120, components: 30}`, Vehicle Lift `{scrap: 120, components: 40}`.
- **Armor** (GDD §17 Equipment, per-slot per-tier): e.g. Leather Body `{leather: 6}`, Cloth Body `{cloth: 4}`, Scrap Body `{scrap: 6}`.
- **Weapons + ammo** (GDD §17 Equipment): Knife `{metal: 2}`, Pistol `{metal: 5, components: 5}`, Bullet `{scrap: 1}`. (Club/Bow/arrows are post-MVP.)
- **Smelting** (GDD §7.3 items): Ore→Metal, Scrap→Components, Metal+Components→Reinforced.

## `data/loadouts/<template>.tres` (Resource: `loadout_template.gd`) — *(planned)*

> **Status: planned — `data/loadouts/` is empty; `loadout_template.gd` does not exist yet** (Equipment subsystem). Intended schema below.

Player-created loadout templates, saved per run. Each template is an abstract slot→item_def_id mapping (resolved to concrete items from storage at equip time). Created/edited via the Colony screen Loadouts tab. See GDD §17 Equipment + §12.

| Field | Type | Description |
|---|---|---|
| `template_id` | `String` | Unique per run. |
| `display_name` | `String` | Player-assigned name. |
| `slots` | `Dictionary[String, String]` | slot_id → item_def_id. Keys: `"armor_head"`, `"armor_body"`, `"armor_arms"`, `"armor_legs"`, `"armor_feet"`, `"armor_hands"`, `"melee"`, `"ranged"`. Values are item_def_ids (e.g. `"leather_armor_body"`, `"knife"`). Missing/empty slots = unequipped. |

**Slot validity** (which item_def_ids can go in which slot):
- `armor_*` slots: armor defs matching the slot (e.g. `armor_body` accepts `cloth_armor_body`, `leather_armor_body`, `scrap_armor_body`).
- `melee`: weapon defs with `class == "melee"` (Knife in MVP; Club post-MVP).
- `ranged`: weapon defs with `class == "ranged"` (Pistol in MVP; Bow post-MVP).

**Equip resolution at runtime:** when auto-equip fires, LoadoutManager resolves each slot's `item_def_id` to the nearest unclaimed concrete item of that type in colony storage. If none available, the slot stays empty (partial equip; logged).

**MVP note:** templates are per-colonist (one template assigned per colonist). "Colonist Groups" (assign a template to a group of colonists) is pinned post-MVP per GDD §12.

## `data/crops/<id>.tres` (Resource: `crop_def.gd`)

Global definition for a farmable crop (ARCH [Farming](farming.md), GDD §6). Scanned by `CropLibrary`. See authoring guide in `docs/HOWTO-author-crops.md`.

| Field | Type | Description |
|---|---|---|
| `id` | `String` | Unique; matches filename (e.g. `"cave_spud"`, `"holdout_wheat"`, `"bio_gel_orchid"`). |
| `display_name` | `String` | Inspector and UI label. |
| `growth_time_hours` | `float` | In-game hours to reach 100% maturity. |
| `growth_stages` | `int` | Number of visual growth stages (default `3`). |
| `stage_meshes` | `Array[Mesh]` | Optional custom meshes per stage. Falls back to procedural cylinder meshes if empty. |
| `max_water` | `float` | Maximum water capacity (default `100.0`). |
| `water_decay_per_hour` | `float` | Water percentage consumed per in-game hour. |
| `thirsty_threshold` | `float` | Water percentage below which a `WaterJobDef` is spawned (default `30.0`). |
| `tending_mode` | `int` / `TendingMode` | `0` = NONE, `1` = MILESTONE, `2` = DECAY. |
| `tending_milestones` | `Array[float]` | Growth progress points (0.0 to 1.0) requiring tending. |
| `tending_decay_hours` | `float` | In-game hours a tended state lasts before needing maintenance again (DECAY mode). |
| `untended_growth_mult` | `float` | Growth speed multiplier while untended (`0.0` = frozen). |
| `neglect_hours` | `float` | Buffer hours untended before neglect penalties accumulate. |
| `neglect_yield_penalty` | `float` | Fraction of yield lost per `neglect_hours` exceeded. |
| `plant_conditions` | `Array[Condition]` | Gating requirements to sow/plant this crop. |
| `tend_conditions` | `Array[Condition]` | Gating requirements to tend this crop (e.g. `MinSkillCondition`, `HasItemCondition`). |
| `seed_item_id` | `String` | Optional seed item required to plant. |
| `yield_tiers` | `Array[CropYieldTier]` | Milestone yield definitions. |
| `base_harvest_time` | `float` | Base harvest seconds (scaled by harvesting skill). |
| `wither_hours` | `float` | In-game hours a mature crop can sit unharvested before withering (`0.0` = never). |

## `data/crops/crop_yield_tier.gd` (Resource: `CropYieldTier`)

Defines yields granted when harvesting a crop at or above a minimum growth progress.

| Field | Type | Description |
|---|---|---|
| `min_growth_progress` | `float` | Minimum growth progress required (e.g. `0.5` for half-yield, `1.0` for full maturity). |
| `yields` | `Array[ItemAmount]` | Items and counts awarded. |

## `data/capability_params/farm_plot_params.gd` (Resource: `FarmPlotParams`)

Capability sub-resource attached to farm plot `FurnitureDef`s (e.g. `Growing Trough`).

| Field | Type | Description |
|---|---|---|
| `allowed_crops` | `Array[String]` | Allowed `CropDef` ids for this plot. Empty means all crops in `CropLibrary` are permitted. |
