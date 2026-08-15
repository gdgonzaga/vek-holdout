# Subsystem: Crafting

Recipe-driven conversion of materials into items at crafting stations (GDD §7.9). The station is a **furniture component** (`CraftingStation`, the `StorageInventory` pattern — not a `Furniture` subclass), its order is a **MaterialSink** hauling can feed like a blueprint's, and crafting itself is a **Job** on the board (no special-casing). Consumes from colony storage via hauling; produces into the crafter's carry inventory (overflow to the nearest crate).

> **Status: built (2026-08-15, `test/suite_crafting_test.gd`).** Workbench ships with seed recipes (`data/recipes/planks.tres`: 1 wood block → 4 planks; `data/recipes/axe.tres`: 2 planks + 1 stone block → 1 axe). Forge + smelting deferred (no forge FurnitureDef, no smelting skill in the catalog) — the shared component/def make it data-only work later.

**Design notes:**
- **One unified `Recipe` shape** for all craftable output (`RecipeDef`: furniture, armor, weapons, ammo, smelting). Same fields regardless of output type.
- **`CraftingStation` is a component attached to furniture nodes** (Workbench today, Forge later) — owns "which recipes are available here?" and the active order. The recipe data lives in `data/recipes/` referenced from the def's `CraftingParams`.
- **No tech tree in MVP** — all recipes available from the start; the constraint is materials + station + skill gate (L1 Crafting via `RecipeDef.conditions`). Post-MVP: unlocking.
- **Material flow goes through hauling** (MaterialSink → crates), not reservation at queue time and not the colonist's personal inventory at fetch time. This supersedes the original reserve-at-queue design — inputs are physically hauled to the station, the blueprint pattern.
- **Queueing never rejects for missing materials** — the haul job drought-waits on the board (HaulingJobDef lifetime semantics) and restock resumes it with no new producer event.

## Files

| File | Type | Responsibility |
|---|---|---|
| `data/crafting/recipe_def.gd` | Script (Resource) | Data shape for one recipe: inputs/outputs (`Array[ItemAmount]`), `base_time`, recipe-level `conditions`. Pure data. See [Data Schemas](data-schemas.md). |
| `data/capability_params/crafting_params.gd` | Script (Resource) | Capability sub-resource on `FurnitureDef`: `recipes: Array[RecipeDef]`. Non-null → FurnitureLayer attaches the station. |
| `subsystems/crafting/crafting_station.gd` | Script (component on furniture) | The order + deposit ledger; implements MaterialSink from the active order; emits `crafting_order_queued` / `crafting_materials_ready`. Does NOT own the craft math. |
| `data/jobs/crafting_job_def.gd` + `crafting.tres` | Script + data | Craft Job def: WORK leg at the station, skill-scaled duration, outputs + order clear on complete. |
| `data/recipes/*.tres` | Data | Recipe resources referenced from the station def's CraftingParams. |
| `ui/crafting/craft_panel.tscn` + `data/actions/open_crafting_action.gd` | UI + action | The queue surface: E on the workbench → craft panel → queue. |

## Signals

Crafting is local to the base scene + Colony (Job Board) via the EventBus relay:

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `crafting_order_queued(station, anchor)` | `CraftingStation.queue_recipe` | Colony | Yes | Player Queues a Craft |
| `crafting_materials_ready(station, anchor)` | `CraftingStation.deposit_from` (single-fire per order) | Colony | Yes | Player Queues a Craft |
| `job_logged` / log feed entries | JobBoard / `GameLog.craft(...)` | log feed UI | Yes/No | queue, materials-ready, and crafted lines |

## Flow Trace: Player queues a craft (Workbench)

**Trigger:** Player E-presses the workbench → `OpenCraftingAction` → `ui/crafting/craft_panel.tscn` → clicks a recipe row.

1. `CraftingStation.queue_recipe(recipe_id)`: no-op if an order is active (one per station in v1) or the recipe isn't offered; writes the order `{recipe_id, given:{}}` into the furniture's `state` bag (save/load round-trips free); emits `crafting_order_queued`.
2. `Colony._on_crafting_order_queued`: spawns a **haul job bound to the station** (`HAULING_DEF`, `target_node` = the station — hauling is sink-generic), deduped by anchor + labor. Spawned regardless of crate stock: no stock → the job drought-waits on the board (unclaimable but not dead); restock flips it claimable within one 0.5s poll.
3. Haulers loop FETCH (crate → carry) → DELIVER (`station.deposit_from`) until the order's inputs are covered.
4. The DELIVER that crosses `has_complete_materials` emits `crafting_materials_ready` (single-fire per order — `given` never decreases).
5. `Colony._on_crafting_materials_ready` → `_spawn_craft_job` (dedupe by anchor + labor, the `_spawn_construction_job` pattern).

