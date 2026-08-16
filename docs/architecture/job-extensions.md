# Job System Extensions

Architecture plan for four new colonist job types — **Crafting at furniture, Harvesting, Farming, Patrol** — over the [Jobs](jobs.md) core. Companion to [Jobs](jobs.md) (the built system), [Crafting](crafting.md) (the crafting design intent), and [Skills](skills.md) (the skill spec). GDD §6.

> **Status: the Core Changes are built (2026-08-15, with tests); the Crafting Feature is built (2026-08-15, `test/suite_crafting_test.gd`). Harvesting, Farming, and Patrol are still planned.** Built behavior is documented on [Jobs](jobs.md), [Skills](skills.md), and [Crafting](crafting.md); this page keeps the plan + the design rules the features must follow. Sequencing at the bottom.

## Verdict

The `JobDef`/`JobLeg`/`Job`/`JobBoard`/`ColonistAI` core supports all four features unchanged. The proof cases already ship: unbounded leg streams (hauling loops FETCH/DELIVER with zero stored state), timed WORK legs (construction), and job chaining through a stateful target + EventBus signal (`blueprint_materials_ready` → construction). Crafting is a second user of that chain; harvesting and farming are new defs over the same leg machinery; patrol v1 needs **zero core changes**.

What was missing before the Core Changes landed: per-colonist gating (nothing in the pipeline evaluated the *actor* — `JobDef.is_available(job)` takes no actor, `get_best_job_for` filtered on labor priority only), `SkillSet` (a two-line stub), item tags, a generalized haul target, furniture state persistence — all **built now**. Still missing, and only needed for *scheduled* patrols later: persistent jobs + an external cancel.

## Design Rules

The load-bearing decisions, distilled. Each exists because the naive version breaks something.

1. **Skill gates and tool gates live in different layers.** Def-level `conditions` carry only stable per-colonist capability gates (skills). Tool requirements are procedural **FETCH_TOOL legs** + an `is_available` stock check — `HaulingJobDef`'s exact pattern. A def-level `HasItem` condition would be self-contradictory: a toolless colonist fails selection and can never claim the job whose first leg fetches the tool.
2. **Job conditions are hot.** Unlike `ActionOption`'s check-once-at-menu-open semantics (see [Actions & Interaction](actions.md)), job conditions are re-evaluated fresh on every poll — `get_best_job_for`, `try_assign`, and per-leg inside `get_next_leg`. Never cache a result.
3. **Tools stay with the colonist.** Every dump-to-crate path must skip tool-tagged items. `HaulingJobDef.on_end` currently returns *all* carried items to the nearest crate — it would confiscate a fetched axe on the colonist's next haul run.
4. **Bulk vs pocketable inputs.** Bulk inputs (crafting: 10× wood) reuse the multi-hauler FETCH/DELIVER loop via MaterialSink. Pocketable inputs (seeds, fertilizer, tools) use inline FETCH legs in the job's own leg stream. One seed doesn't justify the multi-hauler machinery.
5. **`is_available` prevents hot-loops.** If `get_next_leg` can return null for a colonist who still passes selection (e.g. no crate stocks the required tool), idle colonists claim → release → retry every 0.5s and never consider lower-ranked jobs. The actor-independent half of such gates belongs in `is_available`, where the prune and the selection filter both see it.

## Core Changes — ✅ built

All six shipped (2026-08-15, `test/suite_skills_test.gd` / `suite_condition_test.gd` / `suite_jobs_test.gd`); documented in built form on [Jobs](jobs.md) / [Skills](skills.md). Kept here as the plan of record for what the Features may rely on.

### 1. Requirement gating — `JobDef` / `Job` / `JobBoard`

Files: `data/jobs/job_def.gd`, `subsystems/colonists/job.gd`, `subsystems/colonists/job_board.gd`.

- `JobDef` gains `@export var conditions: Array[Condition] = []` and `func meets_requirements(actor: Node, job: Job) -> bool` — evaluates each `condition.is_met(actor, job.target_node)` fresh (rule 2).
- `JobBoard.get_best_job_for` skips jobs failing `def.meets_requirements(colonist, job)` *before* ranking, so ineligible colonists never claim-and-release.
- `Job.try_assign` rejects on failure — enforcement even if selection is bypassed.
- Conditions must tolerate a null target (patrol jobs carry no `target_node`; the existing leaves already do).
- Per-order gates (a hard recipe) live on the sub-resource (`RecipeDef.conditions`, evaluated by the def) — def-level conditions are shared by every job of that def.

Reuses the `Condition` resource family (`AllOf`/`AnyOf`/`Not` + leaves) from [Actions & Interaction](actions.md) — **not** `ActionOption`, whose label + `GameAction` coupling is interaction-menu-only.

