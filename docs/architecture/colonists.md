# Subsystem: Colonists

Colonist entities, roster (in Colony autoload), labor AI, raid stances. GDD §6. The job system (Job Board, JobDefs, hauling, construction) is documented separately in [Jobs](jobs.md).

> **Sprint scope (built):** colonists work jobs via `ColonistAI`'s inline three-state machine (IDLE → poll [Job Board](jobs.md) → MOVE → WORK). Seven job defs ship — Construction, Hauling, Crafting, Harvest, Sow, Water, Tend — all driven by the [`JobDef`](jobs.md) leg-behaviour contract. See [Jobs](jobs.md) for the full job pipeline.
>
> **Deferred (GDD §6, not yet built):** the Stamina work-speed factor (the skill factor is live — timed legs scale via [Skills](skills.md); `StaminaComponent` is still a stub), `colonist_combat.gd` (§6.7), recruitment (§6.9), the `RaidStance` enum (§6.2), roster save/restore (so a colonist's carry inventory isn't persisted yet — skills now round-trip via `Colonist.serialize` for when it lands).

## Files

| File | Type | Responsibility |
|---|---|---|
| `colonist.gd` | Script | The colonist entity (`Colonist extends CharacterBody3D`). HP, labor priorities, raid stance, current Job, path-following locomotion (`set_path` / `has_arrived`), and a carry `CharacterInventory` (so it can stand in for `actor` in `Blueprint.deposit_from`). Holds `skill_set` / `stamina_component` / `pathfinder` / `inventory` child refs. Does NOT own job discovery (Job Board does). |
| `colonist.tscn` | Scene | Capsule mesh + CollisionShape + `SkillSet` / `StaminaComponent` / `ColonistAI` / `ColonistCombat` (bare node, no script yet) / `VoxelPathfinder` / `StepClimber` (shared step/hop assist, `hop_height = 1.05` — see the [Player](player.md) class reference) children. (The carry `Inventory` is code-created in `_ready`, mirroring the Player's scene-placed one.) |
| `colonist_ai.gd` | Script | The colonist job loop over a **leg sequence**: IDLE → poll [Job Board](jobs.md) (0.5s throttle) → `try_assign` → get leg 0 → path (A\*) → MOVE → on arrival run the leg's `begin`/`complete` → `_advance` to the next leg or `_end_job`. Owns the WORK tick for timed legs; delegates pathfinding to `VoxelPathfinder`. The [`JobDef`](jobs.md) contract (`get_next_leg`/`begin`/`complete`/`on_end`/`is_available`) supplies all behaviour — ColonistAI is intentionally "dumb" (walks, times, advances). |
| `voxel_pathfinder.gd` | Script (component) | Voxel A\* with an **injected walkability predicate** — intentionally generic (knows nothing about voxels/furniture/blueprints). `find_path_to_adjacent` resolves a stand-adjacent cell so a colonist can reach a blocked footprint (a blueprint or a crate). See class reference. |
| `skill_set.gd` | Script (component) | Per-colonist skill progression — seeded from `colonist_def.starting_skills`, XP on job success, work-speed multipliers. See [Skills](skills.md). |
| `stamina_component.gd` | Script (component) | Still a stub — see [Energy](energy.md). |
| `../autoloads/colony.gd` | Autoload | Roster + [Job Board](jobs.md) + StorageRegistry. Produces construction/haul Jobs from `EventBus.blueprint_placed`; chains hauling→construction on `blueprint_materials_ready`; craft jobs from the crafting signals; harvest/sow/water/tend jobs from the harvest-mark and farm-plot signals. Cross-scene (colonists persist base↔POI). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `colonist_died(colonist_id)` | `colonist.gd` | GameLog | Yes | Colonist Death |

*(Job-related signals — `blueprint_materials_ready`, `job_failed`, `job_logged` — are documented in [Jobs](jobs.md).)*

## Class Reference

### Class: Colony

**Extends:** Node (autoload)
**Script:** `autoloads/colony.gd`
**Description:** The colony roster, [Job Board](jobs.md), and StorageRegistry. Cross-scene because colonists persist during expeditions. Owns colonist lifecycle (spawn/reparent into the current map's `ColonistContainer`) and produces Jobs for every labor: construction/haul from blueprint placement (chaining hauling→construction on `blueprint_materials_ready`), craft from the crafting signals, harvest from harvest marks, and sow/water/tend from the farm-plot signals.
**Used by:** HUD (roster UI), Colony Management screen, Combat (damage targets), Raids (stance execution).
**Lifecycle:** `_ready` creates the [JobBoard](jobs.md) + `StorageRegistry` child Nodes and connects the EventBus producers: `blueprint_placed` / `blueprint_removed` / `blueprint_materials_ready`, `crafting_order_queued` / `crafting_materials_ready`, `harvest_mark_toggled`, `plot_needs_sowing` / `plot_needs_water` / `plot_needs_tending`, and `furniture_removed` (job cleanup). `on_map_wired` is called by `MapWiring.wire_colonists` on every map load (which also points `storage_registry` at the map's furniture container).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `colonists` | `Array[Colonist]` | Active colonists (capped at `MVP_CAP = 5`). Node instances live in the current map's `ColonistContainer`; this Array is the cross-scene authority. |
| `job_board` | `JobBoard` | The [Job Board](jobs.md) (a child Node). |
| `storage_registry` | `StorageRegistry` | The storage-crate index (a child Node). See [Inventory](inventory.md). |
| `_walkability_predicate` | `Callable` | Cached walkability predicate from the active map (used for runtime-spawned colonists). |

**Functions:**

| Function | Description |
|---|---|
| `on_map_wired(container, spawn_positions) → void` | Empty roster → spawn one colonist per `ColonistSpawn` marker via `spawn_colonist`; non-empty → reparent existing nodes into the new map. |
| `set_walkability_predicate(predicate: Callable) → void` | Stores the active map's walkability predicate and injects it into all current roster colonists. |
| `spawn_colonist(colonist_def = null, pos = Vector3.ZERO) → Colonist` | Instantiate, position, register, and wire a new colonist. Returns the new `Colonist` instance, or `null` if the roster is full or no map is wired. |
| `add_colonist` / `remove_colonist` | Recruit / drop a colonist (post-MVP / death). |
| `_on_blueprint_placed(target_def_id, anchor, blueprint) → void` | Decide haul-vs-construct (any unmet material_cost → haul, regardless of stock — the job drought-waits until crates can satisfy it; else construction), bind + add the Job. See [Jobs](jobs.md). |
| `_on_blueprint_materials_ready(target_def_id, anchor, blueprint) → void` | Materials crossed complete (player or hauler deposit) → `_spawn_construction_job`. |
| `_spawn_construction_job(target_def_id, anchor, blueprint) → void` | Build + add a construction Job, deduped by anchor (defensive against a duplicate `blueprint_materials_ready`). |
| `_spawn_job(def, title, anchor, location, target) → void` | Shared producer plumbing every `_spawn_*` routes through: dedupe by anchor + def, `Job.from_def`, bind the placement, `add_job`. Def identity works because the def consts are preloaded singletons (required for the farming defs, which share `labor_id "farming"`). |
| `_remove_jobs_at(anchor, def = null) → void` | Drop jobs at an anchor — every def's when `def` is null (blueprint removal), else only that def's. |
| `_on_blueprint_removed(target_def_id, anchor) → void` | Removes any Job targeting that anchor (fires on cancel and completion). Idempotent. |
| `_on_crafting_order_queued(station, anchor) → void` | A recipe was queued at a station with unmet inputs → haul job feeding the station. See [Jobs](jobs.md). |
| `_on_crafting_materials_ready(station, anchor) → void` | Station inputs crossed complete → `_spawn_craft_job`. |
| `_spawn_craft_job(station, anchor) → void` | Build + add a crafting Job targeting the station (deduped via `_spawn_job`). |
| `_on_harvest_mark_toggled(furniture, anchor, is_marked) → void` | Harvest mark set → `_spawn_harvest_job`; cleared → `_remove_jobs_at(anchor, HARVEST_DEF)`. |
| `_on_furniture_removed(def_id, anchor) → void` | Furniture freed → `_remove_jobs_at(anchor)` so colonists don't path into freed nodes. |
| `_on_plot_needs_sowing` / `_on_plot_needs_water` / `_on_plot_needs_tending` | Farm-plot needs flipped on → spawn the matching sow/water/tend job; off → remove it (via `_spawn_sow_job` / `_spawn_water_job` / `_spawn_tend_job`, deduped through `_spawn_job`). |

### Class: Colonist

**Extends:** CharacterBody3D
**Script:** `colonist.gd`
**Description:** A colonist entity. Holds identity, labor priorities, raid stance, the current Job, and a carry `CharacterInventory`; runs gravity + path-following locomotion in `_physics_process` (vertical negotiation — stepping onto lips, hopping 1 m blocks — lives in the shared `StepClimber` child; see [Player](player.md)). Resolves its component child refs in `_ready` (including the code-created carry `Inventory`). Does NOT own job discovery — `ColonistAI` (a child node) drives the leg loop against the [Job Board](jobs.md).
**Used by:** Colony (roster), Combat (target, future), Colonist Management screen.
**Lifecycle:** `_ready` assigns a uuid `colonist_id`, copies identity/labor/stance from the `ColonistDef`, resolves component child refs, creates + adds the carry `CharacterInventory`, and seeds HP.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `colonist_id` | `String` | Unique id (`Tools.generate_uuid()`). |
| `display_name` | `String` | Shown in UI. |
| `colonist_def` | `ColonistDef` | `[export]` The static def (identity, stats, default labor priorities). See [Data Schemas](data-schemas.md). |
| `labor_priorities` | `Dictionary` | Labor id → 0–5 priority weight. Copied from the def at `_ready`. |
| `raid_stance` | `int` | Fight / Fight-Post / Shelter (`RaidStance` enum deferred — stored as int). |
| `current_job` | `Job` | The Job while working a leg (null while idle). Not serialized. |
| `inventory` | `CharacterInventory` | Carry inventory (materials hauled to blueprints). Lets the colonist stand in for `actor` in `Blueprint.deposit_from`. |
| `skill_set` / `stamina_component` / `pathfinder` | component | `@onready` child refs. See [Skills](skills.md) / [Energy](energy.md) / VoxelPathfinder below. |

**Functions:**

| Function | Description |
|---|---|
| `set_path(path: Array) → void` | Feed world-space waypoints; resets any in-progress path. Empty path leaves the colonist standing. |
| `has_arrived() → bool` | True when every waypoint has been consumed (or no path was set). |
| `add_item` / `remove_item` / `has_item` / `can_carry` / `remaining_capacity` | Carry-inventory wrappers (mirror `Player`'s) so `deposit_from` and crate transfers work. |
| `take_damage(amount, source)` / `heal(amount)` | HP changes; at 0 HP emits `EventBus.colonist_died`. |
| `set_labor_priority` / `set_raid_stance` | Mutators. |
| `serialize()` / `deserialize(data)` | SaveSystem contract — scalar/dict state + world position. Excludes `current_job`, component sub-state, and (for now) the carry inventory. |

### Class: ColonistAI

**Extends:** Node
**Script:** `colonist_ai.gd` (a child of each `Colonist`)
**Description:** Drives a colonist's job loop over a **leg sequence** against the [Job Board](jobs.md): poll → assign → leg 0 → path → walk → run the leg → advance. Owns the inline `State` machine, the per-leg bookkeeping (`_leg`, `_work_elapsed`), and the WORK tick for timed legs. The [`JobDef`](jobs.md) supplies the legs + the `begin`/`complete`/`on_end` behaviour — ColonistAI is intentionally "dumb" (it walks, times, and advances; all behaviour lives on the def). Delegates pathfinding to the colonist's `VoxelPathfinder`. The WORK state is itself the busy guard — no separate `set_busy`.
**Lifecycle:** `_process` runs the state machine each frame; IDLE polls are throttled to once per `_POLL_INTERVAL = 0.5s`.

**States (`State` enum):**

| State | Behaviour |
|---|---|
| `IDLE` | Throttled `_try_claim_and_path`: `get_best_job_for` → `try_assign` → `def.get_next_leg` (leg 0) → `find_path_to_adjacent` → `set_path` → MOVE. On any miss (no job, lost assign race, no leg, no path) `unassign` + stay IDLE. |
| `MOVE` | Freed-target guard on `_leg.target_node` (abort if freed); on `has_arrived()` → `_begin_work()`. |
| `WORK` | `_tick_work(delta)`: accumulate `_work_elapsed` against `job.def.begin()`'s duration; on elapse `complete` + `_advance`. Abort via `_end_job(false)` if the target freed. |

**Functions:**

| Function | Description |
|---|---|
| `_try_claim_and_path() → void` | IDLE tick: select + assign + leg 0 + path (→ MOVE), or release + stay IDLE. A null leg-0 runs `def.on_end` (null leg) before releasing (hauling's clog self-heal); an unreachable leg-0 records a `JobBoard.fail`. |
| `_begin_work() → void` | MOVE arrival: `def.begin`; instant (≤0) → `complete` + `_advance`, else → WORK. |
| `_tick_work(delta) → void` | WORK tick: accumulate; on elapse `complete` + `_advance`; `_abort_job` if the target freed. |
| `_advance() → void` | Pull the next leg via `def.get_next_leg`; re-path → MOVE. Null → `_end_job(def.job_complete(job))` — a stall (drought hauler) logs "waiting for materials" and skips skill XP; an unreachable next leg `_abort_job`s. |
| `_abort_job(reason) → void` | `_end_job(false)` (on_end cleanup, unassign, maybe remove) then `JobBoard.fail(job.id, reason)` — the failure counter / auto-remove path. |
| `_end_job(success) → void` | Leave the job: `def.on_end` cleanup (return carried items, persist partial progress), `unassign`, `should_close()` (def-level — drought-waiting haul jobs survive) →`remove_job`, → IDLE. |

### Class: VoxelPathfinder

**Extends:** Node
**Script:** `voxel_pathfinder.gd`
**Description:** Voxel A\* pathfinder with an **injected walkability predicate**. Intentionally generic — it knows nothing about voxels, furniture, or blueprints. The wiring layer (`MapWiring.wire_colonists`) composes a per-cell `is_walkable(Vector3i)` Callable from `VoxelGrid` solidity + `FurnitureLayer`/`BlueprintLayer` occupancy and injects it via `set_walkability`. Output is world-space `Vector3` waypoints sized for `Colonist.set_path` (whose locomotion zeroes Y).
**Used by:** ColonistAI (path requests), Colonist (`pathfinder` child ref).

**Neighbor model:** stepped — the 4 horizontal directions crossed with dy ∈ {+1, 0, −1…−3}. +1 climbs one full block (the `StepClimber` child physically hops the obstacle face — colonists have no manual jump); drops up to `_MAX_DROP = 3` cells are walk-off-and-fall. Vertical moves cost extra (`_JUMP_UP_COST = 3.0` to climb, `_DROP_COST_PER_CELL = 1.5` per cell fallen) so flat detours — and, once a per-block cost hook exists, future stair blocks — win over jumping whenever comparable. The predicate validates every expanded cell including head clearance, and `find_path_to_footprint_adjacent`'s candidate expansion stays strictly horizontal (stand-adjacent never changes Y). Multi-cell drops assume an unobstructed fall column — the predicate validates the landing, not the gap.

**Functions:**

| Function | Description |
|---|---|
| `set_walkability(predicate: Callable) → void` | Inject the per-cell walkability predicate (composed by the wiring layer). |
| `find_path(start_cell, target_cell) → Array[Vector3i]` | Core A\* over cells (Dictionary-backed open/closed, linear min-f scan, stepped neighbors with per-move costs). Empty if no path / predicate unset / target not standable / start==target. `_MAX_EXPLORED = 8000` backstop. |
| `find_stand_cell(world_pos) → Vector3i` | Resolve a standable cell near a world position (scan down then up ±3 Y). Handles the spawn-drop resting height. |
| `find_stand_near_cell(center, max_radius = 4) → Vector3i` | Nearest walkable cell to `center` via a horizontal ring search (Chebyshev rings, min Euclidean within the first non-empty ring). For targets on a blocked footprint — the colonist stands adjacent, never on it. Returns `center` unchanged if already walkable or none found within radius. |
| `find_path_world(start_world, target_world) → Array[Vector3]` | World→stand-cell→A\*→world. Use only when the target is standable terrain, NOT a blocked footprint. |
| `find_path_to_adjacent(start_world, target_world, max_radius = 4) → Array[Vector3]` | Like `find_path_world`, but resolves the TARGET via `find_stand_near_cell` so the colonist reaches a point on a blocked footprint (a blueprint or crate). Entry point for `ColonistAI` legs. |
| `to_world_waypoints(cells) → Array[Vector3]` | Cell waypoints → world-space centers. |
