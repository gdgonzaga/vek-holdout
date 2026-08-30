# Subsystem: Crafting

Recipe-driven conversion of materials into items at crafting stations (GDD §7.9). The station is a **furniture component** (`CraftingStation`, the `StorageInventory` pattern — not a `Furniture` subclass), its order is a **MaterialSink** hauling can feed like a blueprint's, and crafting itself is **dual-mode**: a colonist craft Job or the player personally at the bench — one order, two possible workers, the same pattern blueprints already use (player `BuildAction` vs `ConstructionJobDef`).

> **Status: built (2026-08-15, `test/suite_crafting_test.gd`).** Workbench ships with `wooden_board` (3 planks → 1, authored in `data/crafting/`) and `axe` (2 planks + 1 stone block → 1, `data/recipes/axe.tres`) in its `CraftingParams.recipes`. `planks` (1 wood block → 4) is authored in `data/recipes/planks.tres` but referenced by no station yet. Forge + smelting deferred (no forge FurnitureDef, no smelting skill in the catalog) — the shared component/def make it data-only work later.

**Design notes:**
- **One unified `Recipe` shape** for all craftable output (`RecipeDef`: furniture, armor, weapons, ammo, smelting). Same fields regardless of output type.
- **`CraftingStation` is a component attached to furniture nodes** (Workbench today, Forge later) — owns "which recipes are available here?" and the active order. The recipe data lives in `data/recipes/` referenced from the def's `CraftingParams`.
- **No tech tree in MVP** — all recipes available from the start; the constraint is materials + station + skill gate (L1 Crafting via `RecipeDef.conditions`). Post-MVP: unlocking.
- **Material flow goes through hauling** (MaterialSink → crates), not reservation at queue time. Queueing never rejects for missing materials — the haul job drought-waits on the board (HaulingJobDef lifetime semantics) and restock resumes it with no new producer event.
- **Dual-mode, one ledger**: the deposit ledger belongs to the order, not to a worker — haulers fill player-queued orders too, and the player may Craft-now any *ready* order (colonist-queued ones included). The modes differ only in who works: `worker "colony"` (craft job; the crossing emits `crafting_materials_ready`) vs `worker "player"` (reserved — no emit, no craft job; the order waits for the player).
- **Claim lock**: while anyone is mid-WORK (a colonist's WORK phase or the player's ActionProgress gauge), the station is claimed; colonists refuse to start and so does the player — except against their *own* claim, which never blocks them (the player can't overlap their own gauge: the panel closes and busy-locks first), making a stale player claim self-healing rather than a bricked station (Kenshi's one-worker-per-bench rule, enforced per order).
- **Maintain orders** ("until stock: N", colony-only): on completion, if `StorageRegistry.colony_stock(first output) < N` the station requeues the same recipe through the standard chain — a RimWorld "do until you have X" one-shot, not a standing bill and not Kenshi's loop-forever repeat. Colony-order outputs drop as **WorldItems** at the station for haulers to transport to storage; player crafts are pocket-first.
- **Player SkillSet**: the Player carries a SkillSet (code-created, unseeded). Recipe conditions gate personal crafting, duration divides by the player's crafting multiplier, and personal crafts train it.

## Files