### 2. `SkillSet` — implement the [Skills](skills.md) spec

Files: `subsystems/colonists/skill_set.gd`, `data/skills/skills.tres`.

[Skills](skills.md) specifies the API, signals, and flow traces — this is implementation-to-spec, not design: `record_use(skill_id)`, `get_level(skill_id)`, `get_multiplier(labor_id) -> float`, `meets_requirement(skill_id, min_level) -> bool`, signals `skill_progressed`/`skill_leveled_up`. Seeded from `ColonistDef.starting_skills` (ships `mining` + `farming` at L1; `mining` isn't one of the 6 skills and is ignored by the seed).

- **Work speed**: defs divide `begin()`'s duration by `actor.skill_set.get_multiplier(job.labor_id)` — the documented `base_rate` seam (Jobs' deferred list). `StaminaComponent` stays stubbed.
- **XP**: `ColonistAI` calls `record_use` on `_end_job(true)`, only for labors mapped to a skill in `skills.tres` (unmapped labors grant nothing; hauling maps to none initially).

### 3. Leaf conditions — `data/conditions/`

| Class | Properties | Reads |
|---|---|---|
| `MinSkillCondition` | `skill_id: String`, `min_level: int = 1` | `actor.skill_set.meets_requirement` — the L1 default is the job gate Jobs documented as deferred |
| `HasItemCondition` | `item_id: String` XOR `item_tag: String`, `count: int = 1` | `actor.inventory.has_item` / `has_item_tag` |

The `AllOf`/`AnyOf`/`NotCondition` composites are reused unchanged.

### 4. `ItemDef` tags + tool retention

Files: `data/items/item_def.gd`, `subsystems/inventory/inventory.gd`, `data/jobs/hauling_job_def.gd`.

- `ItemDef` gains `@export var tags: Array[String] = []` (an axe: `["tool", "axe"]`). `Inventory` gains `has_item_tag(tag, count)`. Tools are authored low-weight so they don't clog carry capacity.
- `HaulingJobDef.on_end` (and every future dump-to-crate path) skips tool-tagged items (rule 3).

### 5. `MaterialSink` — generalize hauling off `Blueprint`

Files: `data/jobs/hauling_job_def.gd` + `subsystems/furniture/material_sink.gd` + the contract table below. **No new base class**: GDScript has no interfaces and `Blueprint` already extends `Furniture`, so this is a duck-typed contract with a static `is_material_sink(node)` helper (`has_method` × 4).

| Method (contract) | Purpose |
|---|---|
| `needed_item_ids() -> Array[String]` | Item ids still short |
| `remaining_need(item_id) -> int` | Units still wanted of one item — generalizes hauling's `Blueprint.given_count` + `BuildLibrary.material_cost` reads |
| `deposit_from(actor) -> void` | Take from the actor's inventory; emit the satisfaction signal on the crossing |
| `has_complete_materials() -> bool` | Satisfied check |

`Blueprint` already matches (behavior unchanged); `HaulingJobDef` swaps its `Blueprint` casts for these calls. New EventBus signal `crafting_materials_ready(station, anchor)` mirrors `blueprint_materials_ready` — specific, not generic; a shared signal gets added only when a third sink appears.

### 6. Furniture state persistence

Files: `subsystems/furniture/furniture.gd`, `subsystems/build/furniture_layer.gd`.

`Furniture` serialize/restore gains a `state: Dictionary` round-trip (today only `def_id` + storage survive). Capability components (`Growable`, `CraftingStation`) read/write it — the prerequisite for farm plots that grow across save/load.

## Features

### Crafting — haul-then-work at a station — ✅ built

Shipped 2026-08-15 (`data/crafting/recipe_def.gd`, `data/capability_params/crafting_params.gd`, `subsystems/crafting/crafting_station.gd`, `data/jobs/crafting_job_def.gd` + `crafting.tres`, `ui/crafting/craft_panel.tscn` + `OpenCraftingAction`, Colony routing; `test/suite_crafting_test.gd`). Built form documented on [Crafting](crafting.md). The design as built:

**Trigger:** Player queues a recipe at the station (an `ActionOption` on the furniture; one active order per station in v1).

1. `CraftingStation` (child component, the `StorageInventory` pattern) implements **MaterialSink** from the active order's inputs.
2. Colony producer on order placement (`crafting_order_queued`): a **haul job bound to the station** (the existing def, sink-generic) — spawned regardless of crate stock, so a drought just drought-waits on the board until restock.
3. The haul DELIVER that crosses `has_complete_materials` → the station emits `crafting_materials_ready` → Colony spawns the craft job (dedupe by anchor + labor, like `_spawn_construction_job`).
4. `CraftingJobDef`: WORK leg at the station; `begin` = `recipe.base_time / skill multiplier`; `complete` = consume inputs → outputs to the colonist's carry inventory (overflow → nearest crate), `record_use`, order cleared.

