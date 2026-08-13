# Subsystem: Colonists

Colonist entities, roster (in Colony autoload), Job Board, labor AI, raid stances. GDD §6.

> **Sprint scope (built):** colonists work **multi-leg jobs**. A `JobDef` produces a stream of `JobLeg`s (walk-to → act); `ColonistAI` walks each leg and runs the def's `begin`/`complete` on arrival. Two labors ship:
> - **Construction** — a blueprint with no unmet `material_cost` (costless, pre-satisfied, or no storage source) → a one-leg job: walk to a stand-adjacent cell, WORK over `build_time`, `Blueprint.complete` materializes it.
> - **Hauling** — a blueprint with an unmet `material_cost` whose source is in stock → up to `max_assignees` haulers divvy a run through the blueprint's shared deposit counter: each loops FETCH (crate → carry inventory) → DELIVER (`Blueprint.deposit_from`) until `has_complete_materials()`. The DELIVER that crosses the threshold emits `blueprint_materials_ready` → `Colony` spawns the construction job.
>
> **Multi-assign:** a `Job` may hold several colonists at once (`try_assign`/`unassign`); **one colonist finishing ≠ job done** — the job leaves the board only when `should_close()` (no assignees left AND not accepting more). `JobBoard.get_best_job_for` prunes dead jobs (`!is_available && unassigned`) on each poll.
>
> **Deferred (GDD §6, not yet built):** the skill × Stamina work-speed multiplier (the WORK tick runs at 1×; `begin`'s returned duration is the seam), `colonist_combat.gd` (§6.7), recruitment (§6.9), the `RaidStance` enum (§6.2), roster save/restore (so a colonist's carry inventory isn't persisted yet), and `colonist_ai_statemachine.gd` (an unreferenced orphan stub superseded by the inline state enum in `colonist_ai.gd`).
>
> **Known gaps:** a material'd blueprint with no stocked source builds anyway (the producer falls back to construction so the game still progresses — the materials gate only bites when stock exists); a haul job whose source dries up is pruned and won't auto-retrigger on later restock (the player can still deposit directly, which self-heals via `blueprint_materials_ready`).
>
> **Labors (GDD §6.4):** a *Labor* is a category of work, declared as a `LaborDef` resource under `data/labors/` (see [Data Schemas](data-schemas.md)) and referenced everywhere by its String `id`. Five ship today — `construction`, `crafting`, `hauling`, `mechanics`, `smelting` (Repair/Farming/Cooking post-MVP). The labor id is the join key of the subsystem: a `Job` carries one `labor_id` (what kind of work it is), and a `Colonist`'s `labor_priorities` Dict (`{labor_id: 0–5 weight}`) decides which jobs that colonist will accept — `JobBoard.get_best_job_for` skips any job whose labor has weight 0 for that colonist. `ColonistDef.default_labor_priorities` enables `construction`, `crafting`, and `hauling` at priority 1 by default (mechanics/smelting start disabled).

## Files

| File | Type | Responsibility |
|---|---|---|
| `colonist.gd` | Script | The colonist entity (`Colonist extends CharacterBody3D`). HP, labor priorities, raid stance, current Job, path-following locomotion (`set_path` / `has_arrived`), and a carry `CharacterInventory` (so it can stand in for `actor` in `Blueprint.deposit_from`). Holds `skill_set` / `stamina_component` / `pathfinder` / `inventory` child refs. Does NOT own job discovery (Job Board does). |
| `colonist.tscn` | Scene | Capsule mesh + CollisionShape + `SkillSet` / `StaminaComponent` / `ColonistAI` / `ColonistCombat` (bare node, no script yet) / `VoxelPathfinder` children. (The carry `Inventory` is code-created in `_ready`, mirroring the Player's scene-placed one.) |
| `colonist_ai.gd` | Script | The colonist job loop over a **leg sequence**: IDLE → poll Job Board (0.5s throttle) → `try_assign` → get leg 0 → path (A\*) → MOVE → on arrival run the leg's `begin`/`complete` → `_advance` to the next leg or `_end_job`. Owns the WORK tick for timed legs; delegates pathfinding to `VoxelPathfinder`. |
| `voxel_pathfinder.gd` | Script (component) | Voxel A\* with an **injected walkability predicate** — intentionally generic (knows nothing about voxels/furniture/blueprints). `find_path_to_adjacent` resolves a stand-adjacent cell so a colonist can reach a blocked footprint (a blueprint or a crate). See class reference. |
| `job.gd` | Script (`RefCounted`) | A unit of work — pure data + the multi-assign claim bookkeeping (`try_assign`/`unassign`/`is_available`/`should_close`, `_assigned_colonists`). Leg behaviour lives on the `JobDef`; the Job Board owns the registry. |
| `job_board.gd` | Script (on Colony) | Job registry + selection: `add_job` / `get_best_job_for` / `remove_job` / `fail`. Selection filters `Job.is_available()` and prunes dead jobs each poll. Assignment lives on the `Job`, not here. |
| `../inventory/storage_registry.gd` | Script (on Colony) | Live index of storage crates: `find_source` / `has_source_for` / `nearest_crate`, scanning the current map's `FurnitureContainer`. Used by hauling to find a source for a blueprint's still-needed materials. See [Inventory](inventory.md). |
| `skill_set.gd` / `stamina_component.gd` | Script (component) | Colocated here for the colonist sprint (stubs — see [Skills](skills.md) / [Energy](energy.md)). |
| `../autoloads/colony.gd` | Autoload | Roster + Job Board + StorageRegistry. Produces construction/haul Jobs from `EventBus.blueprint_placed`; chains hauling→construction on `blueprint_materials_ready`. Cross-scene (colonists persist base↔POI). |
| `../data/labors/` | Data | `LaborDef` resources — the canonical labor ids (Construction, Crafting, Hauling, Mechanics, Smelting; Repair/Farming/Cooking post-MVP). See [Data Schemas](data-schemas.md). |
| `../data/jobs/` | Data | `JobDef` templates (`job_def.gd` base, `JobLeg`, + per-labor subclasses) authored as `.tres`. `construction.tres` (`ConstructionJobDef`) and `hauling.tres` (`HaulingJobDef`). See [Data Schemas](data-schemas.md). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `colonist_died(colonist_id)` | `colonist.gd` | Colony, HUD, Memorial | Yes | Colonist Death |
| `blueprint_materials_ready(target_def_id, anchor, blueprint)` | `blueprint.gd` (`deposit_from`) | Colony | Yes | Haul → construction chain (single-fire per blueprint) |
| `job_failed(job_id, reason)` | `job_board.gd` | Job Log UI | No | Job Failure Handling |
| `job_logged(entry)` | `job_board.gd` | Job Log UI (when open) | Yes | Job Failure Handling |

## Flow Trace: Job lifecycle (produce → assign → resolve)

The Job Board is the registry; producers add Jobs, consumers (`ColonistAI`) select + assign via `Job.try_assign` (assignment lives on the Job, multi-colonist). The board never pathfinds or builds. Two views of the same pipeline: this flow is the board/job state machine; the walk flow below is the colonist's spatial half.

**Trigger:** A blueprint is placed (`EventBus.blueprint_placed`).

1. **Produce (decide haul vs construct)** — `Colony._on_blueprint_placed(target_def_id, anchor, blueprint)`:
   - If the blueprint has an unmet `material_cost` AND `storage_registry.has_source_for(needed_ids)` → build a **haul** `Job` from `HAULING_DEF` (`title="Haul materials for <id>"`, `max_assignees` from the def).
   - Else → `_spawn_construction_job` (costless, pre-satisfied, or no source available — the materials gate only bites when stock exists).
   Both bind `anchor_cell=anchor`, `location=footprint-center` (via `FurnitureLayer.world_origin`), `target_node=blueprint`, then `JobBoard.add_job`. `Job.from_def` denormalizes `labor_id`/`title`/`max_assignees` from the def and mints a uuid `id`.
2. **Select** — a colonist's `ColonistAI`, throttled to once per 0.5s while IDLE, calls `JobBoard.get_best_job_for(colonist)`. The board first `_prune_dead_jobs()` (drop `!is_available && unassigned`), then filters to `is_available()` jobs whose Labor is enabled (`labor_priorities[labor_id] > 0`), ranks by highest priority, ties by nearest `distance_squared_to(job.location)`. Returns the best Job (or `null`); **it does not assign.**
3. **Assign** — `ColonistAI` calls `job.try_assign(colonist)`: the Job checks `is_available()` (slot under `max_assignees` AND the def's labor-specific gate) and that the colonist isn't already assigned, then appends its id to `_assigned_colonists`. Pull, not push — this only registers; the colonist asks `get_next_leg` when ready. Returns false on a lost slot race; the next poll retries.
4. **Resolve — happy path (legs)** — see the walk flow. On arrival at each leg the AI runs `job.def.begin`/`complete`; `_advance` pulls the next leg (or `_end_job` when `get_next_leg` returns null). For hauling, the DELIVER leg's `deposit_from` crossing `has_complete_materials` emits `blueprint_materials_ready` → `Colony._on_blueprint_materials_ready` → `_spawn_construction_job` (guarded against a duplicate at the anchor). When the last assignee leaves and `should_close()` is true, the AI removes the Job.
5. **Resolve — fail path** — `JobBoard.fail(job.id, reason)` increments `failure_count`, clears assignees, emits `job_failed` locally, relays `job_logged` via EventBus, auto-erases at `_MAX_FAILURES (3)`. (Currently no caller drives `fail` from the leg loop — the dead-job prune handles removal for haul's no-source case. Kept as the documented failure seam.)

**End state:** Job removed from the board — by the last assignee's `should_close()` on completion, or pruned/`fail`-removed otherwise. The blueprint's lifetime is independent: cancelling or completing one emits `blueprint_removed` → `Colony._on_blueprint_removed` drops any matching Job by anchor (idempotent).

## Flow Trace: Colonist works a job (assign → leg loop → arrive)

The spatial counterpart to the lifecycle flow. A job is a sequence of legs; the AI walks each and acts on arrival. The pathing is the load-bearing part — a leg's `location` is a footprint-center the walkability predicate marks **blocked**, so the pathfinder routes the colonist to a cell *adjacent* to it, never onto it (true for both blueprints and crates — both are furniture).

**Trigger:** `ColonistAI._try_claim_and_path` just assigned a Job and got leg 0; `colonist.current_job` is set.

1. The AI calls `_colonist.pathfinder.find_path_to_adjacent(_colonist.global_position, leg.location)`. Inside that one call:
   - **`find_stand_cell(start_world)`** — a vertical scan (±`_STAND_SCAN = 3`) settles the colonist's *own* standing cell (spawn-drop height, minor floor ambiguity).
   - **`target_base = Vector3i(floor(target_world.{x,y,z}))`** — the leg target's footprint-center cell. **Blocked** by the predicate.
   - **`find_stand_near_cell(target_base, max_radius = 4)`** — horizontal Chebyshev ring search; the predicate rejects footprint/furniture/terrain cells, the **first non-empty ring** returns its min-Euclidean cell → nearest walkable cell **adjacent**. Returns `target_base` unchanged if nothing walkable is in range (A\* then fails clean).
   - **`find_path(start_cell, target_cell)`** — A\*: 4-connected neighbors, Manhattan heuristic, lazy neighbor expansion gated cell-by-cell by the predicate; Dictionary-backed open/closed, linear min-f scan; `_MAX_EXPLORED = 4000` backstop.
   - **`to_world_waypoints(cells)`** — each cell → `Vector3(cell) + (0.5, 0.5, 0.5)` (XZ-centered; Y informative only).
2. If the path is **empty** (no reachable adjacent cell): the AI `unassign`s, clears `current_job`, stays IDLE — the 0.5s throttle bounds the retry.
3. Otherwise `Colonist.set_path(waypoints)` (`_path.assign(...)`, reset `_path_index`), AI state → MOVE.
4. **Locomotion** — `Colonist._physics_process` applies gravity, then `_follow_path`: horizontal vector to `_path[_path_index]` (Y zeroed) at `base_move_speed`; within `_ARRIVAL_THRESHOLD = 0.2` → advance index. `has_arrived()` = `_path_index >= _path.size()`.
5. **Arrival** — MOVE `_process` watches `has_arrived()`; on true → `_begin_work()`: `job.def.begin(colonist, leg, job)`. Instant (≤0) → `complete` + `_advance`; timed (>0) → WORK ticks, then `complete` + `_advance`. `_advance` pulls the next leg (re-path → MOVE) or, on null, `_end_job(true)`. A freed leg target mid-MOVE/mid-WORK, or an unreachable next leg, → `_end_job(false)` (def's `on_end` returns carried items, `unassign`, maybe `should_close`→remove).

> **Legs are how a hauler loops:** FETCH leg → walk to crate → `complete` withdraws still-needed materials into the carry inventory → `_advance` → DELIVER leg → walk to blueprint → `complete` = `deposit_from` → `_advance` → (satisfied? `_end_job` : carrying? DELIVER : FETCH a crate). Phase is derived from carry state, not stored.

> **Why the ring search is the crux:** the injected predicate (`MapWiring._compose_walkability`) marks a cell walkable iff it is air, has a solid floor below, and is **not** furniture or a blueprint. Footprint-centers are rejected for free — the pathfinder never needs the footprint's shape or the def's `dimensions`; it just finds the nearest free neighbour.

**End state:** Colonist stands adjacent to each leg target in turn; a builder WORKs the blueprint to completion (materializes via `Blueprint.complete`), a hauler fetches/delivers until materials are satisfied. Job resolves on the board; colonist idles.

## Class Reference

### Class: Colony

**Extends:** Node (autoload)
**Script:** `autoloads/colony.gd`
**Description:** The colony roster, Job Board, and StorageRegistry. Cross-scene because colonists persist during expeditions. Owns colonist lifecycle (spawn/reparent into the current map's `ColonistContainer`) and produces construction/haul Jobs from blueprint placement, chaining hauling→construction on `blueprint_materials_ready`.
**Used by:** HUD (roster UI), Colony Management screen, Combat (damage targets), Raids (stance execution).
**Lifecycle:** `_ready` creates the `JobBoard` + `StorageRegistry` child Nodes and connects `EventBus.blueprint_placed` → `_on_blueprint_placed`, `blueprint_removed` → `_on_blueprint_removed`, `blueprint_materials_ready` → `_on_blueprint_materials_ready`. `on_map_wired` is called by `MapWiring.wire_colonists` on every map load (which also points `storage_registry` at the map's furniture container).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `colonists` | `Array[Colonist]` | Active colonists (capped at `MVP_CAP = 5`). Node instances live in the current map's `ColonistContainer`; this Array is the cross-scene authority. |
| `job_board` | `JobBoard` | The Job Board (a child Node). |
| `storage_registry` | `StorageRegistry` | The storage-crate index (a child Node). |

**Functions:**

| Function | Description |
|---|---|
| `on_map_wired(container, spawn_positions) -> void` | Empty roster → spawn one colonist per `ColonistSpawn` marker (up to `MVP_CAP`); non-empty → reparent existing nodes into the new map. |
| `add_colonist` / `remove_colonist` | Recruit / drop a colonist (post-MVP / death). |
| `_on_blueprint_placed(target_def_id, anchor, blueprint) -> void` | Decide haul-vs-construct (unmet material_cost + source in stock → haul; else construction), bind + add the Job. |
| `_on_blueprint_materials_ready(target_def_id, anchor, blueprint) -> void` | Materials crossed complete (player or hauler deposit) → `_spawn_construction_job`. |
| `_spawn_construction_job(target_def_id, anchor, blueprint) -> void` | Build + add a construction Job, deduped by anchor (the no-source producer path and a later deposit can both target one blueprint). |
| `_on_blueprint_removed(target_def_id, anchor) -> void` | Removes any Job targeting that anchor (fires on cancel and completion). Idempotent. |

### Class: Colonist

**Extends:** CharacterBody3D
**Script:** `colonist.gd`
**Description:** A colonist entity. Holds identity, labor priorities, raid stance, the current Job, and a carry `CharacterInventory`; runs gravity + path-following locomotion in `_physics_process`. Resolves its component child refs in `_ready` (including the code-created carry `Inventory`). Does NOT own job discovery — `ColonistAI` (a child node) drives the leg loop against the Job Board.
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
| `set_path(path: Array) -> void` | Feed world-space waypoints; resets any in-progress path. Empty path leaves the colonist standing. |
| `has_arrived() -> bool` | True when every waypoint has been consumed (or no path was set). |
| `add_item` / `remove_item` / `has_item` / `can_carry` / `remaining_capacity` | Carry-inventory wrappers (mirror `Player`'s) so `deposit_from` and crate transfers work. |
| `take_damage(amount, source)` / `heal(amount)` | HP changes; at 0 HP emits `EventBus.colonist_died`. |
| `set_labor_priority` / `set_raid_stance` | Mutators. |
| `serialize()` / `deserialize(data)` | SaveSystem contract — scalar/dict state + world position. Excludes `current_job`, component sub-state, and (for now) the carry inventory. |

### Class: ColonistAI

**Extends:** Node
**Script:** `colonist_ai.gd` (a child of each `Colonist`)
**Description:** Drives a colonist's job loop over a **leg sequence** against the Job Board: poll → assign → leg 0 → path → walk → run the leg → advance. Owns the inline `State` machine, the per-leg bookkeeping (`_leg`, `_work_elapsed`), and the WORK tick for timed legs. The `JobDef` supplies the legs + the `begin`/`complete`/`on_end` behaviour. Delegates pathfinding to the colonist's `VoxelPathfinder`. The WORK state is itself the busy guard — no separate `set_busy`.
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
| `_try_claim_and_path() -> void` | IDLE tick: select + assign + leg 0 + path (→ MOVE), or release + stay IDLE. |
| `_begin_work() -> void` | MOVE arrival: `def.begin`; instant (≤0) → `complete` + `_advance`, else → WORK. |
| `_tick_work(delta) -> void` | WORK tick: accumulate; on elapse `complete` + `_advance`; abort if target freed. |
| `_advance() -> void` | Pull the next leg via `def.get_next_leg`; re-path → MOVE, or `_end_job(true)` on null / `_end_job(false)` if the next leg is unreachable. |
| `_end_job(success) -> void` | Leave the job: `def.on_end` cleanup (return carried items, persist partial progress), `unassign`, `should_close()`→`remove_job`, → IDLE. |

### Class: Job

**Extends:** RefCounted
**Script:** `job.gd`
**Description:** A unit of colonist work — pure data + the multi-assign claim bookkeeping. Created by a producer (Colony) from a `JobDef`; colonists join via `try_assign` and leave via `unassign`; the Job leaves the board when `should_close()`. Leg behaviour lives on the `JobDef`.
**Used by:** Job Board (registry), ColonistAI (assign/leg loop), future Job Log UI.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `def` | `JobDef` | The template this Job was built from (back-ref). Owns the leg behaviour. Set by `Job.from_def`. |
| `id` | `String` | Unique id; the Job Board keys on it. |
| `labor_id` | `String` | Which Labor this is (a `LaborDef.id`). Drives priority selection. |
| `title` | `String` | Human-readable label; for the Job Log. |
| `anchor_cell` | `Vector3i` | The voxel cell targeted (a blueprint's anchor). |
| `location` | `Vector3` | World walk-target (best-effort footprint center); refined to an adjacent standing cell at navigation. |
| `target_node` | `Node` | The in-world node being worked (the Blueprint). Held weak so a freed target is detectable. |
| `max_assignees` | `int` | Max colonists that may join at once (copied from the def; 1 for construction, 3 for hauling). |
| `_assigned_colonists` | `Array[String]` | colonist_ids currently on the job. Drives the slot gate + the drain check. |
| `base_rate` | `float` | Base work-rate multiplier (forward-compat; unused this sprint). |
| `failure_count` | `int` | Times `fail` has been called; auto-remove at `_MAX_FAILURES` (3). |

**Functions:**

| Function | Description |
|---|---|
| `from_def(d: JobDef) -> Job` | Static ctor: uuid, `def` back-ref, denormalized `labor_id`/`title`/`max_assignees`. |
| `try_assign(colonist) -> bool` | Join (checks `is_available` + not-already-assigned). Pull, not push. |
| `unassign(colonist) -> void` | Leave (leg exhaustion or abort). |
| `is_assigned(id) -> bool` / `clear_assigned() -> void` | Membership check / release all (used by the failure path). |
| `is_available() -> bool` | `_assigned < max_assignees && def.is_available(self)` — the slot gate AND the labor-specific gate. |
| `should_close() -> bool` | `_assigned.is_empty() && !is_available()` — the job should leave the board. |

### Class: JobLeg

**Extends:** RefCounted
**Script:** `data/jobs/job_leg.gd`
**Description:** One leg of a job's walk→act sequence — pure routing data. A `JobDef` produces a stream of these via `get_next_leg`; `ColonistAI` walks to each `location` and runs the leg's action through `begin`/`complete` (dispatched on `kind`). Pure routing keeps legs reusable across labors (construction = one WORK leg; hauling = repeated FETCH/DELIVER legs) and lets the AI stay dumb about both.
**Properties:** `location: Vector3` (walk-target), `target_node: Node` (the per-leg node — crate/blueprint; weak, freed-detectable), `kind: int` (opaque, def-owned discriminator).

### Class: JobDef

**Extends:** Resource
**Script:** `data/jobs/job_def.gd`
**Description:** Reusable template for one kind of colonist work — one subclass per Labor, authored as a `.tres` via `script_class`. Owns data (`id`/`display_name`/`labor_id`/`max_assignees`) and **leg behaviour**: `get_next_leg` produces the next leg for a colonist (null when done), `begin` reports a leg's work duration (0 = instant), `complete` applies its effect, `on_end` cleans up on leave, `is_available` gates acceptability. Mirrors the behaviour-bearing Resource precedent (`GameAction`, `Condition`). The behaviour lives here, not on the Furniture, because it depends on Job parameters the Furniture doesn't know (e.g. a craft job's duration = `recipe.base_time × quantity`).
**Used by:** `Job` (`def` back-ref), `Colony` (`Job.from_def`), `ColonistAI` (drives the leg loop).

**Properties:** `id`, `display_name`, `labor_id` (Strings); `max_assignees: int = 1`.

**Functions (virtual — overridden per Labor):**

| Function | Description |
|---|---|
| `get_next_leg(actor, job) -> JobLeg` | The next leg for this colonist, or null when it has no further work. Base default null (finish immediately). |
| `begin(actor, leg, job) -> float` | This leg's work duration (0 = instant → `complete` same tick). Base default 0.0. |
| `complete(actor, leg, job) -> void` | Apply this leg's effect. Base default no-op. |
| `on_end(success, actor, leg, job, elapsed) -> void` | Cleanup when a colonist leaves (finish or abort). Base default no-op. |
| `is_available(job) -> bool` | Labor-specific acceptability gate (e.g. hauling: bp unsatisfied + source in stock). Base default true. |

### Class: ConstructionJobDef

**Extends:** `JobDef`
**Script:** `data/jobs/construction_job_def.gd`
**Description:** Construction labor — a **one-leg job**: walk to the blueprint, WORK over `build_time`, `Blueprint.complete` materializes it. Single-colonist (`max_assignees=1`). Headless twin of the player's `BuildAction` — no gauge/mouse/`set_busy` (WORK is the busy guard). 1× tick (skill × Stamina deferred; `begin`'s duration is the seam).

**Functions:**

| Function | Description |
|---|---|
| `get_next_leg(actor, job) -> JobLeg` | Returns the blueprint leg once (location = `job.location`, target = the bp), then null. |
| `begin(actor, leg, job) -> float` | `BuildLibrary.get_def(bp.target_def_id).build_time`; 0 if not a Blueprint / unknown def. |
| `complete(actor, leg, job) -> void` | Reset `bp.work_done = 0` and `bp.complete(actor)`. |
| `on_end(success, actor, leg, job, elapsed) -> void` | On abort (not success), persist `bp.work_done = elapsed` so a later attempt resumes. |
| `is_available(job) -> bool` | The blueprint still exists. |

### Class: HaulingJobDef

**Extends:** `JobDef`
**Script:** `data/jobs/hauling_job_def.gd`
**Description:** Hauling labor — carry materials from storage crates to a blueprint until its `material_cost` is satisfied. A multi-colonist job (`max_assignees=3`): haulers divvy a run through the blueprint's shared deposit counter (no per-colonist slices) — each independently loops FETCH → DELIVER until `has_complete_materials()`. The crate's live stock serializes concurrent haulers (two can't double-spend a plank). Phase is derived from carry state (not stored); both legs are instant (no WORK). The DELIVER leg's `deposit_from` emits `blueprint_materials_ready` on the crossing — Colony's single trigger to spawn construction.
**Constants:** `FETCH = 1`, `DELIVER = 2` (the `JobLeg.kind` discriminator).

**Functions:**

| Function | Description |
|---|---|
| `get_next_leg(actor, job) -> JobLeg` | bp gone/satisfied → null; carrying a needed material → DELIVER; else FETCH from the nearest source crate (`registry.find_source`), or null if no source. |
| `complete(actor, leg, job) -> void` | FETCH: `crate.transfer_to(colonist.inventory, id, remaining)` per unsatisfied material (skips if bp became satisfied en route). DELIVER: `bp.deposit_from(actor)`. |
| `on_end(success, actor, leg, job, elapsed) -> void` | Return any surplus on the colonist to the nearest crate (`registry.nearest_crate`). |
| `is_available(job) -> bool` | bp valid, unsatisfied, and some crate holds a needed material. |

### Class: JobBoard

**Extends:** Node
**Script:** `job_board.gd`
**Description:** The colony's job registry + selection. Owned by the Colony autoload as a child Node. Producers add Jobs; consumers (`ColonistAI`) query `get_best_job_for` then assign via `Job.try_assign` directly. Holds the registry + selection + the dead-job prune — no assignment bookkeeping (that's on the `Job`) and no pathfinding/work.
**Used by:** Colony (producer), ColonistAI (consumer), future Job Log UI.
**Lifecycle:** Created and added as a child by `Colony._ready`.

**Signals:** `job_failed(job_id, reason)` (direct listeners). (`job_logged` is relayed via EventBus.)

**Functions:**

| Function | Description |
|---|---|
| `add_job(job) -> void` | Register (assigns an id if the creator didn't). |
| `remove_job(job_id) -> void` | Drop by id. |
| `get_job` / `has_jobs` / `get_jobs` | Inspection / debug / future UI. |
| `get_best_job_for(colonist) -> Job` | First `_prune_dead_jobs()`, then best `is_available()` job whose Labor is enabled (highest priority, nearest). Does NOT assign. (L1 skill gate deferred.) |
| `_prune_dead_jobs() -> void` | Drop jobs that are `!is_available() && unassigned` (no-source haul, satisfied-but-drained, cancelled). |
| `fail(job_id, reason) -> void` | Record a failure: increment `failure_count`, clear assignees, emit `job_failed`, relay `job_logged`; auto-remove at `_MAX_FAILURES` (3). (Failure path not driven from the leg loop yet — the prune handles haul's no-source removal.) |

### Class: StorageRegistry

**Extends:** Node
**Script:** `inventory/storage_registry.gd`
**Description:** Live index of the colony's storage crates, so hauling jobs can find a source for a blueprint's still-needed materials. Owned by Colony as a child Node; pointed at the current map's `FurnitureContainer` by `MapWiring` on each map load. No registration — `find_source`/`has_source_for`/`nearest_crate` scan the container's live children each call, so freed crates are simply absent (no stale refs, no unregister hook).

**Functions:**

| Function | Description |
|---|---|
| `on_map_wired(container) -> void` | Bind to the current map's furniture container (called by `MapWiring`). |
| `find_source(item_ids, near) -> Furniture` | Nearest crate whose `StorageInventory` holds any of `item_ids` (straight-line; reachability verified later by the pathfinder). Null if none. |
| `has_source_for(item_ids) -> bool` | Any crate holds any of `item_ids`. Used by the producer decision + hauling's `is_available`. |
| `nearest_crate(near) -> Furniture` | Nearest crate regardless of contents (for surplus return). |

### Class: VoxelPathfinder

**Extends:** Node
**Script:** `voxel_pathfinder.gd`
**Description:** Voxel A\* pathfinder with an **injected walkability predicate**. Intentionally generic — it knows nothing about voxels, furniture, or blueprints. The wiring layer (`MapWiring.wire_colonists`) composes a per-cell `is_walkable(Vector3i)` Callable from `VoxelGrid` solidity + `FurnitureLayer`/`BlueprintLayer` occupancy and injects it via `set_walkability`. Output is world-space `Vector3` waypoints sized for `Colonist.set_path` (whose locomotion zeroes Y).
**Used by:** ColonistAI (path requests), Colonist (`pathfinder` child ref).

**Neighbor model (MVP):** 4-connected horizontal on the standing Y — correct for flat terrain. Step-up/down + multi-level are deferred; the floor-based predicate validates every cell, so widening neighbors later is localized.

**Functions:**

| Function | Description |
|---|---|
| `set_walkability(predicate: Callable) -> void` | Inject the per-cell walkability predicate (composed by the wiring layer). |
| `find_path(start_cell, target_cell) -> Array[Vector3i]` | Core A\* over cells (Dictionary-backed open/closed, linear min-f scan). Empty if no path / predicate unset / target not standable / start==target. `_MAX_EXPLORED = 4000` backstop. |
| `find_stand_cell(world_pos) -> Vector3i` | Resolve a standable cell near a world position (scan down then up ±3 Y). Handles the spawn-drop resting height. |
| `find_stand_near_cell(center, max_radius = 4) -> Vector3i` | Nearest walkable cell to `center` via a horizontal ring search (Chebyshev rings, min Euclidean within the first non-empty ring). For targets on a blocked footprint — the colonist stands adjacent, never on it. Returns `center` unchanged if already walkable or none found within radius. |
| `find_path_world(start_world, target_world) -> Array[Vector3]` | World→stand-cell→A\*→world. Use only when the target is standable terrain, NOT a blocked footprint. |
| `find_path_to_adjacent(start_world, target_world, max_radius = 4) -> Array[Vector3]` | Like `find_path_world`, but resolves the TARGET via `find_stand_near_cell` so the colonist reaches a point on a blocked footprint (a blueprint or crate). Entry point for `ColonistAI` legs. |
| `to_world_waypoints(cells) -> Array[Vector3]` | Cell waypoints → world-space centers. |
