# Subsystem: Functional Rooms

Tracks which functional-furniture types are placed in the colony and how many of each. Gates capability unlocks (world map, crafting, smelting, etc.) and feeds the raid visibility bonus. GDD §7.8.

> **Implementation status: planned, not yet built.** The design below is the intended shape, but **none of it exists in `colony.gd` yet** — there is no `functional_counts` state, no `_on_block_placed` / `_on_block_destroyed` listeners, and no `count_functional_furniture()` / `count_of()` / `has_functional()` surface. The `data/furniture/` schema (`is_functional` + `functional_area`) is also still pending (C1). Treat this section as the spec to implement against, not a description of current code. The pieces it depends on *do* exist: `VoxelGrid` emits `block_placed` / `block_destroyed`, and `FurnitureLayer` emits `furniture_placed` / `furniture_removed` (the more likely source once furniture is non-block — see note below).

**Design notes:**
- **No room detection** — there's no bounding-box or enclosure check. "Functional area unlocked" means *at least one of the furniture type exists in the colony*, placed anywhere.
- **"Functional furniture" = the 7 area-defining types only** (Clinic Bed, Workbench, Forge, Command Desk, Vehicle Lift, Colonist Bed, Growing Trough). Storage crates, watchtowers, spike traps, lamps do NOT count.
- **Counts live directly on the Colony autoload** (not a separate child). It's just 7 integers — too small to justify a 5th Colony child. Colony exposes the query surface; ThreatModel and UI read from it.
- **Signal source — open question.** The doc previously assumed Colony subscribes to `VoxelGrid.block_placed` / `block_destroyed`. With the two-kind placement model now landed (Build subsystem), functional furniture is a `FurnitureDef` placed via `FurnitureLayer`, which emits `furniture_placed` / `furniture_removed` on EventBus — not `block_placed`. Decide at implementation time whether to count from the furniture emissions, the voxel emissions (only relevant if a functional type is ever a `BlockDef`), or both.

## Files

| File | Type | Responsibility |
|---|---|---|
| *(no separate script — functionality folded into Colony autoload)* | — | Colony tracks `functional_counts: Dictionary[String, int]` directly; the placement/destroy listeners + query methods are Colony methods. Documented here because the *feature* is distinct even though the code lives on Colony. |
| `../data/furniture/` | Data | FurnitureDef per type — includes `is_functional: bool` flag + `functional_area: String` so the registry knows which placements to count. Schema pending (C1). |

## Signals

*(No new signals — Functional Rooms subscribes to VoxelGrid's `block_placed`/`block_destroyed` and exposes query methods. The consumer-side reaction is pull-based: ThreatModel and UI call `Colony.count_functional_furniture()` when they need it.)*

## Flow Trace: Placing functional furniture updates the registry

**Trigger:** Player (or colonist via construction Job) places a furniture block via the Build subsystem; VoxelGrid emits `block_placed(pos, block_id)`.

1. Colony listens for `block_placed`.
2. Looks up the block's FurnitureDef (from `data/furniture/`).
3. If `def.is_functional == true`: increment `functional_counts[def.functional_area]`.
4. (No emission — consumers pull on demand. UI can poll on its refresh tick; ThreatModel pulls at raid-start.)

**End state:** Colony's functional count for that area incremented; capability unlocked if it was the first; visibility bonus increased (+3 to all edges, applied at next raid).

## Flow Trace: Raid visibility reads the functional count

**Trigger:** RaidScheduler computes a new raid (on `day_rolled_over`, if colony ≥ 3 colonists).

1. ThreatModel needs the colony's visibility bonus.
2. Calls `Colony.count_functional_furniture()` → sums all 7 counts (per-item: 3 Workbenches + 1 Clinic Bed = 4).
3. Applies `+3 per item to all edges equally` → bumps each edge weight by `(count × 3)`.
4. Proceeds with weighted-random edge selection per the normal threat-direction flow.

**End state:** Raid threat edges reflect the colony's current functional-furniture footprint.

## Class Reference

*(Planned — methods/state live on the Colony autoload. None of this is implemented yet; documented here because the feature is distinct even though the code will live on Colony.)*

### Colony methods (Functional Rooms surface)

| Function | Description |
|---|---|
| `count_functional_furniture() -> int` | Sum of all 7 functional-furniture counts (per-item). Used by ThreatModel for the visibility bonus. |
| `count_of(type: String) -> int` | Count of a specific functional type (e.g. `"workbench"`). |
| `has_functional(type: String) -> bool` | True if at least one of `type` is placed. Used by UI for capability-unlock gating (e.g. world-map tab greyed out until `has_functional("command_desk")`). |
| `_on_block_placed(pos: Vector3i, block_id: String) -> void` | VoxelGrid signal listener; increments `functional_counts` if the block is functional furniture. |
| `_on_block_destroyed(pos: Vector3i) -> void` | VoxelGrid signal listener; decrements the relevant counter. |

**State on Colony:**

| Property | Type | Description |
|---|---|---|
| `functional_counts` | `Dictionary[String, int]` | 7 entries keyed by functional_area (`"command"`, `"medical"`, `"crafting"`, `"smelting"`, `"vehicle"`, `"rest"`, `"farming"`). Saved with Colony state. |
