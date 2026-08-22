# Subsystem: Pathfinding & Navigation

Voxel A* pathfinding, hybrid walkability probing across dual-voxel terrain, stepped 3D locomotion, physics assist, and diagnostic visualization. GDD §6.

The pathfinding system provides intelligent navigation for colonists across both flat blocky floors and arbitrary continuous marching-cubes terrain, including underground excavated tunnels, ramps, and multi-tier construction sites.

## Design Notes: Problems, Solutions & Rationales

### 1. Dual-Voxel Multi-Layer Walkability & Excavated Tunnels

- **Problem:** The original walkability seam (D4) relied purely on downward physics raycasts from the sky (`SmoothGrid.height_at`). On natural terrain, this only detected the topmost exterior surface of hills. When colonists mined underground rooms or tunnels beneath a hill, the downward raycast hit the mountain roof above rather than the excavated floor below, marking underground tunnel cells as completely unwalkable (buried inside rock) and preventing colonists from navigating inside mines.
- **Solution:** `MapWiring._compose_walkability` and `MapWiring.hybrid_ground_probe` combine `height_at` with direct signed distance field (SDF) voxel sampling (`SmoothGrid.is_solid_at` and `VoxelGridAdapter.is_terrain_at`). An excavated cell with SDF $\\ge 0.0$ is recognized as traversable air regardless of whether solid terrain exists higher up in the column.
- **Rationale:** Dual-voxel base building requires seamless transitions between outdoor surface slopes and subterranean excavated networks. Probing the local voxel lattice SDF enables multi-story underground structures without breaking surface slope gating.

### 2. Head Clearance in Enclosed Cavities

- **Problem:** Colonist entities are $1.8\\text{m}$ tall capsules requiring at least 2 full vertical voxel cells ($2\\text{m}$) of vertical clearance. In narrow or partially carved tunnels, a stand cell could have walkable floor support, but have solid ceiling geometry immediately above it ($Y+1$), causing colonist capsules to clip into ceilings or get wedged during path execution.
- **Solution:** `MapWiring._compose_walkability` explicitly enforces head clearance: for any cell $C$ to be standable, $C$ must be air, $C - Y$ must provide solid floor support, and $C + Y$ (head space) must also be non-solid (`not is_solid_at(cell + Vector3i.UP)`).
- **Rationale:** Moving head clearance validation into the A* predicate prevents the pathfinder from ever generating paths through 1-block-high crawlspaces that the physics engine will reject.

### 3. Capsule Wall Clearance & SDF Safety Margins

- **Problem:** CharacterBody3D capsules have a collision radius of $0.35\\text{m}-0.4\\text{m}$. Discrete point probes evaluating SDF at exactly $0.0$ (the mathematical zero-isosurface) allowed path waypoints to pass dangerously close to jagged marching-cubes walls. Colonists following these waypoints frequently collided with wall micro-geometry, stopping locomotion.
- **Solution:** Evaluated solidity via direct signed distance field checks (treating $\\text{SDF} > -0.01$ as excavated air/surface) in `SmoothGrid.is_solid_at` and `VoxelGridAdapter.is_terrain_at`.
- **Rationale:** Incorporating the capsule radius into walkability solidity checks creates an automatic safety buffer around walls and corners, keeping waypoints centered in open air.

### 4. Stepped Locomotion & Continuous Ramp Transitions

- **Problem:** Marching-cubes terrain extraction on $45^\\circ$ slopes generates smooth continuous ramps whose step-to-step height differential can exceed $1.0\\text{m}$ (up to $1.2\\text{m}-1.3\\text{m}$) due to vertex interpolation. Colonists using the standard $1.05\\text{m}$ hop height failed to climb ramps. Furthermore, `find_stand_near_cell` assumed same-Y neighbors, failing to find stand locations when target blueprints or dig jobs sat on a slope.
- **Solution:**
  - Increased `StepClimber.hop_height` on `colonist.tscn` to $1.3\\text{m}$.
  - Updated `find_stand_near_cell` in `VoxelPathfinder` to search $\\pm 1 Y$ neighbor steps on slopes and query column stand hints.
- **Rationale:** Real terrain is non-discrete; physical climbing assists and stand-cell resolvers must accommodate smooth slope variance without requiring artificial stair blocks for every incline.

### 5. Physics Snags & Dynamic Impulse Wiggling

