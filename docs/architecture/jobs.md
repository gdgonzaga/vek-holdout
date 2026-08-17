# Subsystem: Jobs

The colony's job system — `JobDef` behaviour templates, the `JobLeg` walk→act pattern, the `JobBoard` registry, and four shipped labors (Construction, Hauling, Crafting, Harvesting). Producers (currently [Colony](colonists.md) from blueprint + crafting-order events) create `Job` instances; consumers (`ColonistAI`) poll the board, assign, and execute legs. GDD §6.

> **Sprint scope (built):** colonists work **multi-leg jobs**. A `JobDef` produces a stream of `JobLeg`s (walk-to → act); `ColonistAI` walks each leg and runs the def's `begin`/`complete` on arrival. Four labors ship:
> - **Construction** — a blueprint with no unmet `material_cost` (costless or pre-satisfied) → a one-leg job: walk to a stand-adjacent cell, WORK over `build_time`, `Blueprint.complete` materializes it.
> - **Hauling** — any blueprint with an unmet `material_cost` → up to `max_assignees` haulers divvy a run through the sink's shared deposit counter: each loops FETCH (crate → carry inventory) → DELIVER (`deposit_from` on the [MaterialSink](#jobs-furniture) — blueprints and crafting stations today) until `has_complete_materials()`. The DELIVER that crosses the threshold emits the sink's materials-ready signal (`blueprint_materials_ready` / `crafting_materials_ready`) → `Colony` spawns the follow-on job.
> - **Crafting** — a queued recipe at a [CraftingStation](crafting.md) → hauling feeds the order's inputs (the station is a MaterialSink) → on the crossing `Colony` spawns a one-leg craft job: WORK over `recipe.base_time ÷ skill multiplier`, then outputs to the crafter's carry (overflow to the nearest crate) and the order clears.
- **Harvesting** — a placed or spawned harvestable resource node (e.g. tree) with `HarvestParams` → marked via player interaction (`ToggleHarvestAction`) → `Colony` spawns a one-leg harvest job: WORK over `work_time ÷ skill multiplier`, then `Harvestable.complete` resolves yields to colonist carry inventory and removes the node.
>
> **Multi-assign:** a `Job` may hold several colonists at once (`try_assign`/`unassign`); **one colonist finishing ≠ job done** — the job leaves the board only when `should_close()` (no assignees left AND the def's `should_close` says dead). `JobBoard.get_best_job_for` prunes `should_close()` jobs on each poll.
>
> **Drought persistence:** a haul job's *claimability* (`is_available`: sink valid + unsatisfied + a crate stocks a needed item) is separate from its *lifetime* (`should_close`: sink satisfied or gone). When crates run dry the job becomes invisible to selection but stays registered — the 0.5s idle poll re-checks stock, and a restocked crate resumes hauling with no producer event. A stalled hauler's null leg is not a completion (`job_complete` false: no skill XP, a "waiting for materials" log line).
>
> **Deferred (GDD §6, not yet built):** the Stamina work-speed factor (the skill factor is live — `begin()` durations divide by `SkillSet.get_multiplier(labor_id)`, [Skills](skills.md); StaminaComponent is still a stub), mechanics/smelting jobs.
>
> **Known gaps:** a job `fail`-removed at 3 aborts won't respawn on restock (the producer only fires on placement); save-load doesn't recreate jobs for restored blueprints (see [Colonists](colonists.md)); there is no idle fallback activity yet (no wander, no rest — Stamina is a stub), so a colonist with no claimable work stands still.

**Labors (GDD §6.4):** a *Labor* is a category of work, declared as a `LaborDef` resource under `data/labors/` (see [Data Schemas](data-schemas.md)) and referenced everywhere by its String `id`. Six ship today — `construction`, `crafting`, `hauling`, `harvesting`, `mechanics`, `smelting` (Repair/Farming/Cooking post-MVP). The labor id is the join key of the subsystem: a `Job` carries one `labor_id` (what kind of work it is), and a [Colonist](colonists.md)'s `labor_priorities` Dict (`{labor_id: 0–5 weight}`) decides which jobs that colonist will accept — `JobBoard.get_best_job_for` skips any job whose labor has weight 0 for that colonist.

## Files

| File | Type | Responsibility |
|---|---|---|
| `data/jobs/job_def.gd` | Script (Resource) | Abstract behaviour template for a labor type — `get_next_leg`/`begin`/`complete`/`on_end`/`is_available`/`should_close`/`job_complete` virtual contract + `conditions`/`meets_requirements` actor gating. Subclassed per labor. |
| `data/jobs/job_leg.gd` | Script (RefCounted) | Pure routing data for one step of a job: `location`, `target_node`, `kind`. No behaviour — the `JobDef` dispatches on `kind`. |
| `data/jobs/construction_job_def.gd` | Script (Resource) | Construction labor: single-leg timed build — `Blueprint.complete` on finish, persists `work_done` on abort; `begin` divides `build_time` by the skill multiplier. |
| `data/jobs/hauling_job_def.gd` | Script (Resource) | Hauling labor: multi-leg FETCH/DELIVER loop — deposit materials from crates into any MaterialSink via colonist carry inventory; tool-tagged items survive the surplus dump. |
| `data/jobs/crafting_job_def.gd` | Script (Resource) | Crafting labor: single-leg timed craft at a [CraftingStation](crafting.md) — skill-scaled `begin`, outputs + order-clear on `complete`, recipe conditions ANDed into `meets_requirements`. |
| `data/jobs/harvest_job_def.gd` | Script (Resource) | Harvesting labor: single-leg timed harvest of marked resource nodes — `Harvestable.complete` on finish, persists `work_done` on abort; `begin` divides `work_time` by the skill multiplier. |
| `subsystems/harvesting/harvestable.gd` | Script (Node component) | Capability component attached by FurnitureLayer to furniture declaring `harvest_params`: tracks `is_marked_for_harvest` and `work_done`, and resolves harvest completion. |
| `data/capability_params/harvest_params.gd` | Script (Resource) | Capability sub-resource on `FurnitureDef` defining `yields: Array[ItemAmount]`, `work_time: float`, and `respawn_time: float`. |
| `data/actions/harvest_action.gd` | Script (GameAction) | Player direct LMB harvesting action with timed `ActionProgress` HUD gauge and skill XP scaling. |
| `data/actions/toggle_harvest_action.gd` | Script (GameAction) | E interaction menu action to toggle `is_marked_for_harvest` on a targeted node. |
| `construction.tres` / `hauling.tres` / `crafting.tres` / `harvest.tres` | Data | `JobDef` resources (labor_id, max_assignees, conditions). See [Data Schemas](data-schemas.md). |
| `../furniture/material_sink.gd` | Script (static helper) | The duck-typed MaterialSink contract (4 methods) + `is_material_sink(node)` check. Blueprints and CraftingStation implement it. |
| `../data/conditions/` | Data + scripts | Leaf conditions reusable on JobDefs (`MinSkillCondition`, `HasItemCondition`) and ActionOptions. See [Actions](actions.md). |
| `colonists/job.gd` | Script (RefCounted) | Per-placement job instance — pure data + multi-assign bookkeeping (`try_assign`/`unassign`/`is_available`/`should_close`, `_assigned_colonists`). Leg behaviour lives on the `JobDef`. |
| `colonists/job_board.gd` | Script (on Colony) | Job registry + selection: `add_job` / `get_best_job_for` / `remove_job` / `fail`. Selection filters `Job.is_available()` + `meets_requirements` and prunes dead jobs each poll. Assignment lives on the `Job`, not here. |
| `../autoloads/colony.gd` | Autoload | **Producer role:** creates construction/haul `Job`s from `EventBus.blueprint_placed`; chains hauling→construction on `blueprint_materials_ready`; chains crafting order→haul on `crafting_order_queued` and haul→craft on `crafting_materials_ready`. Owns `JobBoard` + `StorageRegistry`. See [Colonists](colonists.md). |
| `../inventory/storage_registry.gd` | Script (on Colony) | Live index of storage crates: `find_source` / `has_source_for` / `nearest_crate`. Used by hauling to locate source/destination crates. See [Inventory](inventory.md). |
| `../data/labors/` | Data | `LaborDef` resources — the canonical labor ids (Construction, Crafting, Hauling, Mechanics, Smelting). See [Data Schemas](data-schemas.md). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `blueprint_materials_ready(target_def_id, anchor, blueprint)` | `blueprint.gd` (`deposit_from`) | Colony | Yes | Haul → construction chain (single-fire per blueprint) |
| `crafting_order_queued(station, anchor)` | `crafting_station.gd` (`queue_recipe`) | Colony | Yes | Craft order → haul chain ([Crafting](crafting.md)) |
| `crafting_materials_ready(station, anchor)` | `crafting_station.gd` (`deposit_from`) | Colony | Yes | Haul → craft chain, single-fire per order ([Crafting](crafting.md)) |
| `harvest_mark_toggled(furniture, anchor, is_marked)` | `harvestable.gd` (`set_marked`) | Colony | Yes | Resource mark → Harvest lifecycle |
| `job_failed(job_id, reason)` | `job_board.gd` | Job Log UI | No | Job Failure Handling |
| `job_logged(entry)` | `job_board.gd` | Job Log UI (when open) | Yes | Job Failure Handling |

## Flow Trace: Job lifecycle (produce → assign → resolve)

The Job Board is the registry; producers add Jobs, consumers (`ColonistAI`) select + assign via `Job.try_assign` (assignment lives on the Job, multi-colonist). The board never pathfinds or builds. Two views of the same pipeline: this flow is the board/job state machine; the walk flow below is the [colonist's](colonists.md) spatial half.

**Trigger:** A blueprint is placed (`EventBus.blueprint_placed`) — or a player queues a craft (`EventBus.crafting_order_queued`; the same chain with a [CraftingStation](crafting.md) playing the blueprint's role).

1. **Produce (decide haul vs construct)** — `Colony._on_blueprint_placed(target_def_id, anchor, blueprint)`:
   - If the blueprint has an unmet `material_cost` → build a **haul** `Job` from `HAULING_DEF` (`title="Haul materials for <id>"`, `max_assignees` from the def), **regardless of current stock** — while no crate stocks a needed item the job drought-waits on the board (unclaimable but not dead; see Drought persistence above).
   - Else (costless or pre-satisfied) → `_spawn_construction_job`.
   Both bind `anchor_cell=anchor`, `location=footprint-center` (via `FurnitureLayer.world_origin`), `target_node=blueprint`, then `JobBoard.add_job`. `Job.from_def` denormalizes `labor_id`/`title`/`max_assignees` from the def and mints a uuid `id`. The crafting twin: `_on_crafting_order_queued` binds a `HAULING_DEF` job to the **station** (`target_node` = the CraftingStation node — it implements the same sink contract), deduped by anchor + def.
2. **Select** — a colonist's `ColonistAI`, throttled to once per 0.5s while IDLE, calls `JobBoard.get_best_job_for(colonist)`. The board first `_prune_dead_jobs()` (drop unassigned `should_close()` jobs), then filters to `is_available()` jobs whose Labor is enabled (`labor_priorities[labor_id] > 0`) and whose def requirements the colonist meets (`def.meets_requirements` — the `conditions` array, evaluated fresh every poll), ranks by highest priority, ties by nearest `distance_squared_to(job.location)`. Returns the best Job (or `null`); **it does not assign.** A drought-waiting haul job is skipped here (unclaimable) but not pruned — a restocked crate makes it claimable on a later poll.
3. **Assign** — `ColonistAI` calls `job.try_assign(colonist)`: the Job checks `is_available()` (slot under `max_assignees` AND the def's labor-specific gate), that the colonist isn't already assigned, and re-checks `meets_requirements` (the authoritative condition gate), then appends its id to `_assigned_colonists`. Pull, not push — this only registers; the colonist asks `get_next_leg` when ready. Returns false on a lost slot race or a condition that flipped mid-poll; the next poll retries.
4. **Resolve — happy path (legs)** — see the walk flow. On arrival at each leg the AI runs `job.def.begin`/`complete`; `_advance` pulls the next leg (or `_end_job` when `get_next_leg` returns null). A null leg is a clean finish only when `def.job_complete(job)` says so — a stalled hauler (drained crates, sink still short) gets `success=false` (no skill XP) and a "waiting for materials" `GameLog.colony` entry. For hauling, the DELIVER leg's `deposit_from` crossing `has_complete_materials` emits the sink's ready signal — `blueprint_materials_ready` → `Colony._on_blueprint_materials_ready` → `_spawn_construction_job`, or `crafting_materials_ready` → `_spawn_craft_job` (both guarded against a duplicate at the anchor). When the last assignee leaves and `should_close()` is true, the AI removes the Job; a drought-waiting haul job survives (its def overrides `should_close`).
5. **Resolve — fail path** — aborts (a freed leg target mid-MOVE/mid-WORK, an unreachable next leg, an unreachable leg-0 claim) run the normal `_end_job(false)` cleanup, then `JobBoard.fail(job.id, reason)`: increments `failure_count`, clears assignees, emits `job_failed` locally, relays `job_logged` via EventBus, auto-erases at `_MAX_FAILURES (3)` — which also bounds the unreachable claim→release thrash. A stalled-but-alive job (a haul drought) deliberately does not route through `fail`: stalls aren't failures, and `fail` counts toward removal.

**End state:** Job removed from the board — by the last assignee's `should_close()` on completion, or pruned/`fail`-removed otherwise. The blueprint's lifetime is independent: cancelling or completing one emits `blueprint_removed` → `Colony._on_blueprint_removed` drops any matching Job by anchor (idempotent). A station's furniture persists across orders — its jobs close through "order gone / sink satisfied" (`CraftingJobDef.should_close`) or the freed-station guard, not through removal events.

## Flow Trace: Colonist works a job (assign → leg loop → arrive)

The spatial counterpart to the lifecycle flow. A job is a sequence of legs; the AI walks each and acts on arrival. The pathing is the load-bearing part — a leg's `location` is a footprint-center the walkability predicate marks **blocked**, so the pathfinder routes the colonist to a cell *adjacent* to it, never onto it (true for both blueprints and crates — both are furniture). See [ColonistAI](colonists.md) for the state machine details.

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

## Flow Trace: Resource mark → Harvest lifecycle

The harvest subsystem provides dual-mode gathering: colonists work marked nodes as jobs, while the player can chop/gather nodes directly with LMB.

**Trigger:** A player marks a harvestable furniture piece via interaction (`ToggleHarvestAction`), or points and left-clicks in Normal mode (`HarvestAction`).

1. **Marking & Job Board Registration**:
   - The player looks at a harvestable node (e.g. `tree1`) within `interact_distance` and presses `E` to open the interaction menu.
   - Selecting "Toggle harvest" executes `ToggleHarvestAction`, calling `Harvestable.toggle_mark()`.
   - `Harvestable.set_marked()` flips `is_marked_for_harvest` and emits `EventBus.harvest_mark_toggled(furniture, anchor, is_marked)`.
   - `Colony._on_harvest_mark_toggled` receives the signal:
     - `is_marked == true`: registers a new `Job` built from `HARVEST_DEF` (`title="Harvest <label>"`, `labor_id="harvesting"`, `target_node=furniture`, `anchor_cell=anchor`) onto `JobBoard`.
     - `is_marked == false`: removes any `Job` matching that anchor from `JobBoard`.
2. **Colonist Selection & Pathing**:
   - An idle colonist with `labor_priorities["harvesting"] > 0` polls `JobBoard.get_best_job_for(colonist)`.
   - `JobBoard` verifies `Job.is_available()` (which checks `is_marked_for_harvest` and validity) and `JobDef.meets_requirements`.
   - `ColonistAI` claims the job via `job.try_assign(colonist)` and requests `get_next_leg(colonist, job)`.
   - `HarvestJobDef.get_next_leg` returns a single `WORK` leg targeted at the furniture node.
   - The colonist paths to a standable adjacent cell via `find_path_to_adjacent`.
3. **Execution & Completion**:
   - On arrival, `ColonistAI` calls `HarvestJobDef.begin(colonist, leg, job)`.
   - `begin` returns `maxf(0.0, (params.work_time / skill_multiplier) - harvestable.work_done())`.
   - If duration > 0, the colonist enters `WORK` state for that duration.
   - Upon timer completion, `ColonistAI` calls `HarvestJobDef.complete(colonist, leg, job)`:
     - Invokes `Harvestable.complete(colonist)`.
     - Dispenses `HarvestParams.yields` into `colonist.inventory` (carry inventory).
     - Posts a "Harvested <label>" entry to `GameLog`.
     - Removes the furniture node from `FurnitureLayer` via `FurnitureLayer.remove_at(anchor)` (which emits `EventBus.furniture_removed`).
   - Harvesting skill XP lands right after, in `ColonistAI._end_job` — the single XP entry point ([Skills](skills.md)); the def itself never records.
   - `get_next_leg` now returns `null` (the node is freed), ending the job cleanly.
4. **Dual-Mode: Direct Player Harvesting (LMB)**:
   - In Normal mode, pressing LMB (`InputComponent.primary_action_pressed`) on a targeted interactable running `HarvestAction.execute(player, target)` starts the `ActionProgress` HUD gauge.
   - `ActionProgress` is configured with `total_duration = params.work_time / player.skill_set.get_multiplier("harvesting")` and `start_elapsed = harvestable.work_done()`.
   - **On Complete**: `HarvestAction._apply` calls `Harvestable.complete(player)` (granting yields directly to the player's pocket) and awards player harvesting XP.
   - **On Cancel (Esc / interrupt)**: `ActionProgress.cancelled` emits `elapsed`, and `HarvestAction` calls `Harvestable.set_work_done(elapsed)` to persist partial progress for subsequent attempts.

**End state:** The node is removed from the world, materials land in the actor's inventory, XP is awarded, and Colony drops any corresponding job from the board.

## Subsystem Interfaces

The job system sits between [Furniture](build.md)/[Blueprint](build.md) and [ColonistAI](colonists.md) — it defines the contracts both sides depend on.

### Jobs ↔ Furniture

Jobs target furniture nodes through the **MaterialSink** duck-typed contract (`subsystems/furniture/material_sink.gd`): `needed_item_ids()`, `remaining_need(item_id)`, `deposit_from(actor)`, `has_complete_materials()` — checked with `has_method`, never a class cast, so any furniture implementing the four is haulable-to. `Blueprint` and `CraftingStation` implement it today. The `JobDef` subclass is responsible for calling the correct furniture methods; `ColonistAI` and the `Job`/`JobLeg` data classes are furniture-agnostic.

| Furniture / Blueprint member | Called by | Purpose |
|---|---|---|
| `Furniture.get_footprint_cells() → Array[Vector3i]` | `ColonistAI._path_for_leg()` | Path colonist adjacent to multi-cell furniture via `find_path_to_footprint_adjacent` |
| `Furniture.global_position` | `StorageRegistry` distance calculations | Find nearest crate (straight-line) |
| `Blueprint.has_complete_materials() → bool` | `HaulingJobDef` (`get_next_leg`, `complete`, `is_available`) | Check if all material_cost entries are satisfied |
| `Blueprint.needed_item_ids() → Array[String]` | `Colony._on_blueprint_placed`, `HaulingJobDef` (`get_next_leg`, `complete`, `is_available`, `_carries_needed_material`) | Determine which item IDs still need hauling |
| `Blueprint.remaining_need(item_id) → int` | `HaulingJobDef.complete()` (FETCH) | Units of one item still owed (cost minus given). Part of the MaterialSink contract. |
| `Blueprint.given_count(item_id) → int` | `Blueprint.needed_item_ids`/`remaining_need`, info text | How much of a specific item has been deposited |
| `Blueprint.deposit_from(actor) → int` | `HaulingJobDef.complete()` (DELIVER) | Transfer materials from actor's inventory into the blueprint; emits `blueprint_materials_ready` on threshold |
| `Blueprint.complete(builder) → bool` | `ConstructionJobDef.complete()` | Materialize the blueprint into real furniture via `layer.complete_blueprint` |
| `Blueprint.work_done` (read/write) | `ConstructionJobDef` (`on_end`: write, `complete`: reset) | Persist partial build progress so a later attempt resumes |
| `Blueprint.is_instance_valid()` | `ConstructionJobDef`, `HaulingJobDef` (via `is_material_sink`) | Guard against freed blueprints |
| `BuildableDef.build_time` | `ConstructionJobDef.begin()` | Duration of the WORK phase (divided by the builder's skill multiplier) |
| `BuildableDef.material_cost` | `Blueprint.has_complete_materials()` / `needed_item_ids` / `remaining_need` / `deposit_from` | Determine what items are needed and in what quantities |

### Jobs ↔ ColonistAI

`ColonistAI` drives the leg loop; the job system provides the `JobDef` virtual contract that the AI calls at each stage. The AI is intentionally "dumb" — it walks, times, and advances, but knows nothing about what legs do.

**The `JobDef` contract** (seven virtual methods on `JobDef`, called by `ColonistAI`):

| Method | Called by ColonistAI at | Returns | Purpose |
|---|---|---|---|
| `get_next_leg(actor, job) → JobLeg` | IDLE (leg 0) and `_advance()` | Next leg, or null if done | Produces the stream of walk→act steps |
| `begin(actor, leg, job) → float` | `_begin_work()` on arrival | Work duration in seconds (0 = instant) | Starts the leg; returned duration drives the WORK tick |
| `complete(actor, leg, job) → void` | `_tick_work()` (on elapse) and `_begin_work()` (instant) | — | Applies the leg's effect (build, fetch, deliver) |
| `on_end(success, actor, leg, job, elapsed) → void` | `_end_job()` (finish, abort, or claim-path release) | — | Cleanup: return carried items, persist partial progress. `leg` is null on a claim-path release. |
| `is_available(job) → bool` | `Job.is_available()` (via `try_assign` + selection) | Whether the job is claimable | Labor-specific gate (slot gate is on `Job`) |
| `should_close(job) → bool` | `Job.should_close()` (AI removal + board prune) | Whether the job is dead | Lifetime gate, independent of claimability — a drought-waiting haul job stays registered. Base default: `not is_available`. |
| `job_complete(job) → bool` | `_advance()` on a null leg | Whether a null leg is a clean finish | Drives success/XP vs. stall (log line, no XP) |

**Colonist members used by the job pipeline:**

| Colonist / ColonistAI member | Used by | Purpose |
|---|---|---|
| `Colonist.labor_priorities` | `JobBoard.get_best_job_for()` | Filter which jobs the colonist considers (weight 0 = skip) |
| `Colonist.global_position` | `JobBoard.get_best_job_for()`, `StorageRegistry` | Distance comparison for job selection and crate lookups |
| `Colonist.inventory` (add_item / remove_item / has_item / can_carry / remaining_capacity) | `Blueprint.deposit_from(actor)`, `StorageRegistry` transfers | Carry inventory for hauling; colonist stands in as `actor` |
| `Colonist.set_path(path)` | `ColonistAI` | Feed waypoints from the pathfinder |
| `Colonist.has_arrived() → bool` | `ColonistAI` (MOVE state) | Detect arrival at the leg target |
| `Colonist.current_job` | `ColonistAI` (set/unset) | Track the active job on the colonist entity |

## Planned Extensions (features not yet built)

Approved architecture (2026-08-15) for four new labors — Crafting at stations, Harvesting, Farming, Patrol — in [Job System Extensions](job-extensions.md). The **core foundations those features required are built** (second 2026-08-15 pass) and are documented on this page:

- **Requirement gating** — `JobDef.conditions: Array[Condition]` + `meets_requirements(actor, job)` (the [Condition](actions.md) family, not `ActionOption`), enforced in `get_best_job_for` + `try_assign` and re-evaluated fresh every poll — job conditions are hot, unlike the interaction menu's check-once-at-open semantics. Def-level conditions carry skill/item actor gates; tool gates stay procedural (FETCH_TOOL legs + an `is_available` stock check) so a toolless colonist can still claim the job that fetches the tool. Leaves: `MinSkillCondition`, `HasItemCondition` (by id or tag).
- **MaterialSink** — the duck-typed 4-method contract above; hauling no longer casts to `Blueprint`.
- **Tool retention** — `HaulingJobDef.on_end`'s surplus dump skips tool-tagged items (`ItemDef.tags`, `Inventory.has_item_tag`), so a carried tool survives haul runs.
- **Skill multipliers** — [Skills](skills.md) is live: `SkillSet` per colonist (seeded from `ColonistDef.starting_skills`), XP on job success via `ColonistAI`, and `begin()` durations divided by `skill_set.get_multiplier(labor_id)` (construction today; stamina still deferred).

Still open with the features themselves: crafting stations (the `crafting_materials_ready` signal is declared on EventBus, no emitter yet), harvesting/farming job defs, patrol + the labor-assignment UI.

## Class Reference

### Class: JobDef

**Extends:** Resource
**Script:** `data/jobs/job_def.gd`
**Description:** Reusable template for one kind of colonist work — one subclass per Labor, authored as a `.tres` via `script_class`. Owns data (`id`/`display_name`/`labor_id`/`max_assignees`) and **leg behaviour**: `get_next_leg` produces the next leg for a colonist (null when done), `begin` reports a leg's work duration (0 = instant), `complete` applies its effect, `on_end` cleans up on leave, `is_available` gates acceptability. Mirrors the behaviour-bearing Resource precedent (`GameAction`, `Condition`). The behaviour lives here, not on the Furniture, because it depends on Job parameters the Furniture doesn't know (e.g. a craft job's duration = `recipe.base_time × quantity`).
**Used by:** `Job` (`def` back-ref), `Colony` (`Job.from_def`), `ColonistAI` (drives the leg loop).

**Properties:** `id`, `display_name`, `labor_id` (Strings); `max_assignees: int = 1`; `conditions: Array[Condition]` (actor requirements — skill/item gates, evaluated hot every poll; empty = any colonist).

**Functions (virtual — overridden per Labor):**

| Function | Description |
|---|---|
| `get_next_leg(actor, job) → JobLeg` | The next leg for this colonist, or null when it has no further work. Base default null (finish immediately). |
| `begin(actor, leg, job) → float` | This leg's work duration (0 = instant → `complete` same tick). Divide by `skill_set.get_multiplier(labor_id)` for skill-scaled work. Base default 0.0. |
| `complete(actor, leg, job) → void` | Apply this leg's effect. Base default no-op. |
| `on_end(success, actor, leg, job, elapsed) → void` | Cleanup when a colonist leaves (finish, abort, or claim-path release — `leg` may be null there). Base default no-op. |
| `is_available(job) → bool` | Labor-specific claimability gate (e.g. hauling: sink valid + unsatisfied + a crate stocks a needed item). Base default true. |
| `should_close(job) → bool` | Whether the job is dead (leave the board) — independent of claimability so a temporarily-unclaimable job can stay registered (hauling's drought persistence). Base default `not is_available`. |
| `job_complete(job) → bool` | Whether a null `get_next_leg` is a clean finish (success/XP) versus a stall (e.g. a hauler that drained every crate). Base default true. |
| `meets_requirements(actor, job) → bool` | Every `conditions` entry `is_met(actor, job.target_node)` — actor-inherent facts only; world facts a def can check go in `get_next_leg`/`is_available` instead (a def-level tool condition would lock out the colonists its FETCH_TOOL leg exists for). Base default true. |

### Class: JobLeg

**Extends:** RefCounted
**Script:** `data/jobs/job_leg.gd`
**Description:** One leg of a job's walk→act sequence — pure routing data. A `JobDef` produces a stream of these via `get_next_leg`; `ColonistAI` walks to each `location` and runs the leg's action through `begin`/`complete` (dispatched on `kind`). Pure routing keeps legs reusable across labors (construction = one WORK leg; hauling = repeated FETCH/DELIVER legs) and lets the AI stay dumb about both.
**Properties:** `location: Vector3` (walk-target), `target_node: Node` (the per-leg node — crate/blueprint; weak, freed-detectable), `kind: int` (opaque, def-owned discriminator).

### Class: ConstructionJobDef

**Extends:** `JobDef`
**Script:** `data/jobs/construction_job_def.gd`
**Description:** Construction labor — a **one-leg job**: walk to the blueprint, WORK over `build_time` ÷ skill multiplier, `Blueprint.complete` materializes it. Single-colonist (`max_assignees=1`). Headless twin of the player's `BuildAction` — no gauge/mouse/`set_busy` (WORK is the busy guard). Skill-scaled via `SkillSet.get_multiplier("construction")` (L1 = 1×; stamina factor deferred).

**Functions:**

| Function | Description |
|---|---|
| `get_next_leg(actor, job) → JobLeg` | Returns the blueprint leg once (location = `job.location`, target = the bp), then null. |
| `begin(actor, leg, job) → float` | `BuildLibrary.get_def(bp.target_def_id).build_time / skill_set.get_multiplier(labor_id)`; the bare `build_time` for a non-Colonist actor; 0 if not a Blueprint / unknown def. |
| `complete(actor, leg, job) → void` | Reset `bp.work_done = 0` and `bp.complete(actor)`. |
| `on_end(success, actor, leg, job, elapsed) → void` | On abort (not success), persist `bp.work_done = elapsed` so a later attempt resumes. |
| `is_available(job) → bool` | The blueprint still exists. |

### Class: HaulingJobDef

**Extends:** `JobDef`
**Script:** `data/jobs/hauling_job_def.gd`
**Description:** Hauling labor — carry materials from storage crates to a [MaterialSink](#jobs-furniture) (blueprints and crafting stations today) until its need is satisfied. A multi-colonist job (`max_assignees=3`): haulers divvy a run through the sink's shared deposit counter (no per-colonist slices) — each independently loops FETCH → DELIVER until `has_complete_materials()`. The crate's live stock serializes concurrent haulers (two can't double-spend a plank). Phase is derived from carry state (not stored); both legs are instant (no WORK). The DELIVER leg's `deposit_from` emits the sink's materials-ready signal on the crossing (`blueprint_materials_ready` for blueprints, `crafting_materials_ready` for stations) — Colony's single trigger to spawn the follow-on job. `on_end`'s surplus dump skips tool-tagged items, so a carried tool survives haul runs.
**Constants:** `FETCH = 1`, `DELIVER = 2` (the `JobLeg.kind` discriminator).

**Functions:**

| Function | Description |
|---|---|
| `get_next_leg(actor, job) → JobLeg` | sink gone/satisfied → null; carrying a needed material → DELIVER; else FETCH from the nearest source crate (`registry.find_source`), or null if no source (drought — the job stays registered). |
| `complete(actor, leg, job) → void` | FETCH: `crate.transfer_to(colonist.inventory, id, sink.remaining_need(id))` per still-needed item (skips if the sink became satisfied en route). DELIVER: `sink.deposit_from(actor)`. |
| `on_end(success, actor, leg, job, elapsed) → void` | Return any surplus on the colonist to the nearest crate (`registry.nearest_crate`) — except tool-tagged items (`ItemDef.tags`), which stay with the colonist. |
| `is_available(job) → bool` | Claimability: sink valid, unsatisfied, and some crate holds a needed material. |
| `should_close(job) → bool` | Lifetime: close only when the sink is gone or satisfied — a source drought keeps the job registered (unclaimable, invisible to selection) until restock. |
| `job_complete(job) → bool` | True only when the sink crossed `has_complete_materials` — a drought null leg is a stall, not a finish. |

### Class: CraftingJobDef

**Extends:** JobDef (`data/jobs/crafting.tres`: labor `crafting`, `max_assignees=1`)
**Script:** `data/jobs/crafting_job_def.gd`
**Description:** Crafting labor — a **one-leg job** at a [CraftingStation](crafting.md): walk to the station, WORK over `recipe.base_time` ÷ skill multiplier, then produce. `job.target_node` is the station node (it IS the MaterialSink; freeing the furniture frees it, so the freed-target guard covers deconstruction). Spawned by Colony only when a **colony** order's deposits cross `has_complete_materials` (`crafting_materials_ready`) — player-reserved orders never spawn a craft job (the dual-mode reservation). A maintain order ("until stock N") self-requeues on completion, riding the same haul chain.

**Functions:**

| Function | Description |
|---|---|
| `get_next_leg(actor, job) → JobLeg` | The station leg while the order is active, materials-complete, AND unclaimed; null otherwise (complete cleared/requeued it → the clean end-signal; a claimed order means the player's gauge owns it). |
| `begin(actor, leg, job) → float` | `recipe.base_time / skill_set.get_multiplier(labor_id)`; bare `base_time` for a non-Colonist actor; 0 if the order vanished **or the claim is held** (the colonist backs off — complete no-ops the same tick). Claims the station under the colonist's id for a timed WORK phase. |
| `complete(actor, leg, job) → void` | Re-checks the claim (player-gauge race → no-op), then `produce()` crate-first (pocket overflow — maintain stock counters read crates) and `complete_order()` (maintain requeue or clear). XP is automatic in `_end_job`. |
| `produce(actor, station, recipe, pocket_first) → bool` | The shared craft math — output routing with overflow into the other container. CraftAction (the player's personal craft) reuses it pocket-first. |
| `on_end(success, actor, leg, job, elapsed) → void` | Release this colonist's claim (owner-matched — an aborting colonist can't unlock the player's gauge). |
| `meets_requirements(actor, job) → bool` | Base def conditions AND the active recipe's `RecipeDef.conditions` (hot, per poll — a leveled-up colonist becomes eligible on the next poll). |
| `is_available(job) → bool` | Station holds a materials-complete, unclaimed order (deposits never regress within an order). |
| `should_close(job) → bool` | Station gone or order resolved — unlike hauling there is no drought state to wait out. |

### Class: Job

**Extends:** RefCounted
**Script:** `colonists/job.gd`
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
| `from_def(d: JobDef) → Job` | Static ctor: uuid, `def` back-ref, denormalized `labor_id`/`title`/`max_assignees`. |
| `try_assign(colonist) → bool` | Join (checks `is_available` + not-already-assigned + `meets_requirements`). Pull, not push. |
| `unassign(colonist) → void` | Leave (leg exhaustion or abort). |
| `is_assigned(id) → bool` / `clear_assigned() → void` | Membership check / release all (used by the failure path). |
| `is_available() → bool` | `_assigned < max_assignees && def.is_available(self)` — the slot gate AND the labor-specific claimability gate. |
| `should_close() → bool` | `_assigned.is_empty() && def.should_close(self)` — the job is dead and should leave the board (def-less jobs fall back to `!is_available()`). |

### Class: JobBoard

**Extends:** Node
**Script:** `colonists/job_board.gd`
**Description:** The colony's job registry + selection. Owned by the Colony autoload as a child Node. Producers add Jobs; consumers (`ColonistAI`) query `get_best_job_for` then assign via `Job.try_assign` directly. Holds the registry + selection + the dead-job prune — no assignment bookkeeping (that's on the `Job`) and no pathfinding/work.
**Used by:** Colony (producer), ColonistAI (consumer), future Job Log UI.
**Lifecycle:** Created and added as a child by `Colony._ready`.

**Signals:** `job_failed(job_id, reason)` (direct listeners). (`job_logged` is relayed via EventBus.)

**Functions:**

| Function | Description |
|---|---|
| `add_job(job) → void` | Register (assigns an id if the creator didn't). |
| `remove_job(job_id) → void` | Drop by id. |
| `get_job` / `has_jobs` / `get_jobs` | Inspection / debug / future UI. |
| `get_best_job_for(colonist) → Job` | First `_prune_dead_jobs()`, then best `is_available()` job whose Labor is enabled (highest priority, nearest) and whose def `meets_requirements(colonist, job)` holds. Does NOT assign. |
| `_prune_dead_jobs() → void` | Drop unassigned `should_close()` jobs (satisfied, cancelled, invalid). Drought-waiting haul jobs survive — their def keeps them registered until restock. |
| `fail(job_id, reason) → void` | Record a failure: increment `failure_count`, clear assignees, emit `job_failed`, relay `job_logged`; auto-remove at `_MAX_FAILURES` (3). Driven by `ColonistAI` on aborts (freed target, unreachable leg); stalls (haul droughts) don't count. |

### Class: StorageRegistry

**Extends:** Node
**Script:** `inventory/storage_registry.gd`
**Description:** Live index of the colony's storage crates, so hauling jobs can find a source for a blueprint's still-needed materials. Owned by Colony as a child Node; pointed at the current map's `FurnitureContainer` by `MapWiring` on each map load. No registration — `find_source`/`has_source_for`/`nearest_crate` scan the container's live children each call, so freed crates are simply absent (no stale refs, no unregister hook).

**Functions:**

| Function | Description |
|---|---|
| `on_map_wired(container) → void` | Bind to the current map's furniture container (called by `MapWiring`). |
| `find_source(item_ids, near) → Furniture` | Nearest crate whose `StorageInventory` holds any of `item_ids` (straight-line; reachability verified later by the pathfinder). Null if none. |
| `has_source_for(item_ids) → bool` | Any crate holds any of `item_ids`. Used by the producer decision + hauling's `is_available`. |
| `nearest_crate(near) → Furniture` | Nearest crate regardless of contents (for surplus return). |
| `inventory_of(crate) → StorageInventory` | The crate's `StorageInventory` (or null). Shared resolution path for haul legs. |

### Class: HarvestJobDef

**Extends:** JobDef (`data/jobs/harvest.tres`: labor `harvesting`, `max_assignees=1`)
**Script:** `data/jobs/harvest_job_def.gd`
**Description:** Harvesting labor — a **one-leg job** targeting a marked resource node (e.g. tree): walk adjacent to the node, WORK over `HarvestParams.work_time` ÷ skill multiplier, then `Harvestable.complete` to grant yields and remove the node. Available exactly while `target_node` is valid AND `is_marked_for_harvest` is true.

**Functions:**

| Function | Description |
|---|---|
| `get_next_leg(actor, job) → JobLeg` | Returns the node leg while `is_marked_for_harvest` is true; null otherwise (unmarking or completion cleanly ends the job). |
| `begin(actor, leg, job) → float` | `maxf(0.0, (params.work_time / skill_multiplier) - harvestable.work_done())`. Returns remaining work in seconds. |
| `complete(actor, leg, job) → void` | Calls `harvestable.complete(actor)` and records harvesting skill XP. |
| `on_end(success, actor, leg, job, elapsed) → void` | On abort, persists `harvestable.set_work_done(work_done + elapsed)`. |
| `is_available(job) → bool` | Target valid AND `harvestable.is_marked_for_harvest()`. |
| `should_close(job) → bool` | Target gone or `!is_marked_for_harvest()`. |

### Class: Harvestable

**Extends:** Node
**Script:** `subsystems/harvesting/harvestable.gd`
**Description:** Capability component attached under a `Furniture` node by `FurnitureLayer` when its def declares `harvest_params`. Tracks `is_marked_for_harvest` and `work_done` in the parent's `state` dictionary (`"harvest"` key). Exposes `complete(actor)` to resolve yields and node deletion.
**Used by:** `HarvestJobDef`, `HarvestAction`, `ToggleHarvestAction`, `FurnitureLayer`, `Colony`.

**Functions:**

| Function | Description |
|---|---|
| `params() → HarvestParams` | Back-ref to definition's `def.harvest_params`. |
| `anchor_cell() → Vector3i` | Footprint corner anchor cell. |
| `is_marked_for_harvest() → bool` | Whether marked for colonist work. |
| `set_marked(marked: bool) → void` | Update mark state, log change, and emit `EventBus.harvest_mark_toggled`. |
| `toggle_mark() → void` | Flips mark state. |
| `work_done() → float` / `set_work_done(amount: float) → void` | Accumulated work accessors. |
| `complete(actor: Node) → bool` | Dispenses `params.yields` into `actor` inventory, logs "Harvested <label>", and removes the node via `FurnitureLayer.remove_at` (or `queue_free`). |

### Class: HarvestParams

**Extends:** Resource
**Script:** `data/capability_params/harvest_params.gd`
**Description:** Capability sub-resource on `FurnitureDef` configuring harvesting properties.
**Properties:** `yields: Array[ItemAmount]`, `work_time: float` (default 4.0), `respawn_time: float` (0 = permanent), `required_tool_tag: String`.

### Class: HarvestAction

**Extends:** GameAction
**Script:** `data/actions/harvest_action.gd`
**Description:** Dual-mode player harvesting action executed on LMB click in Normal mode. Runs the `ActionProgress` HUD gauge scaled by player skill, invoking `Harvestable.complete(player)` on finish or persisting `elapsed` on cancel.

### Class: ToggleHarvestAction

**Extends:** GameAction
**Script:** `data/actions/toggle_harvest_action.gd`
**Description:** Interaction menu action bound to `toggle_harvest_action_option.tres`. Invokes `Harvestable.toggle_mark()` on the targeted furniture node.