| File | Type | Responsibility |
|---|---|---|
| `data/crafting/recipe_def.gd` | Script (Resource) | Data shape for one recipe: inputs/outputs (`Array[ItemAmount]`), `base_time`, recipe-level `conditions`. Pure data. See [Data Schemas](data-schemas.md). |
| `data/capability_params/crafting_params.gd` | Script (Resource) | Capability sub-resource on `FurnitureDef`: `recipes: Array[RecipeDef]`. Non-null → FurnitureLayer attaches the station. |
| `subsystems/crafting/crafting_station.gd` | Script (component on furniture) | The order + deposit ledger; implements MaterialSink from the active order; worker reservation, claim lock, maintain requeue, cancel. Does NOT own the craft math. |
| `data/jobs/crafting_job_def.gd` + `crafting.tres` | Script + data | Colonist craft Job: WORK leg at the station, skill-scaled duration, claim handshake, world item drop production, `complete_order` resolution. `produce()` is the shared craft-math entry (CraftAction reuses it). |
| `data/actions/craft_action.gd` | Script (GameAction) | The player's personal craft: claim, ActionProgress gauge (Esc persists `work_done`, restart resumes), pocket-first production, player XP. Invoked by the panel (no ActionOption wiring). |
| `data/actions/open_crafting_action.gd` + `ui/crafting/craft_panel.tscn` | Action + UI | E on the workbench → the craft panel: per-recipe Queue (with "until stock" SpinBox) / Craft buttons, order section with Craft now / Cancel. |
| `data/recipes/*.tres` | Data | Recipe resources referenced from the station def's CraftingParams. |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `crafting_order_queued(station, anchor)` | `CraftingStation.queue_recipe` (both workers, and every maintain requeue) | Colony | Yes | Player Queues a Craft |
| `crafting_materials_ready(station, anchor)` | `CraftingStation.deposit_from` (single-fire per order, **colony orders only**) | Colony | Yes | Player Queues a Craft |
| log feed entries | `GameLog.craft(...)` | log feed UI | No | queue / materials-ready / crafted / cancelled lines |

## Flow Trace: Player queues a craft (Workbench)

**Trigger:** Player E-presses the workbench → `OpenCraftingAction` → `ui/crafting/craft_panel.tscn`.

1. **Queue** (colony): `queue_recipe(id, "colony", maintain?)`. **Craft** (personal): `queue_recipe(id, "player")` then the panel deposits whatever the player carries (`station.deposit_from(player)`) — shortfalls are hauled either way. Both emit `crafting_order_queued`; an "until stock" SpinBox ≥ 1 attaches a maintain goal to a colony queue.
2. `Colony._on_crafting_order_queued`: spawns a **haul job bound to the station** (deduped by anchor + def), regardless of crate stock — droughts wait on the board.
3. Haulers loop FETCH → DELIVER (`station.deposit_from`) until the order's inputs are covered.
4. The DELIVER crossing `has_complete_materials`: colony orders emit `crafting_materials_ready` → `Colony._spawn_craft_job`; player orders emit nothing — the order waits ready for the player.
5. **Who works it:** a colonist claims the craft Job (labor `crafting`, gated by `RecipeDef.conditions`), or the player presses **Craft now** (offered on any ready order) → `CraftAction`.

**End state:** order worked → outputs produced (colony: world item drop at station; player: pocket-first) → `complete_order` resolves it (maintain orders requeue while stock < target) → next order can be queued.

## Flow Trace: Craft Job executes (colonist)

1. Colonist claims via the standard Job Board flow; paths to the station (`job.location` = footprint center).
2. `begin` = `recipe.base_time ÷ skill_set.get_multiplier("crafting")` and **claims the station** under the colonist's id. If the player's gauge holds the claim, `begin` reports instant and `complete` no-ops — the colonist backs off cleanly instead of double-producing.
3. WORK ticks in ColonistAI; on elapse `complete` runs: `produce()` (world item drop at station) → `complete_order()` (maintain requeue or clear) → `GameLog.craft`.
4. XP is automatic (`record_use_for_labor("crafting")` in `_end_job`). A null next leg is always a clean finish for this def (the maintain requeue leaves a fresh not-ready order — not a stall).

## Flow Trace: Player crafts personally (CraftAction)