**End state:** Craft Job on the board; the station reads as a satisfied sink; awaiting a crafter.

## Flow Trace: Craft Job executes (colonist claims + completes)

**Trigger:** A colonist claims the craft Job via the standard Job Board flow (§6.10) — labor `crafting` (default priority 1), gated by `RecipeDef.conditions` through `CraftingJobDef.meets_requirements` (hot, every poll).

1. Colonist AI claims the Job; paths to the station (A* on the voxel grid, `job.location` = footprint center).
2. `begin` = `recipe.base_time ÷ skill_set.get_multiplier("crafting")` (L1 = 1.0 … L5 = 2.0; the ConstructionJobDef pattern). Stamina factor still deferred (StaminaComponent stub).
3. WORK ticks in ColonistAI; on elapse `complete` runs.
4. `complete`: outputs → the crafter's carry inventory, overflow `add`ed to the nearest crate (StorageRegistry); `clear_order()` (the deposit ledger IS the consumption — inputs were virtual); `GameLog.craft("Crafted …")`.
5. XP is automatic: `_end_job(true)` → `record_use_for_labor("crafting")` → Crafting skill progress.
6. Post-complete `get_next_leg` → null (order gone) → clean finish; `should_close` → the Job leaves the board.

**End state:** Inputs consumed; output carried (or stored); Crafting skill progressed; Job closed; station ready for the next order.

## Flow Trace: Interruptions

- **Order cleared / station freed mid-anything:** haul jobs close via the sink's normal lifecycle (a no-order station reports no needs → "satisfied" → close); the craft job's `should_close` is station/order-gone; a freed station (deconstructed workbench) is caught by ColonistAI's freed-target guard.
- **Craft aborted mid-WORK:** the order and its deposits survive on the station; the job stays claimable and a later attempt re-runs the full `base_time` (no partial-work persistence in v1 — the `work_done` seam blueprint construction has is not mirrored yet).
- **Save/load:** the order round-trips through `Furniture.state`; jobs are NOT recreated on load (the pre-existing colony gap, applies to craft jobs too).

## Class Reference

### Class: CraftingStation

**Extends:** Node (component on furniture nodes — Workbench today, Forge later)
**Script:** `subsystems/crafting/crafting_station.gd`
**Description:** Attached by `FurnitureLayer._create_furniture_node` when `def.crafting_params != null` (child named `"CraftingStation"`). Holds the station's recipe list (copied from the def at `_ready`) and the active order `{recipe_id, given}` in the furniture's `state` bag under `"craft_order"`. Implements the MaterialSink contract from the order's inputs — a station with no order reports no needs and vacuous-satisfied, which closes any bound haul job through HaulingJobDef's normal lifecycle. Does NOT own the craft math.
**Used by:** craft panel UI (queue), HaulingJobDef (sink), CraftingJobDef (order API), Colony (signals).

| Property/Method | Type | Description |
|---|---|---|
| `recipes` | `Array[RecipeDef]` | Offered here; copied from `def.crafting_params` at `_ready`. |
| `queue_recipe(recipe_id)` | `-> bool` | Start an order (no-op if one is active / unknown id); emits `crafting_order_queued`. |
| `active_recipe()` | `-> RecipeDef?` | The order's recipe, or null (no order / def edited). |
| `has_active_order()` | `-> bool` | Order present. |
| `clear_order()` | `-> void` | Drop order + ledger (called by `CraftingJobDef.complete`). |
| `given_count(item_id)` | `-> int` | Deposited toward the order (panel progress read). |
| `anchor_cell()` | `-> Vector3i` | Footprint corner — Colony's dedupe key. |
| `needed_item_ids` / `remaining_need` / `deposit_from` / `has_complete_materials` | MaterialSink | The haul contract, read from the order's inputs. |

### Class: CraftingJobDef

**Extends:** JobDef (`data/jobs/crafting.tres`: id `craft`, labor `crafting`, single-assignee)
**Script:** `data/jobs/crafting_job_def.gd`
**Description:** Single WORK leg at the station (`job.target_node` = the CraftingStation node — it IS the sink, and freeing the furniture frees it, so the freed-target guard covers deconstruction). `begin` divides `recipe.base_time` by the crafter's skill multiplier; `complete` produces outputs (carry inventory first, overflow to the nearest crate) and clears the order. `meets_requirements` ANDs the active recipe's `conditions` (hot); `is_available` = order active + materials complete (the job only spawns on the crossing, and `given` never decreases, so it can't regress).

## Known gaps / deferred

- One order per station; no cancel/re-queue UI (rows disable while an order runs).
- No partial-work persistence across craft attempts (order + deposits survive; elapsed work doesn't).
- Forge + smelting skill deferred; recipe unlocking post-MVP.
- Jobs aren't recreated on save/load (pre-existing colony gap).
