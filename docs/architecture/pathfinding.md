# Subsystem: Pathfinding & Navigation

Voxel A* pathfinding, pluggable pathfinding strategies, hybrid walkability probing across dual-voxel terrain, stepped 3D locomotion, physics assist, and diagnostic visualization. GDD §6.

## Subsystem Overview

The pathfinding system provides intelligent navigation for colonists across both flat blocky floors and arbitrary continuous marching-cubes terrain, including underground excavated tunnels, ramps, and multi-tier construction sites.

Navigation is built around four decoupled layers:
1. **Target & Stand Resolution (`VoxelPathfinder`):** Converts world positions and multi-cell footprints into valid standable voxel cell coordinates.
2. **Hybrid Walkability Predicate (`map_wiring.gd` & `VoxelGridAdapter`):** Evaluates terrain solidity, floor support, vertical headroom clearance (>= 2m), and slope angles (<= 45 deg) across both blocky and smooth voxel grids.
3. **Pluggable Strategy Search (`PathfindingStrategy`):** Executes A*, 8-way, line-of-sight smoothed string pulling, or Theta* search algorithms based on the global `GameState` configuration or per-pathfinder override.
4. **Locomotion & Stepped Physics (`Colonist` & `StepClimber`):** Executes waypoint navigation with waist-height ray probing to hop steps up to 1.3m and walk off drops up to 3 cells.

---

## Flow Trace: Path Calculation Lifecycle

**Trigger:** `ColonistBrain` or Behavior Tree task (`BTActionNavigateTo`, `BTActionWander`) invokes `pathfinder.find_path_world()`, `find_path_to_adjacent()`, or `find_path_to_footprint_adjacent()`.

```
+------------------+     1. Resolve Stand Cell      +--------------------+
|  World Target /  | -----------------------------> |  find_stand_cell / |
|    Footprint     |                                |  find_stand_near   |
+------------------+                                +---------+----------+
                                                              |
                                  2. Delegate Search          v
+------------------+     3. Waypoint Conversion     +--------------------+
| World Waypoints  | <----------------------------- |PathfindingStrategy |
| (Smooth / Direct)|                                |(Smoothed/8Way/etc.)|
+------------------+                                +--------------------+
```

1. **Target Stand Resolution:**
   - For ground targets: `find_stand_cell` scans +/- 3 Y cells or evaluates the column stand hint.
   - For blocked footprints / blueprints / dig targets (e.g. 1-wide stairways down): `find_stand_near_cell` executes an expanding horizontal Chebyshev ring search (r = 1..4). Each ring position resolves its column's stand cell via `_stand_cell_in_column` — same-Y, then +/- 1 Y, then the column hint — regardless of hint presence, and the search returns the nearest valid walkable neighbour cell adjacent to the footprint.
   - For furniture/blueprint nodes with a known footprint: `find_path_to_footprint_adjacent` expands each footprint cell's 4 horizontal neighbour columns through the same `_stand_cell_in_column` resolution (hint bound 2), then runs multi-target A* over the candidate set — so a footprint raised one Y above the floor yields the ground cells beside it.
2. **Start Stand Resolution:**
   - Evaluates colonist current world position to the nearest standable cell via `find_stand_cell`. If the column and hint are unwalkable (e.g. inside a multi-cell blueprint), `find_stand_cell` falls back to a horizontal ring search (`find_stand_near_cell` with radius 3) to locate the nearest exterior standable perimeter cell.
