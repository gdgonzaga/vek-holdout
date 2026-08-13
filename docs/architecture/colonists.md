# Subsystem: Colonists

Colonist entities, roster (in Colony autoload), Job Board, labor AI, raid stances. GDD §6.

> **Sprint scope (built):** place a Workshop blueprint → `Colony` creates a construction Job → a colonist claims it on the next idle poll → A\* walks to a stand-adjacent cell of the blueprint → on arrival completes the Job and returns to idle. Arrival completes the **Job** only; the blueprint stays placed for the player to build manually (the real build is deferred — see below).
>
> **Deferred (GDD §6, not yet built):** the work-tick build (skill × Stamina rate → `BlueprintLayer.complete_blueprint`), `colonist_combat.gd` (§6.7), recruitment (§6.9), the `RaidStance` enum (§6.2), roster save/restore, and `colonist_ai_statemachine.gd` (an unreferenced orphan stub superseded by the inline state enum in `colonist_ai.gd`).
>
> **Labors (GDD §6.4):** a *Labor* is a category of work, declared as a `LaborDef` resource under `data/labors/` (see [Data Schemas](data-schemas.md)) and referenced everywhere by its String `id`. Five ship today — `construction`, `crafting`, `hauling`, `mechanics`, `smelting` (Repair/Farming/Cooking post-MVP). The labor id is the join key of the subsystem: a `Job` carries one `labor_id` (what kind of work it is), and a `Colonist`'s `labor_priorities` Dict (`{labor_id: 0–5 weight}`) decides which jobs that colonist will accept — `JobBoard.get_best_job_for` skips any job whose labor has weight 0 for that colonist. `ColonistDef.default_labor_priorities` enables `construction`, `crafting`, and `hauling` at priority 1 by default (mechanics/smelting start disabled), so a fresh colonist picks up construction jobs — the only labor producing jobs today, via blueprint placement.

## Files

| File | Type | Responsibility |
|---|---|---|
| `colonist.gd` | Script | The colonist entity (`Colonist extends CharacterBody3D`). HP, labor priorities, raid stance, current Job, and path-following locomotion (`set_path` / `has_arrived`). Holds `skill_set` / `stamina_component` / `pathfinder` child refs. Does NOT own job discovery (Job Board does). |
| `colonist.tscn` | Scene | Capsule mesh + CollisionShape + `SkillSet` / `StaminaComponent` / `ColonistAI` / `ColonistCombat` (bare node, no script yet) / `VoxelPathfinder` children. |
| `colonist_ai.gd` | Script | The colonist build-job loop: IDLE → poll Job Board (0.5s throttle) → claim → path (A\*) → MOVE → on arrival `complete` the Job → IDLE. Does NOT own pathfinding (delegates to `VoxelPathfinder`). |
| `voxel_pathfinder.gd` | Script (component) | Voxel A\* with an **injected walkability predicate** — intentionally generic (knows nothing about voxels/furniture/blueprints). `find_path_to_adjacent` resolves a stand-adjacent cell so a colonist can reach a blocked footprint (a blueprint). See class reference. |
| `job.gd` | Script (`RefCounted`) | Pure-data unit of work (`Job`): `id`, `labor_id`, `title`, `anchor_cell`, `location`, `target_node`, `base_rate`, `claimed_by`, `failure_count`. No behaviour — the Job Board owns transitions. |
| `job_board.gd` | Script (on Colony) | Job registry + lifecycle: `add_job` / `get_best_job_for` / `claim` / `unclaim` / `complete` / `fail`. Atomic claim; `fail` auto-removes at 3 failures. Early-MVP policy: log + skip + auto-remove. |
| `skill_set.gd` | Script (component) | Colocated here for the colonist sprint (stub — see [Skills](skills.md)). |
| `stamina_component.gd` | Script (component) | Colocated here for the colonist sprint (stub — see [Energy](energy.md)). |
| `../autoloads/colony.gd` | Autoload | Roster + Job Board. Produces construction Jobs from `EventBus.blueprint_placed` / `blueprint_removed`. Cross-scene (colonists persist base↔POI). |
| `../data/labors/` | Data | `LaborDef` resources — the canonical labor ids (Construction, Crafting, Hauling, Mechanics, Smelting; Repair/Farming/Cooking post-MVP). See [Data Schemas](data-schemas.md). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `colonist_died(colonist_id)` | `colonist.gd` | Colony, HUD, Memorial | Yes | Colonist Death |
| `job_claimed(job_id, colonist_id)` | `job_board.gd` | (internal) | No | Colonist walks to a blueprint |
| `job_failed(job_id, reason)` | `job_board.gd` | Job Log UI | No | Job Failure Handling |
| `job_logged(entry)` | `job_board.gd` | Job Log UI (when open) | Yes | Job Failure Handling |

