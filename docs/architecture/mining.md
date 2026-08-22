# Mining Subsystem

The mining subsystem handles voxel excavation, strata-driven terrain generation and material composition, and player dig box designation.

## Architecture

Mining interacts with both the natural smooth terrain (`SmoothGrid`) and blocky structures (`BlockyGrid`) via the unified `VoxelGridAdapter`.

```
Player (Shift+G) -> DigBoxController (Raycast / Ghost preview / Box math)
                          |
              EventBus.dig_box_designated
                     /          \
                    v            v
           Colony (JobBoard)    MiningSystem (DesignationContainer markers)
                    |                    |
             Colonist AI                 |
                    |                    |
              DigJobDef (Action)         |
                    |                    |
              EventBus.dig_job_completed |
                    \                   /
                     v                 v
                 MiningSystem (Carve terrain & free marker)
```

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `dig_box_toggled(active: bool)` | `player.gd` | `DigBoxController`, `DigBoxHud` | Yes | Dig Box Designation toggle |
| `dig_box_dimensions_changed(w, h, d)` | `dig_box_controller.gd` | `DigBoxHud` | Yes | Live HUD dimension updates |
| `dig_box_mode_changed(mode_name)` | `dig_box_controller.gd` | `DigBoxHud` | Yes | Active orientation mode changed (Horizontal, Vertical, Stairway Down) |
| `dig_box_designated(voxels: Array)` | `dig_box_controller.gd` | `Colony`, `MiningSystem` | Yes | Designation commit, job dispatch, marker spawn |
| `dig_job_completed(cell: Vector3i)` | `dig_job_def.gd` | `MiningSystem` | Yes | Job completion, marker cleanup, voxel carving |
| `material_placed(pos: Vector3, material_id: String)` | `smooth_grid.gd` | (sound/particles hook) | No | Smooth placement, editor sculpt, structure stamp |
| `material_carved(pos: Vector3)` | `smooth_grid.gd` | (dig feedback hook) | No | Dig completion |

## Flow Trace: player real-time LMB mining

1. In **Normal mode**, player aims crosshair at terrain within reach (`interact_distance`) and clicks **LMB** (`InputComponent.primary_action_pressed`).
2. `Player._on_primary_action` raycasts to find the struck terrain voxel coordinate `pos: Vector3i`.
3. `SmoothGrid.apply_damage_at(pos, 50, player)` is called:
   - Queries `TerrainMaterialDef` at `pos` to determine max HP and `minutes_to_full_heal`.
   - Computes effective current HP considering time elapsed and damage regeneration.
   - Inflicts damage (50 HP per hit).
   - If HP drops $\le 0$: the cell is carved via `carve_box`, `material.yields` are deposited into the player inventory, `"mining"` skill use is recorded on `skill_set`, and `_hp_by_pos[pos]` is erased.
   - If HP remains $> 0$: `_hp_by_pos[pos]` records the new HP and timestamp.
4. Abandoned hits heal back to max HP over `minutes_to_full_heal` (default 0.25 min / 15s) and are purged from memory once full. Materials with `minutes_to_full_heal <= 0.0` (e.g. asphalt) retain damage permanently without regenerating.

## Flow Trace: Dig Box Designation & Colonist Dig Jobs

**Trigger:** Player presses `Shift+G` (`dig_box_toggle`).

1. `InputComponent` fires `dig_box_toggle_pressed` $\\rightarrow$ `Player` switches to `Mode.DIG_BOX_DESIGNATION` and emits `EventBus.dig_box_toggled(true)`.
2. `DigBoxHud` on `HUDLayer` becomes visible, showing initial dimensions ($W=1, H=3, D=3$) and the controls guide.
3. `DigBoxController._physics_process` casts a screen-center raycast to the terrain via `VoxelGridAdapter`. When terrain is struck, it derives 6-way orthogonal orientation from the player's camera view direction (Depth forward into view, Height screen-up $+Y$, Width screen-right) and positions the green `GhostPreview` box.
4. **Resizing:**
   - **Scroll Wheel**: Adjusts **Width** $\\pm 1$ using alternating Right/Left single-block expansion (odd widths centered, even widths +1 right).
   - **Shift + Scroll** (or horizontal scroll): Adjusts **Depth** $\\pm 1$.
   - **Ctrl + Scroll**: Adjusts **Height** $\\pm 1$.
   - All dimensions clamp between $1$ and $11$, emitting `EventBus.dig_box_dimensions_changed` to update the HUD live.
5. **Orientation Modes:** **Right-Click (`RMB`)** cycles through 3 orientation modes:
   - **Horizontal Mode**: Standard ground plane tunneling ($W \times H \times D$).
   - **Vertical Mode**: Vertical shaft digging down $-Y$ or up $+Y$.
   - **Stairway Down Mode**: Digs a downward-descending staircase corridor fixed at 2 blocks wide and 3 blocks high clearance, dropping 1 block down per 1 block forward along the player's dominant horizontal view direction. Scroll wheel adjusts the number of downward steps ($1..11$).