3. **Walkability Evaluation (`map_wiring.gd` & `SmoothGrid.is_solid_at`):**
   - The composed `is_walkable(cell)` predicate runs `hybrid_ground_probe`:
     - **Carved Voxels:** `SmoothGrid.is_solid_at(pos)` (whole-cell rule, `is_solid_cell`) requires all 8 corner samples of `pos` to read `> -0.01` air before answering `false` (air) — carve dilation stamps one lattice plane into neighbouring walls, and a min-corner-only probe mistook those wall cells for hollow tunnel.
     - **Surface Ground Stand Cells:** `height_at` probes smooth surface height h. A cell `pos` is solid natural terrain iff h >= pos.y + 0.5. Open surface stand cells (h in [cell.y, cell.y + 1)) evaluate cell center height above ground as non-solid (`false`), so feet clearance is open.
     - **Surface Slope Gate:** Evaluates raycast surface normal `n.y >= cos(max_slope_deg) - 0.01`. The `-0.01` float tolerance accounts for float32 physics raycast normals on exact 45-degree carved ramp step faces against float64 GDScript math.
4. **Strategy Search Execution (`PathfindingStrategy`):**
   - Pathfinder delegates search to its configured `strategy` (default: `SmoothedAStarStrategy`).
   - Seeds `start_cell` in the open set and evaluates candidate expansions with the active heuristic (Octile, Euclidean, or Manhattan).
   - **Unwalkable Start Recovery:** If `start_cell` is unwalkable (e.g. inside a 1x1 blueprint), search seeds `start_cell` in the open set and enforces that all expanded step destinations pass `is_walkable`, allowing the colonist to step directly out of the obstacle toward the goal.
   - **Corner-Cutting Protection:** 8-way diagonal steps check that adjacent orthogonal cells are passable before stepping diagonally, preventing colonists from clipping through solid wall corners.
   - Computes movement cost: flat = 1.0, diagonal = 1.414, climb +1 Y = 3.0 (`jump_up_cost`), drop -N Y = 1.5 x N (`drop_cost_per_cell`).
   - Bounded by `max_explored = 8000` cells to prevent runaway searches.
5. **Path Output & String Pulling:**
   - Reconstructs cell chain from the strategy's `came_from` dictionary.
   - `to_world_waypoints()` converts cell coordinates to world-space centers (+0.5, +0.5, +0.5).
   - In `SmoothedAStarStrategy`, applies a 2D/3D Line-of-Sight (LOS) string-pulling post-processor across flat spans. Collinear waypoints over open ground are collapsed into direct straight-line vectors, while vertical step climbs (+1) and drops (-1..-3) remain anchored to cell centers so locomotion physics clean ledges safely.

---

## Flow Trace: Locomotion & Physics Obstacle Handling

**Trigger:** `Colonist.set_path(waypoints)` is called.

1. `Colonist._physics_process` computes horizontal velocity towards the next waypoint in the queue.
2. When approaching a vertical face (+Y step):
   - `StepClimber.try_step_up` performs a ray/box probe forward at character waist height.
   - Probes the landing surface height at step destination.
   - If landing rise in `(0, 1.3m]`, applies a vertical hop velocity boost to clear the ledge.
3. When waypoint distance `< 0.3m`, pops waypoint from queue.
4. **Stuck Guard:** If horizontal movement stalls for `> 0.4s`, applies lateral wiggle impulse. If stalling exceeds timeout, `has_arrived()` signals arrival or failure to `BTActionNavigateTo`.
5. Upon reaching the final waypoint, `has_arrived()` returns true.

---

## Class Reference

### Class: VoxelPathfinder

**Extends:** `Node`  
**Script:** `subsystems/colonists/voxel_pathfinder.gd`  
**Description:** Voxel pathfinder coordinating stand-cell resolution, telemetry diagnostics, and strategy execution. Generic and decoupled from voxel engine internals.  
**Used by:** `BTActionNavigateTo`, `BTActionWander`, `Colonist`, `ColonistDebugVisualizer`.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `strategy` | `PathfindingStrategy` | Active search strategy (default: `SmoothedAStarStrategy`, configured via `GameState`). |
| `last_query_start` | `Vector3i` | Diagnostic: start cell of the most recent A* query. |
| `last_query_target` | `Vector3i` | Diagnostic: target cell of the most recent A* query. |
| `last_stand_candidates` | `Array[Dictionary]` | Diagnostic: evaluated stand candidate cells from ring search. |
| `last_status` | `String` | Diagnostic: status string ("OK (N pts)", "FAIL (No path)", etc.). |
| `last_explored_count` | `int` | Diagnostic: number of cells expanded during search. |
| `last_query_time` | `float` | Diagnostic: engine-clock seconds of the last query (-1.0 = never); visualizer expires telemetry older than TTL. |