| Class (as built) | Shape |
|---|---|
| `RecipeDef` (Resource) | `id`, `display_name`, `inputs`/`outputs: Array[ItemAmount]`, `base_time: float`, `conditions: Array[Condition]` (recipe-level skill gates, ANDed by `CraftingJobDef.meets_requirements`) |
| `CraftingParams` (capability on `FurnitureDef`) | `recipes: Array[RecipeDef]` — non-null → FurnitureLayer attaches the station |
| `CraftingStation` (Node component) | Implements MaterialSink from the active order (order + `given` ledger in the Furniture `state` bag under `"craft_order"`); emits `crafting_order_queued` / `crafting_materials_ready` |

**Design note:** supersedes [Crafting](crafting.md)'s reserve-at-queue step — inputs are physically hauled to the station (the blueprint pattern, matching the "furniture creates the job once hauling finishes" requirement) instead of reserved in crates. Crafting's material-flow-through-storage, skill, Stamina, and output-to-storage points otherwise stand.

> **Status: Harvesting Feature is built (2026-08-16, `test/suite_harvesting_test.gd`).**

### Harvesting — furniture nodes, marking, and manual chop

Files: `HarvestParams` capability sub-resource, `subsystems/harvesting/harvestable.gd` component, `data/jobs/harvest_job_def.gd` + `harvest.tres`, `data/labors/harvesting.tres` (new labor), `data/actions/harvest_action.gd` (player LMB action), `data/actions/toggle_harvest_action.gd` (E interaction option), `subsystems/autoloads/colony.gd` routing on `harvest_mark_toggled`.

Trees/resources = furniture authored into maps with `HarvestParams`: `yields: Array[ItemAmount]`, `work_time: float`, `respawn_time: float` (0 = removed permanently). FurnitureLayer attaches the `Harvestable` component and injects the `ToggleHarvestAction` into the `InteractionComponent`.

