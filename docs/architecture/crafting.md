# Subsystem: Crafting

Recipe-driven conversion of materials into furniture, armor, weapons, ammo, and refined materials. GDD §7.9. Consumes from Inventory/colony storage; produces items back into storage. Craft Jobs register on the Job Board (no special-casing — they're Jobs like any other).

**Design notes:**
- **One unified `Recipe` data structure** for all craftable output (furniture, armor, weapons, ammo, smelting). Same shape regardless of output type.
- **`CraftingStation` is a furniture component** (attached to Workbench/Forge nodes) — owns the "which recipes are available here?" check. The recipe data itself lives in `data/recipes/`.
- **No tech tree in MVP** — all recipes available from the start; the constraint is materials + station + L1 skill gate. Post-MVP: unlocking.
- **Material flow goes through colony storage** (StorageCrate proximity per Inventory subsystem), not the colonist's personal inventory. This is why Hauling exists as a Labor — craft Jobs depend on materials being hauled to accessible storage.

## Files

| File | Type | Responsibility |
|---|---|---|
| `recipe.gd` | Script (Resource) | Data shape for one recipe: output, inputs, station, skill, base_time. Pure data; no behavior. See [Data Schemas](data-schemas.md). |
| `crafting_station.gd` | Script (component on furniture) | Attached to Workbench/Forge nodes. Owns the recipe list available at this station; registers craft Jobs on the Job Board. Does NOT own the craft math (Job Board + Skills + Stamina handle that). |
| `../data/recipes/workbench.tres` | Data | RecipeList for the Workbench (furniture, armor, weapons, ammo). See [Data Schemas](data-schemas.md). |
| `../data/recipes/forge.tres` | Data | RecipeList for the Forge (smelting: ore→metal, scrap→components, metal+components→reinforced). See [Data Schemas](data-schemas.md). |

## Signals

Crafting is local to the base scene + Colony (Job Board). No cross-scene signals.

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `craft_started(recipe_id, colonist_id)` | `crafting_station.gd` | HUD (optional notification) | No | Craft Job Executes |
| `craft_completed(recipe_id, output)` | `crafting_station.gd` | HUD (notification), Day Summary (production log) | No | Craft Job Executes |

## Flow Trace: Player queues a craft (Workbench)

**Trigger:** Player opens Workbench UI (or colony craft list), selects a recipe, confirms.

1. `CraftingStation` (on the Workbench node) receives the queue request with `recipe_id`.
2. Validates: recipe belongs to this station; player/colony has the materials in accessible storage (queries StorageCrate inventory via Inventory subsystem).
3. If materials available: reserves them (removed from storage now to prevent double-spend); creates a craft Job on the Job Board with `{recipe_id, station, base_time, skill: crafting}`.
4. If materials missing: reject the queue; emit nothing (UI shows "missing materials").

**End state:** Craft Job on the board; materials reserved; awaiting a colonist (or the player) to claim it.

## Flow Trace: Craft Job executes (colonist claims + completes)

**Trigger:** A colonist (or player) claims the craft Job via the standard Job Board flow (§6.10).

1. Colonist AI claims the Job; paths to the station (A* on voxel grid).
2. On arrival: `stamina_component.set_working(true)` (×2 drain active).
3. Each work tick: progress += `recipe.base_time × skill_set.get_multiplier("crafting") × stamina_component.get_work_multiplier() × delta`.
4. On progress ≥ `recipe.base_time`: craft completes.
5. `CraftingStation` consumes the reserved materials; produces `recipe.output_item × recipe.output_count` into colony storage (via Inventory add flow).
6. Emits `craft_completed(recipe_id, output)`; HUD notifies; Day Summary logs.
7. `skill_set.record_use("crafting")` grants skill progress; `stamina_component.set_working(false)`.
8. Job Board marks Job complete; colonist seeks next.

**End state:** Materials consumed; output in storage; Crafting skill progressed; Stamina burned at ×2; Job closed.

## Flow Trace: Smelting at the Forge (same flow, different station/skill)

**Trigger:** Player queues a smelting recipe (ore→metal, scrap→components, etc.) at the Forge.

1. Identical to the Workbench flow above, with substitutions:
   - Station = Forge (`crafting_station.gd` with `forge.tres` recipe list).
   - Skill = Smelting (not Crafting).
2. Same material-reservation, Job-Board, work-tick, skill-progress, output-deposit steps.

**End state:** Ore/scrap consumed; refined material in storage; Smelting skill progressed.

## Class Reference

### Class: CraftingStation

**Extends:** Node (component on furniture nodes — Workbench, Forge)
**Script:** `crafting_station.gd` (in `crafting/`)
**Description:** Attached to crafting-furniture nodes. Holds the station's recipe list; validates material availability; registers/reserves craft Jobs on the Job Board; produces output on completion. Does NOT own craft math (Skills + Stamina + Job Board handle the tick).
**Used by:** UI (craft list / queue), Colonists (Job Board claim → path → station).

**Properties:**

| Property | Type | Description |
|---|---|---|
| `station_id` | `String` | `"workbench"` or `"forge"`. |
| `recipes` | `RecipeList` | Loaded from `data/recipes/<station>.tres`. |
| `active_jobs` | `Array[String]` | Job IDs currently reserved at this station (for UI + cap if needed). |

**Signals:**

| Signal | Description |
|---|---|
| `craft_started(recipe_id: String, colonist_id: String)` | Optional HUD notification. |
| `craft_completed(recipe_id: String, output: Dictionary)` | `{item_id, count}` produced; HUD + Day Summary log. |

**Functions:**

| Function | Description |
|---|---|
| `queue_craft(recipe_id: String) -> bool` | Validates materials + station; reserves materials; creates Job on Job Board. Returns false if invalid. |
| `get_available_recipes() -> Array[Recipe]` | All recipes this station can craft (filtered by station_id; no tech-tree gating in MVP). |