**Functions:**

| Function | Description |
|---|---|
| `set_strategy(new_strategy: PathfindingStrategy) -> void` | Replaces the active pathfinding strategy at runtime. |
| `set_walkability(predicate: Callable) -> void` | Injects the `(cell: Vector3i) -> bool` walkability predicate. |
| `set_stand_cell_hint(hint: Callable) -> void` | Injects the optional `(x: float, z: float) -> Vector3i` column stand hint. |
| `is_walkable(cell: Vector3i) -> bool` | Evaluates walkability of a single cell using the injected predicate. |
| `find_path(start_cell, target_cell) -> Array[Vector3i]` | Core path search over integer voxel coordinates delegating to `strategy`. |
| `find_stand_cell(world_pos: Vector3) -> Vector3i` | Resolves nearest standable cell within +/- 3 Y or column hint. |
| `find_stand_near_cell(center: Vector3i, max_radius: int = 4) -> Vector3i` | Ring search for nearest standable neighbour adjacent to a target/footprint. |
| `find_path_world(start_world, target_world) -> Array[Vector3]` | World-space entry point for open ground targets. |
| `find_path_to_adjacent(start_world, target_world, max_radius = 4) -> Array[Vector3]` | World-space entry point for blocked footprints (blueprints, crates, dig sites). |
| `find_path_to_footprint_adjacent(start_world, footprint: Array[Vector3i]) -> Array[Vector3]` | Multi-target routing to the closest walkable boundary cell of a multi-cell footprint. |
| `clear_diagnostics() -> void` | Resets all telemetry variables to idle defaults. |

---

### Class: PathfindingStrategy

**Extends:** `RefCounted`  
**Script:** `subsystems/colonists/pathfinding/pathfinding_strategy.gd`  
**Description:** Abstract base strategy for voxel search solvers and path smoothers.

**Concrete Implementations:**

| Class | Script | Description |
|---|---|---|
| `SmoothedAStarStrategy` | `subsystems/colonists/pathfinding/smoothed_a_star_strategy.gd` | **Default.** 8-way stepped A* search combined with 2D/3D Line-of-Sight string pulling across flat spans. |
| `AStar8WayStrategy` | `subsystems/colonists/pathfinding/a_star_8_way_strategy.gd` | 8-directional stepped A* using Octile distance heuristic and corner-cutting wall collision checks. |
| `AStar4WayStrategy` | `subsystems/colonists/pathfinding/a_star_4_way_strategy.gd` | Baseline 4-directional stepped orthogonal A* search. |
| `ThetaStarStrategy` | `subsystems/colonists/pathfinding/theta_star_strategy.gd` | Any-angle Theta* search evaluating line-of-sight shortcuts to parent nodes during open-set expansion. |

---

### Class: ColonistDebugVisualizer

**Extends:** `Node3D`  
**Script:** `subsystems/colonists/colonist_debug_visualizer.gd`  
**Description:** Development diagnostic visualizer attached to colonist instances. Draws real-time 3D wireframe representations of active paths, start/goal cells, candidate stand rings, StepClimber probes, and floating status labels.  

---

### Class: StepClimber

**Extends:** `Node3D`  
**Script:** `subsystems/colonists/step_climber.gd`  
**Description:** Physics climbing assist component. Probes forward obstacle geometry and applies vertical boost velocity when encountering climbable ledges and smooth terrain steps.  