Dual-mode harvesting:
- **Player manual harvest (LMB)**: In Normal mode, pressing LMB looking at a harvestable target runs `HarvestAction` with the `ActionProgress` HUD gauge (duration scaled by player's harvesting skill). Completes work directly or persists partial progress on cancel.
- **Colonist job via marking (E interaction)**: Interacting with E allows toggling the "Mark for Harvest" state on `Harvestable`. Toggling emits `EventBus.harvest_mark_toggled`, prompting Colony to register/unregister a `HarvestJob` on `JobBoard`.

`HarvestJobDef`:
- `get_next_leg`: returns a WORK leg targeting the marked node (null if un-marked or node gone).
- `is_available`: node valid AND `is_marked_for_harvest` is true.
- `begin`: duration = `work_time / skill_multiplier - work_done`.
- `complete`: applies work → yields to colonist inventory → node removed via `FurnitureLayer.remove_at`; records harvesting skill XP.
- `on_end`: persists elapsed work on abort.

**Voxel node harvesting** (follow-up, after Demolition): `BlockDef` gains `drops: Array[ItemAmount]`; a `MiningJobDef` targets a cell — `job.anchor_cell` is the cell's identity (dedupe/cancel by anchor, exactly like blueprints) and `leg.location` the walk target; `complete` drives `VoxelGrid.apply_damage` per swing until `block_destroyed` → drops. The pathfinder is already cell-native (`find_stand_near_cell`; `ColonistAI._path_for_leg` falls back to `find_path_to_adjacent` for non-furniture legs), so no `JobLeg` change is required — an optional `target_cell: Vector3i` is identity sugar. [Tech Debt](tech-debt.md)'s "Demolition (as a Job)" needs the same cell-targeted leg shape and is the smaller proving ground — build it first. Resource veins additionally need worldgen (flat generator today) — a separate effort.

### Farming — plant → water → harvest loop

Files: `FarmPlotParams` capability sub-resource, `subsystems/farming/growable.gd` (component), `data/jobs/` plant/water/harvest defs + `data/labors/farming.tres` (new labor), `subsystems/autoloads/colony.gd` routing. Depends on core changes 1, 2, 6.

`FarmPlotParams`: `seed_item`, `growth_time`, `water_interval`, `fertilizer_effect`, `yields`.

`Growable` (child component) is the one thing the architecture lacks — furniture that changes state *without* a colonist: stage `{EMPTY, PLANTED, GROWING, READY}`, growth + water clocks driven by `TimeSystem` (exists with zero gameplay consumers today), state persisted via core change 6. Emits on EventBus:

| Signal (planned) | When |
|---|---|
| `plot_needs_planting(anchor)` | Stage ENTERED-empty (placed, or after harvest) |
| `plot_needs_water(anchor)` | Water clock elapses while GROWING (drought slows growth) |
| `plot_ready_to_harvest(anchor)` | Growth completes |

Colony routes each to a job (dedupe by anchor + labor):

| JobDef (planned) | Legs |
|---|---|
| `PlantJobDef` | FETCH seed (inline — rule 4) → WORK plant (stage → GROWING) |
| `WaterJobDef` | FETCH_TOOL watering can → WORK water (resets the water clock) |
| `FarmHarvestJobDef` | FETCH_TOOL sickle → WORK harvest (yields → inventory; stage → EMPTY → re-emits needs_planting) |

All `MinSkill`-gated (`farming` ships as a starting skill), durations skill-multiplied. **Fertilizer v1** = a player `ActionOption` on the plot (boost yield or cut growth time); a colonist `FertilizeJobDef` is deferred until the loop proves out.

### Patrol v1 — labor checkbox + random waypoints

Zero core changes. Files: `data/labors/patrol.tres` (new labor), patrol-flag furniture def + `PatrolFlagParams` (reserve `route_id`/`order` for ordered routes later), `data/jobs/patrol_job_def.gd` + `patrol.tres`, `subsystems/autoloads/colony.gd` producer, `ui/labor/labor_assign_ui.tscn` (new).

`PatrolJobDef`:

- **One shared job**, `max_assignees` = roster cap. The producer ensures it exists while ≥1 flag is placed (`furniture_placed`/`furniture_removed`) and removes it when the last flag goes.
- `is_available` = ≥1 flag exists — always true while flags stand, so the job survives the dead-job prune and `should_close()` naturally (no `persistent` flag needed until schedules).
- `get_next_leg` = walk-only leg (`begin` 0) to a random flag other than the one at the actor's position — stateless, no per-colonist memory. Returns null when the actor's `labor_priorities["patrol"] <= 0` (unchecking exits at the next leg boundary; the selection priority filter prevents re-claim) or no flags exist.
- A removed flag mid-walk hits `ColonistAI`'s existing freed-target abort.

**Known semantics:** no preemption — a patrolling colonist never re-polls the board while patrol stays its top enabled labor; the checkboxes are the control surface. `labor_priorities` already round-trips `Colonist.serialize` (colonist save/restore itself is still deferred — see [Colonists](colonists.md)).

**Labor assignment UI** (needed by every new labor — they default to priority 0, since `ColonistDef.default_labor_priorities` ships only `construction`/`crafting`/`hauling`): a minimal scene — rows = colonist display names, columns = labors (construction, crafting, hauling, harvesting, farming, patrol), checkboxes bound to `Colonist.set_labor_priority()` (exists, unused). Opened by a hotkey or HUD button.

### Patrol v2 — schedules + ordered routes (deferred)

`ScheduleDef` resource: time windows vs `TimeSystem.get_time_of_day_fraction()`; ordered routes via the reserved `route_id`/`order`. Two core additions become required then:

- **`JobDef.persistent`** — bypass `_prune_dead_jobs` + `should_close` so an off-schedule job isn't deleted at the first selection sweep. The schedule check goes *in* `is_available` (so unavailable patrol jobs stop ranking — otherwise a claim/null/release hot-loop starves lower-priority work); persistence keeps the job alive while invisible. The mechanism now exists in targeted form: `JobDef.should_close` decouples lifetime from claimability, and hauling already uses it for drought persistence (an unsatisfied sink keeps the job registered while no crate stocks a needed material). Patrol just needs the flag so an author can opt in without overriding the method.
- **`ColonistAI.cancel_current_job(reason)`** — the external interrupt ("shift's over", later "raid started"). Today a job only ends via a null leg, an unreachable leg, or a freed target.

## Sequencing

1. ~~Core changes 1–4 (gating, `SkillSet`, conditions, tags + tool retention); 5 lands with crafting, 6 with farming.~~ **Done — all six core changes shipped ahead of the features.**
2. ~~**Crafting** — proves the MaterialSink chain + skill gates.~~ **Done — shipped 2026-08-15 (`suite_crafting_test.gd`), workbench + planks/axe seed recipes.**
3. **Labor UI + patrol v1** — cheapest feature; exercises the UI every later labor needs.
4. **Harvesting** — proves FETCH_TOOL.
5. **Farming** — the growth loop.

After the roadmap: Demolition → voxel mining; patrol schedules v2; ~~`JobBoard.fail` wiring~~ (done — wired on ColonistAI abort paths); preemption.