- **Problem:** Irregular physics collisions, sliding friction along multi-body boundaries, or grazing corner contacts could occasionally stall colonist movement even with valid paths.
- **Solution:** Added a stuck detection timer in `Colonist._physics_process`. If horizontal progress towards the current waypoint remains near zero ($< 0.05\\text{m}$) for $> 0.4\\text{s}$, the colonist applies a lateral/vertical impulse ("wiggle") to dislodge the capsule. If progress remains blocked, the job leg aborts to trigger path recalculation.
- **Rationale:** Provides resilient, self-healing locomotion in dynamic user-modified voxel geometry without hard locking the labor simulation.

### 6. Telemetry Lifecycle & Diagnostic Visualizer Clutter

- **Problem:** `ColonistDebugVisualizer` renders A* start/target bounding boxes, ring search candidates, and 3D billboard text. Retaining telemetry after job completion caused obsolete green/red debug wireframes and stale A* status strings to linger at previous job sites. Two residue sources remained after the initial `clear_diagnostics()` fix: the colonist's unconsumed waypoints (dig jobs routinely enter work range with the path unfinished, so the tether, path strip and target box kept redrawing from `Colonist._path` after the job closed), and telemetry frozen by a failed initial claim (the unreachable-cell case) whose job then went to backoff-sleep with no further queries to refresh or clear it.
- **Solution:** `ColonistAI._end_job()` now also clears the locomotion path via `Colonist.set_path([])` alongside `VoxelPathfinder.clear_diagnostics()`. Additionally, every telemetry-writing query stamps `last_query_time`, and the visualizer only draws telemetry-derived elements (A* boxes, ring candidates, status line, telemetry target fallback) while the stamp is within a TTL ($5\\text{s}$) — the same self-expiry idea as the StepClimber probe window. Clearing the diagnostics on a failed claim was rejected: query and clear land in the same tick, which would blank exactly the unreachable-target boxes the tool exists to show.
- **Rationale:** Visual debug tools must reflect real-time entity state without leaving phantom indicators in the world.

### 7. Stand Resolution for Footprints Raised Above the Floor

- **Problem:** Build jobs target the blueprint node; since `Blueprint extends Furniture`, `ColonistAI._path_for_leg` routes them through `find_path_to_footprint_adjacent`, whose candidate expansion probed only same-$Y$ horizontal neighbours of the footprint cells. A block blueprint placed on top of an existing block sits one $Y$ above the walkable floor — every same-$Y$ neighbour is air with no floor — so the query yielded zero candidates (`FAIL (No walkable adjacent cells to footprint)`), and the job failed on the board until auto-removed. `find_stand_near_cell`'s $\\pm 1 Y$ probes had the same blind spot on blocky-only maps, where they were gated behind the smooth-terrain column hint being injected.
- **Solution:** Extracted `_stand_cell_in_column(col_base, max_hint_dy)` — the first standable cell among same-$Y$, $+1 Y$, $-1 Y$, then the hinted column cell — used by both the ring search (hint bound $r+1$) and the footprint expansion (bound 2, the ring $r{=}1$ equivalent). The $\\pm 1$ probes are unconditional; the hint only extends reach beyond one vertical step.
- **Rationale:** "Stand adjacent to this footprint" is a question about columns, not cells: the walkable ground beside a raised target routinely sits one $Y$ below it. Both stand-cell resolvers must agree on that answer, on smooth-terrain and blocky-only maps alike.

## Files

| File | Type | Responsibility |
|---|---|---|
| `subsystems/colonists/voxel_pathfinder.gd` | Script (component) | Core A* over integer voxel coordinates with stepped neighbor model, dynamic costs, multi-target queries, and stand-adjacent ring/footprint column resolution. |
| `subsystems/colonists/step_climber.gd` | Script (component) | Physical obstacle negotiation: upward hop assists ($1.3\\text{m}$ max rise) and step-down smoothing for CharacterBody3D locomotion. |
| `subsystems/colonists/colonist_debug_visualizer.gd` | Script (component) | Dev visualization: ImmediateMesh 3D path lines, A* start/goal bounding boxes, candidate ring cells, step climber landing probes, and billboard text. |
| `subsystems/colonists/colonist.gd` | Script | Locomotion execution: waypoint consumption, look-ahead vectoring, stuck detection, dynamic wiggle impulses, and StepClimber integration. |
| `subsystems/maps/map_wiring.gd` | Script | Injects the composed `is_walkable(Vector3i)` Callable and `smooth_stand_hint(x, z)` into active pathfinders. |