## Flow Trace: Job lifecycle (produce → claim → resolve)

The Job Board is the hub: producers add Jobs, consumers (`ColonistAI`) query + claim, and the board owns every state transition on a Job's `claimed_by` / `failure_count`. The board itself never pathfinds or builds — it is a registry + atomic-transition service. Two views of the same pipeline: this flow is the board's state machine; the walk flow below is the colonist's spatial half.

**Trigger:** A blueprint is placed (`EventBus.blueprint_placed`).

1. **Produce** — `Colony._on_blueprint_placed(target_def_id, anchor)` builds `Job{labor_id="construction", title="Build <id>", anchor_cell=anchor, location=footprint-center}` (via `FurnitureLayer.world_origin`) and calls `JobBoard.add_job`, which assigns a uuid `id` if the creator didn't. The Job sits on the board with `claimed_by == ""`.
2. **Select** — a colonist's `ColonistAI`, throttled to once per 0.5s while IDLE, calls `JobBoard.get_best_job_for(colonist)`. Selection filters to unclaimed jobs whose Labor is enabled for that colonist — `colonist.labor_priorities.get(job.labor_id, 0) > 0` — then ranks by highest priority, breaking ties by nearest `global_position.distance_squared_to(job.location)`. Returns the best Job (or `null`); **it does not claim.** (The documented L1 skill gate is deferred until skills wire into the work loop — ignored here.)
3. **Claim** — `ColonistAI` calls `JobBoard.claim(job.id, colonist.colonist_id)`: an atomic compare-and-set on `claimed_by` (`"" → colonist_id`). On success it sets the claim, emits `job_claimed(job_id, colonist_id)`, and returns the Job; on a lost race (another colonist claimed it first, or it was removed) it returns `null` and the next poll retries.
4. **Resolve — happy path** — on arrival (see the walk flow below) `ColonistAI._finish_job` calls `JobBoard.complete(job.id)`, which erases the Job from the board. The blueprint itself is untouched by the board — sprint scope is "walks to it"; the real build (`work-tick → BlueprintLayer.complete_blueprint`) is deferred.
5. **Resolve — fail path** — `JobBoard.fail(job.id, reason)` increments `failure_count`, releases the claim (`claimed_by = ""`), emits `job_failed(job_id, reason)` locally, and relays a `job_logged(entry)` Dictionary through `EventBus` for the Job Log UI. At `failure_count >= _MAX_FAILURES (3)` the board auto-erases the Job — the early-MVP policy is *log + skip + auto-remove*. The blueprint stays placed either way.

> **`fail` is implemented but not driven this sprint.** `ColonistAI` releases a transiently-unreachable job with `unclaim` + throttled retry (the 0.5s poll bounds it) rather than `fail`, so a no-path never burns a `failure_count`. True-unreachable thrash (a per-colonist blacklist, or `fail`-on-no-path) is a documented MVP gap; on the flat base map it never arises.

**End state:** Job removed from the board — completed on arrival, or auto-removed after 3 failures. The blueprint's lifetime is independent of the board: cancelling or completing a blueprint emits `blueprint_removed` → `Colony._on_blueprint_removed` drops any matching Job by anchor (idempotent — erasing an already-removed id is a harmless no-op).

## Flow Trace: Colonist walks to a blueprint (claim → path → arrive)