1. Panel's **Craft now** closes the panel and runs `CraftAction.execute(player, station)` (guarded: ready + unclaimed).
2. Duration = `base_time ÷ player skill multiplier`; instant path for 0-duration recipes. The gauge claims the station under `"player"`, locks the player (`set_busy`), frees the mouse; **Esc cancels** → claim released + `work_done` persisted on the order → a restart **resumes**.
3. Completion re-guards workability (the order can't have been resolved by anyone else while claimed — but the station may have been freed): `produce()` pocket-first (crate overflow), `complete_order()`, `record_use_for_labor` → the player's crafting skill grows.
4. Recipe conditions are evaluated by the *panel* (Craft button disabled + tooltip when the player fails) — the action itself only guards workability.

## Flow Trace: Cancel + interruptions

- **Cancel** (order section): refunds the ledger to the nearest crate, clears the order. Bound jobs self-clean through the normal lifecycle (no-order station reads satisfied → haul job closes; craft job closes on order-gone).
- **Station freed mid-anything:** ColonistAI's freed-target guard aborts the colonist; the player's gauge guards `is_instance_valid` on completion (the same stale-target guard backported to BuildAction).
- **Save/load:** the order (recipe, given, worker, maintain, work_done) round-trips through `Furniture.state`; jobs and claims are runtime-only (a loaded order is never left locked); jobs aren't recreated on load (the pre-existing colony gap).

## Class Reference

### Class: CraftingStation

**Extends:** Node (component on furniture nodes — Workbench today, Forge later)
**Script:** `subsystems/crafting/crafting_station.gd`
**Description:** Attached by `FurnitureLayer._create_furniture_node` when `def.crafting_params != null` (child named `"CraftingStation"`). Holds the station's recipes (from the def at `_ready`) and the active order in the furniture's `state` bag under `"craft_order"`: `{recipe_id, given, worker, maintain?, work_done}`. Implements the MaterialSink contract from the order's inputs; a station with no order reports no needs and vacuous-satisfied (closing bound haul jobs).
**Used by:** craft panel, HaulingJobDef (sink), CraftingJobDef + CraftAction (order API), Colony (signals).

| Property/Method | Type | Description |
|---|---|---|
| `queue_recipe(id, worker, maintain)` | `-> bool` | Start an order (no-op if one is active); emits `crafting_order_queued`. |
| `worker()` / `maintain_goal()` | `-> String/Dictionary` | Reservation ("colony"/"player") and maintain target reads. |
| `is_ready()` / `can_player_work()` | `-> bool` | Inputs complete; ready AND unclaimed. |
| `claim(owner)` / `release_claim(owner)` / `is_claimed()` | lock API | Owner-matched work claim (idempotent; mismatched release no-ops). |
| `complete_order()` | `-> void` | Post-craft resolution: maintain requeue (via `queue_recipe`, so the haul producer refires) or clear; releases the claim. |
| `cancel_order()` | `-> void` | Refund ledger to the nearest crate + clear; jobs self-clean. |
| `work_done()` / `set_work_done(v)` | `-> float` | Player gauge resume state (persists in the state bag). |
| `is_paused()` / `set_paused(value)` | `-> bool/void` | Station pause flag (state bag under `crafting_paused`) — a paused station's craft jobs go unclaimable (`CraftingJobDef._workable` checks it); persists across save/load. |
| `needed_item_ids` / `remaining_need` / `deposit_from` / `has_complete_materials` | MaterialSink | The haul contract, read from the order's inputs (crossing emits only for colony orders). |

### Class: CraftingJobDef

**Extends:** JobDef (`crafting.tres`: labor `crafting`, single-assignee)
**Script:** `data/jobs/crafting_job_def.gd`
**Description:** Single WORK leg at the station (`job.target_node` = the station node). `begin` divides `base_time` by the crafter's multiplier and claims the station; `complete` re-checks the claim (player-gauge race), produces world item drop at station, and resolves via `complete_order`. `produce(actor, station, recipe, pocket_first)` is the shared craft math — CraftAction reuses it pocket-first. `meets_requirements` ANDs the active recipe's conditions (hot).

### Class: CraftAction

**Extends:** GameAction (`data/actions/craft_action.gd`)
**Description:** The player's personal craft — the BuildAction template applied to a station order: claim under `"player"`, `set_busy` + ActionProgress (`setup("Crafting …", duration, station.work_done())` — resume on Esc-cancel), completion re-guard, pocket-first `produce`, `complete_order`, `record_use_for_labor`. Panel-invoked (no `.tres`/ActionOption wiring). Player duration divides by the player's crafting multiplier (SkillSet on the Player).

## Known gaps / deferred

- One order per station; no multi-item queue (Kenshi's per-bench queue) — the maintain goal covers batch needs.
- Maintain orders are one-shot targets, not standing bills (stock falling later doesn't auto-resume).
- Player orders don't participate in maintain; personal crafting is one-shot by design.
- No partial-work persistence for *colonist* crafts (the order + deposits survive an abort; elapsed WORK doesn't — only the player gauge resumes).
- Forge + smelting skill deferred; recipe unlocking post-MVP.
- Jobs aren't recreated on save/load (pre-existing colony gap).