## Signals

*(Pathfinding is a self-contained query component; it emits no EventBus signals. State changes are communicated via direct method return values and `ColonistAI` state transitions.)*

## Flow Trace: Resolving Stand Cells & Finding Paths

**Trigger:** `ColonistAI` claims a job and requests a path to a target position (`find_path_to_adjacent`, `find_path_to_footprint_adjacent`, or `find_path_world`).

1. **Target Stand Resolution:**
   - For ground targets: `find_stand_cell` scans $\\pm 3 Y$ cells or evaluates the column stand hint.
   - For blocked footprints / blueprints / dig targets (e.g. 1-wide stairways down): `find_stand_near_cell` executes an expanding horizontal Chebyshev ring search ($r = 1..4$). Each ring position resolves its column's stand cell via `_stand_cell_in_column` — same-$Y$, then $\\pm 1 Y$, then the column hint — regardless of hint presence, and the search returns the nearest valid walkable neighbour cell adjacent to the footprint.
   - For furniture/blueprint nodes with a known footprint: `find_path_to_footprint_adjacent` expands each footprint cell's 4 horizontal neighbour columns through the same `_stand_cell_in_column` resolution (hint bound 2), then runs multi-target A* over the candidate set — so a footprint raised one $Y$ above the floor yields the ground cells beside it.
2. **Start Stand Resolution:**
   - Evaluates colonist current world position to the nearest standable cell via `find_stand_cell`.
3. **Walkability Evaluation (`map_wiring.gd` & `SmoothGrid.is_solid_at`):**
   - The composed `is_walkable(cell)` predicate runs `hybrid_ground_probe`:
     - **Carved Voxels:** `SmoothGrid.is_solid_at(pos)` checks `vt.get_voxel_f(pos) > -0.01` for carved air (e.g. subterranean stairways / tunnels), returning `false` (air).
     - **Surface Ground Stand Cells:** `height_at` probes smooth surface height $h$. A cell `pos` is solid natural terrain iff $h \ge \text{pos.y} + 0.5$. Open surface stand cells ($h \in [\text{cell.y}, \text{cell.y} + 1)$) evaluate cell center height above ground as non-solid (`false`), so feet clearance is open.
     - **Surface Slope Gate:** Evaluates raycast surface normal $n.y \ge \cos(\text{max\_slope\_deg}) - 0.01$. The $-0.01$ float tolerance accounts for float32 physics raycast normals on exact 45-degree carved ramp step faces against float64 GDScript math.
4. **A* Search Execution (`find_path`):**
   - Initializes open list with `start_cell`, evaluated with Manhattan horizontal heuristic $\\Delta X + \\Delta Z$.
   - Expands stepped neighbors (4 horizontal dirs $\\times$ $\\Delta Y \\in \\{+1, 0, -1, -2, -3\\}$).
   - Queries injected `_is_walkable` predicate on every candidate cell lazily.
   - Computes movement cost: flat = $1.0$, climb $+1 Y$ = $3.0$ (`_JUMP_UP_COST`), drop $-N Y$ = $1.5 \\times N$ (`_DROP_COST_PER_CELL`).
   - Bounded by `_MAX_EXPLORED = 8000` cells to prevent runaway searches.
5. **Path Output:**
   - Reconstructs cell chain and converts to world coordinates centered at cell midpoints ($+0.5, +0.5, +0.5$) via `to_world_waypoints`.

## Flow Trace: Locomotion & Physics Obstacle Handling

**Trigger:** `Colonist.set_path(waypoints)` is called.

1. `Colonist._physics_process` computes horizontal velocity towards the next waypoint in the queue.
2. When approaching a vertical face ($+Y$ step):
   - `StepClimber.try_step_up` performs a ray/box probe forward at character waist height.
   - Probes the landing surface height at step destination.
   - If landing rise $\\in (0, 1.3\\text{m}]$, applies a vertical hop velocity boost to clear the ledge.
3. When waypoint distance $< 0.3\\text{m}$, pops waypoint from queue.
4. **Stuck Guard:** If horizontal movement stalls for $> 0.4\\text{s}$, applies lateral wiggle impulse. If stalling exceeds timeout, `has_arrived()` signals arrival or failure to `ColonistAI`.
5. Upon reaching the final waypoint, `has_arrived()` returns true.