The spatial counterpart to the lifecycle flow: once a Job is claimed, this is how the colonist actually reaches it. The pathing is the load-bearing part — the Job's `location` is the blueprint's footprint-center, which the walkability predicate marks **blocked**, so the pathfinder must route the colonist to a cell *adjacent* to the footprint, never onto it.

**Trigger:** `ColonistAI._try_claim_and_path` just claimed a Job (lifecycle step 3); `colonist.current_job` is set.

1. `ColonistAI` calls `_colonist.pathfinder.find_path_to_adjacent(_colonist.global_position, claimed.location)`. The function chain inside that one call:
   - **`find_stand_cell(start_world)`** — a vertical scan (down then up, ±`_STAND_SCAN = 3` cells) settles the colonist's *own* standing cell, smoothing the spawn-drop resting height and minor floor ambiguity. Falls back to the floored cell if none standable in the window.
   - **`target_base = Vector3i(floor(target_world.{x,y,z}))`** — the blueprint's footprint-center cell. It is **blocked** by the injected predicate, so it cannot be the path target.
   - **`find_stand_near_cell(target_base, max_radius = 4)`** — a horizontal ring search. Chebyshev rings expand r = 1 → 4; the predicate rejects every footprint cell (and any furniture/terrain), and the **first non-empty ring** returns its min-Euclidean-distance cell → the nearest walkable cell **adjacent** to the footprint. Returns `target_base` unchanged if nothing walkable is in range (the A\* below then fails clean).
   - **`find_path(start_cell, target_cell)`** — A\* over cells: 4-connected neighbors, Manhattan heuristic (admissible for unit step costs), lazy neighbor expansion gated cell-by-cell by the injected predicate; Dictionary-backed open/closed sets with a linear min-f scan; `_MAX_EXPLORED = 4000` backstop against runaway searches. Returns cell waypoints start → target, or empty if unreachable / predicate unset / start == target.
   - **`to_world_waypoints(cells)`** — each cell → `Vector3(cell) + (0.5, 0.5, 0.5)` (XZ-centered world points; Y is informative only — locomotion navigates the XZ plane).