6. **LMB Designation:** **Left-Click (`LMB`)** gathers all voxel coordinates in the volume, filters them through `is_terrain_at` (requiring terrain height $\\ge Y + \\text{terrain\\_solidity\\_threshold}$), logs the coordinates to stdout and `GameLog`, and emits `EventBus.dig_box_designated`.
7. **Simulation Dispatch & Marker Placement:**
   - `MiningSystem` receives `dig_box_designated` and places persistent translucent amber `MeshInstance3D` unit cube markers on solid blocks under `DesignationContainer`.
   - `Colony` receives `dig_box_designated` and creates `Dig` jobs (`res://data/jobs/dig.tres`) on the `JobBoard`.
8. **Colonist Execution & Terrain Carving:**
   - Colonist AI picks up the dig job and navigates to an adjacent standable cell.
   - On completing the work timer, `DigJobDef` emits `EventBus.dig_job_completed(cell)`.
   - `MiningSystem` receives the completion event, frees the corresponding visual marker in `DesignationContainer`, and removes the voxel via `grid_adapter.remove_block_at(cell)` and `smooth_grid.carve_box(...)`.

## Visuals: how a material becomes visible

The renderer can't carry material identity (F8/F14), so looks are indirect and ride the identity system:

- **Natural terrain** — `SmoothGrid._apply_visuals` puts one `ShaderMaterial` (`assets/terrain/terrain_shader.gdshader`) on `VoxelTerrain.material_override` (F11). The shader blends the two **band endpoints**' triplanar textures by depth below the pristine surface: `_pick_band_materials` picks the surface material (smallest `min_depth`) and the dominant deep material (highest `spawn_weight` starting at/below the surface material's `max_depth`) — today `ground` $\\rightarrow$ `rock`, so the world reads dirt-over-stone exactly where the strata say it is. The depth basis is a 512² RF height bake written from `_pristine_height` (same F13 math as strata, no per-column cache).
- **Authored blobs** — every smooth add through `add_material` spawns one **Decal** per (block, material), a radial disc tinted the def's `color` (iron rust, gold yellow), reconstructed from the F12 sidecar as blocks load — so markers survive reloads with zero extra save state. The surface material skips marking (its blobs match the terrain's own top band).
- **Designation overlays** — `MiningSystem` spawns unshaded translucent amber (`Color(1.0, 0.65, 0.15, 0.35)`) `BoxMesh` unit markers on designated terrain cells, grouped under `DesignationContainer`.

## Class Reference

### Class: MiningSystem

**Extends:** `Node`  
**Script:** `subsystems/mining/mining_system.gd`  
**Description:** Map-level simulation manager for mining execution and designation markers. Listens to `EventBus.dig_box_designated` to instantiate amber markers and `EventBus.dig_job_completed` to clean up markers and carve voxels.  
**Used by:** `MapWiring`, `EventBus`  
**Lifecycle:** Mounted on map root dynamically by `MapWiring.wire_mining`.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `grid_adapter` | `VoxelGridAdapter` | Adapter for voxel removal and smooth terrain carving. |

**Functions:**

| Function | Description |
|---|---|
| `set_grid_adapter(adapter: VoxelGridAdapter) -> void` | Injects adapter and binds smooth terrain modification signals. |
| `clean_air_markers() -> void` | Sweeps active visual markers and frees any whose cell has become air. |
| `_on_dig_box_designated(cells: Array[Vector3i]) -> void` | Spawns visual markers for newly designated cells. |
| `_on_dig_job_completed(cell: Vector3i) -> void` | Frees marker and carves voxel terrain at cell. |

---

### Class: DigBoxController

**Extends:** `Node3D`  
**Script:** `subsystems/mining/dig_box_controller.gd`  
**Description:** Manages the Dig Box Designation tool: screen-center raycasting, 6-way camera-look orientation math, green preview ghost placement, dynamic mousewheel resizing, manual RMB orientation flipping, terrain solidity filtering, and emitting designation events.  
**Used by:** `MapWiring`, `Player`  
**Lifecycle:** Mounted on map root dynamically by `MapWiring.wire_mining`. Connects to `EventBus.dig_box_toggled`.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `grid_adapter` | `VoxelGridAdapter` | Adapter for raycast and block/smooth queries. |
| `exclude_bodies` | `Array[PhysicsBody3D]` | Raycast exclusion list (player capsule). |
| `camera_path` | `NodePath` | NodePath to player's Camera3D. |
| `width` | `int` | Current box width (1..11, default 1). |
| `height` | `int` | Current box height (1..11, default 3). |
| `depth` | `int` | Current box depth (1..11, default 3). |
| `is_vertical` | `bool` | True when in vertical shaft mode; false for horizontal ground mode. |
| `terrain_solidity_threshold` | `float` | Minimum cell height fraction (0.0..1.0, default 0.5) required to count as solid ground. |

**Functions:**

| Function | Description |
|---|---|
| `set_active(active: bool) -> void` | Enables or disables controller processing and ghost visibility. |
| `set_camera(camera: Camera3D) -> void` | Injects runtime player camera reference. |
| `add_exclude_body(body: PhysicsBody3D) -> void` | Appends body to raycast exclusion list. |
| `is_terrain_at(cell: Vector3i) -> bool` | Queries whether a voxel cell contains solid blocky or smooth terrain meeting the height threshold. |
| `filter_terrain_voxels(coords: Array[Vector3i]) -> Array[Vector3i]` | Filters an array of coordinates, returning only those containing solid terrain. |
| `get_dominant_cardinal(v: Vector3) -> Vector3i` | Snaps a 3D vector to the nearest of the 6 cardinal directions (±X, ±Y, ±Z). |