## Class Reference

### Class: VoxelPathfinder

**Extends:** `Node`  
**Script:** `subsystems/colonists/voxel_pathfinder.gd`  
**Description:** Voxel A* pathfinder with an injected walkability predicate and stepped 3D neighbor expansion model. Generic and decoupled from voxel engine internals.  
**Used by:** `ColonistAI`, `Colonist`  

**Properties:**

| Property | Type | Description |
|---|---|---|
| `last_query_start` | `Vector3i` | Diagnostic: start cell of the most recent A* query. |
| `last_query_target` | `Vector3i` | Diagnostic: target cell of the most recent A* query. |
| `last_stand_candidates` | `Array[Dictionary]` | Diagnostic: evaluated stand candidate cells from ring search. |
| `last_status` | `String` | Diagnostic: status string ("OK (N pts)", "FAIL (No path)", etc.). |
| `last_explored_count` | `int` | Diagnostic: number of cells expanded during search. |
| `last_query_time` | `float` | Diagnostic: engine-clock seconds of the last telemetry-writing query (-1.0 = never); the visualizer expires telemetry older than its TTL. |

**Functions:**

| Function | Description |
|---|---|
| `set_walkability(predicate: Callable) -> void` | Injects the `(cell: Vector3i) -> bool` walkability predicate. |
| `set_stand_cell_hint(hint: Callable) -> void` | Injects the optional `(x: float, z: float) -> Vector3i` column stand hint. |
| `is_walkable(cell: Vector3i) -> bool` | Evaluates walkability of a single cell using the injected predicate. |
| `find_path(start_cell, target_cell) -> Array[Vector3i]` | Core A* over integer voxel coordinates. |
| `find_stand_cell(world_pos: Vector3) -> Vector3i` | Resolves nearest standable cell within $\\pm 3 Y$ or column hint. |
| `find_stand_near_cell(center: Vector3i, max_radius: int = 4) -> Vector3i` | Ring search for nearest standable neighbour adjacent to a target/footprint. |
| `find_path_world(start_world, target_world) -> Array[Vector3]` | World-space entry point for open ground targets. |
| `find_path_to_adjacent(start_world, target_world, max_radius = 4) -> Array[Vector3]` | World-space entry point for blocked footprints (blueprints, crates, dig sites). |
| `find_path_to_footprint_adjacent(start_world, footprint: Array[Vector3i]) -> Array[Vector3]` | Multi-target A* routing to the closest walkable boundary cell of a multi-cell footprint. |
| `clear_diagnostics() -> void` | Resets all telemetry variables to idle defaults. |

---

### Class: ColonistDebugVisualizer

**Extends:** `Node3D`  
**Script:** `subsystems/colonists/colonist_debug_visualizer.gd`  
**Description:** Development diagnostic visualizer attached to colonist instances. Draws real-time 3D wireframe representations of active paths, start/goal cells, candidate stand rings, StepClimber probes, and floating status labels.  
**Used by:** Developer playtesting, debug inspection.  

**Properties:**

| Property | Type | Description |
|---|---|---|
| `draw_path` | `bool` | Toggles drawing of the active 3D path polyline and waypoint markers. |
| `draw_tether` | `bool` | Toggles direct colonist-to-goal vector tether. |
| `draw_diagnostics` | `bool` | Toggles A* cell boxes, candidate ring markers, and StepClimber probe boxes. |
| `label_height_offset` | `float` | Vertical offset ($2.2\\text{m}$) for the 3D billboard text label. |

---

### Class: StepClimber

**Extends:** `Node3D`  
**Script:** `subsystems/colonists/step_climber.gd`  
**Description:** Physics climbing assist component. Probes forward obstacle geometry and applies vertical boost velocity when encountering climbable ledges and smooth terrain steps.  
**Used by:** `Colonist`, `Player`  

**Properties:**

| Property | Type | Description |
|---|---|---|
| `hop_height` | `float` | Maximum climbable step rise ($1.3\\text{m}$ on colonists, $1.05\\text{m}$ on player). |
| `probe_distance` | `float` | Forward distance for obstacle detection. |
| `forward_bias` | `float` | Horizontal impulse applied during hop execution. |