2. If the returned path is **empty** (no reachable adjacent cell): `ColonistAI` calls `JobBoard.unclaim(job.id, colonist_id)`, clears `current_job`, and stays IDLE — the 0.5s throttle bounds the retry (see the `fail` note above).
3. Otherwise `ColonistAI` calls `_colonist.set_path(waypoints)`: `Colonist.set_path` does `_path.assign(waypoints)` (per-element copy into the typed `Array[Vector3]` — a bare `duplicate()` would return an untyped Array, which 4.7 won't assign) and resets `_path_index = 0`. AI state → MOVE.
4. **Locomotion** — `Colonist._physics_process` applies gravity, then `_follow_path`: each frame, take the horizontal vector to `_path[_path_index]` (Y zeroed), move at `colonist_def.base_move_speed`; once within `_ARRIVAL_THRESHOLD = 0.2` of the waypoint, advance `_path_index`. `has_arrived()` returns `_path_index >= _path.size()`.
5. **Arrival** — in MOVE, `ColonistAI._process` watches `has_arrived()`; on true, `_finish_job` calls `JobBoard.complete(current_job.id)` (lifecycle happy path), clears `current_job`, and returns to IDLE with the poll clock reset. The blueprint stays placed.

> **Why the ring search is the crux:** the injected predicate (composed by `MapWiring.wire_colonists._compose_walkability`) defines a cell as walkable iff it is air, has a solid floor below, and is **not** furniture or a blueprint. The footprint-center is therefore rejected for free — the pathfinder never needs to know the footprint's shape or the def's `dimensions`. The ring search simply finds the nearest *free* neighbour, giving clean decoupling between the AI, the pathfinder, and the build layers.

**End state:** Colonist stands on a cell adjacent to the blueprint footprint; Job completed on the board; colonist idles.

## Class Reference

### Class: Colony

**Extends:** Node (autoload)
**Script:** `autoloads/colony.gd`
**Description:** The colony roster and Job Board. Cross-scene because colonists persist during expeditions. Owns colonist lifecycle (spawn/reparent into the current map's `ColonistContainer`) and produces construction Jobs from blueprint placement.
**Used by:** HUD (roster UI), Colony Management screen, Combat (damage targets), Raids (stance execution).
**Lifecycle:** `_ready` creates the `JobBoard` child Node and connects `EventBus.blueprint_placed` → `_on_blueprint_placed`, `blueprint_removed` → `_on_blueprint_removed`. `on_map_wired` is called by `MapWiring.wire_colonists` on every map load.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `colonists` | `Array[Colonist]` | Active colonists (capped at `MVP_CAP = 5`). Node instances live in the current map's `ColonistContainer`; this Array is the cross-scene authority. |
| `job_board` | `JobBoard` | The Job Board (a child Node). |

**Functions:**

| Function | Description |
|---|---|
| `on_map_wired(container: Node3D, spawn_positions: Array) -> void` | Empty roster → spawn one colonist per `ColonistSpawn` marker (up to `MVP_CAP`); non-empty → reparent existing nodes into the new map (the base↔POI persist idiom). |
| `add_colonist(c: Colonist) -> void` | Recruits a colonist (random event / radio, post-MVP). Respects the cap. |
| `remove_colonist(colonist_id: String) -> void` | Drop a colonist by id (death or departure); frees the node. |
| `_on_blueprint_placed(target_def_id, anchor) -> void` | Creates a construction Job at the blueprint's anchor (location = footprint center) and adds it to the board. |
| `_on_blueprint_removed(target_def_id, anchor) -> void` | Removes any Job targeting that anchor (fires on both cancel and completion). Idempotent. |

### Class: Colonist

**Extends:** CharacterBody3D
**Script:** `colonist.gd`
**Description:** A colonist entity. Holds identity, labor priorities, raid stance, and the current Job; runs gravity + path-following locomotion in `_physics_process`. Holds `@onready` refs to its `SkillSet` / `StaminaComponent` / `VoxelPathfinder` children. Does NOT own job discovery — `ColonistAI` (a child node) drives claim/path/arrive against the Job Board.
**Used by:** Colony (roster), Combat (target, future), Colonist Management screen.
**Lifecycle:** `_ready` assigns a uuid `colonist_id`, copies identity/labor/stance from the `ColonistDef`, resolves the component child refs, and seeds HP.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `colonist_id` | `String` | Unique id (`Tools.generate_uuid()`). |
| `display_name` | `String` | Shown in UI. |
| `colonist_def` | `ColonistDef` | `[export]` The static def (identity, stats, default labor priorities). See [Data Schemas](data-schemas.md). |
| `labor_priorities` | `Dictionary` | Labor id → 0–5 priority weight. Copied from the def at `_ready`. |
| `raid_stance` | `int` | Fight / Fight-Post / Shelter (`RaidStance` enum deferred — stored as int for now). |
| `current_job` | `Job` | The claimed Job while MOVE-ing (null while idle). Not serialized. |
| `skill_set` | `SkillSet` | `@onready` child ref. See [Skills](skills.md). |
| `stamina_component` | `StaminaComponent` | `@onready` child ref. See [Energy](energy.md). |
| `pathfinder` | `VoxelPathfinder` | `@onready` child ref. Drives `set_path`. |

**Functions:**

| Function | Description |
|---|---|
| `set_path(path: Array) -> void` | Feed world-space waypoints (from `VoxelPathfinder`); resets any in-progress path. Empty path leaves the colonist standing. |
| `has_arrived() -> bool` | True when every waypoint has been consumed (or no path was set). |
| `take_damage(amount: int, source: Node) -> void` | Applies damage; at HP 0 emits `EventBus.colonist_died`. |
| `heal(amount: int) -> void` | Restores HP (clamped to the def's `max_hp`). |
| `set_labor_priority(labor_id: String, priority: int) -> void` | Mutates a labor priority weight. |
| `set_raid_stance(stance: int) -> void` | Mutates the raid stance. |
| `serialize() -> Dictionary` / `deserialize(data) -> void` | SaveSystem contract — scalar/dict state + world position. Excludes `current_job` and component sub-state. |

### Class: Job

**Extends:** RefCounted
**Script:** `job.gd`
**Description:** A unit of colonist work — pure data. Created by a producer (Colony, on `blueprint_placed`) and resolved through the Job Board lifecycle (`claim → complete` / `fail`). The Job Board owns the registry and transitions; `ColonistAI` drives the claim/path loop.
**Used by:** Job Board (registry), ColonistAI (claim/path), future Job Log UI.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `id` | `String` | Unique id (`Tools.generate_uuid()`); the Job Board keys on it. |
| `labor_id` | `String` | Which Labor this is (a `LaborDef.id`, e.g. `"construction"`). Drives priority selection. |
| `title` | `String` | Human-readable label (e.g. `"Build workshop"`); for the Job Log. |
| `anchor_cell` | `Vector3i` | The voxel cell targeted (a blueprint's anchor). Authoritative placement ref. |
| `location` | `Vector3` | World point a colonist walks toward (best-effort footprint center); refined to a real adjacent standing cell at navigation time. |
| `target_node` | `Node` | The in-world node being worked (e.g. the Blueprint), as a weak ref. Forward-compat; unused this sprint. |
| `base_rate` | `float` | Base work-rate multiplier (GDD §6 effective-rate formula). Forward-compat; unused this sprint. |
| `claimed_by` | `String` | `colonist_id` of the claimer, or `""` when unclaimed. Mutated only via the Job Board. |
| `failure_count` | `int` | Times `fail` has been called; the board auto-removes at `_MAX_FAILURES` (3). |

### Class: JobBoard

**Extends:** Node
**Script:** `job_board.gd`
**Description:** The colony's job registry + lifecycle. Owned by the Colony autoload as a child Node. Producers add Jobs; consumers (`ColonistAI`) query `get_best_job_for` + `claim`. Holds the registry and the atomic claim/fail/complete transitions — it does no pathfinding or work.
**Used by:** Colony (producer), ColonistAI (consumer), future Job Log UI.
**Lifecycle:** Created and added as a child by `Colony._ready`.

**Signals:**

| Signal | Description |
|---|---|
| `job_claimed(job_id, colonist_id)` | A claim succeeded (board-internal / direct listeners). |
| `job_failed(job_id, reason)` | A job failed this attempt (direct listeners). |

**Functions:**

| Function | Description |
|---|---|
| `add_job(job: Job) -> void` | Register a job (assigns an id if the creator didn't). |
| `remove_job(job_id: String) -> void` | Drop a job by id. |
| `get_job(job_id) -> Job` / `has_jobs() -> bool` / `get_jobs() -> Array[Job]` | Inspection / debug / future UI. |
| `get_best_job_for(colonist: Colonist) -> Job` | Best unclaimed job whose Labor is enabled for the colonist (`labor_priorities[labor_id] > 0`): highest priority, then nearest by proximity. Does NOT claim. (The documented L1 skill gate is deferred until skills wire into the work loop.) |
| `claim(job_id, colonist_id) -> Job` | Atomic claim (CAS on `claimed_by`); returns the Job or `null` if lost/missing. Emits `job_claimed`. |
| `unclaim(job_id, colonist_id) -> void` | Release a claim without the failure penalty (reassign / retry). No-op if not held by `colonist_id`. |
| `complete(job_id) -> void` | Job finished successfully — drop from the board. |
| `fail(job_id, reason) -> void` | Record a failure: increment `failure_count`, release the claim, emit `job_failed`, relay `job_logged` via EventBus; auto-remove at `_MAX_FAILURES` (3). |

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
| `find_path_to_adjacent(start_world, target_world, max_radius = 4) -> Array[Vector3]` | Like `find_path_world`, but resolves the TARGET via `find_stand_near_cell` so the colonist reaches a point on a blocked footprint (a blueprint). Entry point for `ColonistAI` build jobs. |
| `to_world_waypoints(cells) -> Array[Vector3]` | Cell waypoints → world-space centers. |
