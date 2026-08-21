# Mining

Digging the natural (smooth) terrain yields **position-dependent materials** — a dirt cap, a rock body, iron and gold veins — driven entirely by authored `TerrainMaterialDef` defs in `data/terrain/materials/`. The mining subsystem (`subsystems/mining/`) encompasses direct player digging via `BuildController` as well as large-scale **Dig Box Designation** (`DigBoxController`).

> **Design notes**
> - The mesher has no material API (F8/F11) and its per-voxel texturing system is verified non-functional (F14) — so visuals are **indirect**: a terrain shader bands the two band endpoints' triplanar textures by depth (F11 shader rules), and authored blobs each get a Decal marker tinted `TerrainMaterialDef.color`. Material *identity* lives outside the renderer — a per-block voxel-metadata sidecar for authored blobs (F12) and deterministic depth rules for natural ground (F13). See `docs/VOXEL-TOOL-NOTES.md`.
> - **Dig Box Designation:** Allows players to designate multi-voxel excavation volumes with line-of-sight orientation, dynamic mousewheel resizing ($1..11$), and persistent per-block amber ghost markers placed exclusively on solid terrain.
> - Equipment gating (planned) matches on the material's **`id`** — no type enum. Identity-is-id is the project's def convention; `ItemDef.tags` is the escape hatch if id-listing ever gets tedious.
> - `hp` is one concept for two eras: today it scales dig duration (`work_time × hp / 100`); the future tool-damage model consumes the same pool per swing.

## Files

| File | Type | Responsibility |
|---|---|---|
| `subsystems/mining/dig_box_controller.gd` | Script | Dig box designation controller: 6-way camera-look orientation math, preview ghost, RMB flip, mousewheel resizing ($1..11$), terrain solidity filter, and designation marker spawning. |
| `subsystems/mining/dig_box.tscn` | Scene | Controller runtime scene and GhostPreview instance. Mounted dynamically by MapWiring. |
| `ui/dig_box_hud/dig_box_hud.tscn` / `.gd` | UI | HUD overlay displaying controls legend and live box dimensions ($W \times H \times D$). |
| `subsystems/voxel/smooth_grid.gd` | Script | Identity representation: F12 sidecar writes/reads, `get_material_at` / `get_material_def_at` resolution chain, `set_material_catalog` injection, `_pristine_height` (the F13 generator mirror). The dig edit primitives: `carve` (SPHERE) and `carve_box` (hard per-sample air writes, F15). Also the visuals: terrain shader + height bake on `material_override`, Decal markers for authored blobs. |
| `subsystems/voxel/terrain_strata.gd` | Script (RefCounted) | Deterministic natural-material selection: depth band + per-material coherent noise in a softmax with `spawn_weight`. No storage. |
| `assets/terrain/terrain_shader.gdshader` | Shader | The one terrain look (F11/F14): triplanar ground/rock textures blended by depth below the pristine surface. Placeholder textures from `tools/terrain_texture_generator.gd`. |
| `data/terrain/materials/*.tres` | Data | `TerrainMaterialDef` content: `ground` (dirt, band 0–3), `rock` (3+, weight 10, province-scale veins), `iron_ore` (12+), `gold_ore` (24+); `color` tints markers, band endpoints carry `texture`. |
| `data/actions/dig_action.gd` | Script | The timed dig interaction: resolve-before-carve, hp-scaled gauge, yields to the digger's inventory, mining skill use. Trigger-agnostic `begin()` — the equipped-tool LMB later reuses it. |
| `data/mining/dig_tool.tres` (`dig_tool_params.gd`) | Data | `DigToolParams`: `work_time`, `shape` (BOX today / SPHERE), `box_size` (authored 1×1×1), `snap_grid`, `carve_radius` (SPHERE only). Preloaded as `BuildLibrary.DIG_TOOL`. |
| `data/items/iron_ore.tres`, `data/items/gold_ore.tres` | Data | Ore drops (`ItemDef`). |
| `subsystems/build/build_controller.gd` | Script | Tool routing: the `BuildLibrary.DIG_ID` sentinel, dig ghost, `_try_dig()`. |
| `testing/zylann/voxel_metadata_spike.tscn`, `testing/zylann/voxel_texturing_spike.tscn` | Scenes (editor-run) | The F12/F13 and F14 probes. The texturing spike is the harness to re-run if a future addon bump should ever revive per-voxel texturing. |
| `test/suite_terrain_strata_test.gd`, `test/suite_mining_test.gd`, `test/suite_terrain_visuals_test.gd` | Tests | Bands, determinism, seed sensitivity, weight mix, vein coherence; per-position yields; band picks, tint fallbacks, marker math. |

## Identity model: what material is this position?

`SmoothGrid.get_material_at(pos)` resolves in strict order:

1. **Air** (`get_voxel_f > 0`) → `""`. Always checked first — carved cells keep stale sidecar entries (F12), and an air-checkless reader would resurrect material out of holes.
2. **Authored sidecar** → the F12 per-block Dictionary (anchored at the 16³ block origin, riding `terrain.sqlite` with the normal block saves). Every smooth add routes through `SmoothGrid.add_material(material_id)` — editor sculpts, `SmoothPlacementStrategy`, `StructureStamper` — so non-generated terrain always carries authored identity.
3. **Strata** → `TerrainStrata.material_id_at`: depth below the **pristine generated surface** (surface row = 0, stable under digging — F13's closed form mirrors the generator), filtered by `min_depth`/`max_depth` bands, scored `argmax(log(spawn_weight) + 4·noise)` over per-material coherent noise at wavelength `vein_size`. Deterministic: same position + seed answers the same material forever — which is why strata needs no storage and survives streaming, saves and reloads.
4. **Fallback** → `default_material` (maps without an injected catalog behave exactly pre-mining).

Two load-bearing invariants keep the sources from disagreeing: `_pristine_height` reads the *same saved `TerrainGenDef`* the generator consumes (editor regeneration moves both in lockstep), and `add_material` is the *only* smooth-add path (no rogue `do_sphere` adds — a painted mound sits above the pristine surface and matches no band anyway).

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `dig_box_toggled(active: bool)` | `player.gd` | `DigBoxController`, `DigBoxHud` | Yes | Dig Box Designation toggle |
| `dig_box_dimensions_changed(w, h, d)` | `dig_box_controller.gd` | `DigBoxHud` | Yes | Live HUD dimension updates |
| `dig_box_designated(voxels: Array)` | `dig_box_controller.gd` | Colony / JobBoard (future) | Yes | Designation commit |
| `material_placed(pos: Vector3, material_id: String)` | `smooth_grid.gd` | (sound/particles hook) | No | Smooth placement, editor sculpt, structure stamp |
| `material_carved(pos: Vector3)` | `smooth_grid.gd` | (dig feedback hook) | No | Dig completion |

## Flow Trace: player direct dig

1. **B** opens the build menu; the **Dig** entry (`BuildLibrary.DIG_ID` sentinel, not a `BuildableDef`) arms dig mode.
2. `_physics_process` raycasts; a smooth-surface hit shows the green ghost of the dig volume. Today's BOX tool: a 1×1×1 cube anchored on the **nearest solid sample** to the hit point (nudged ~1 cm into the surface, F15) — WYSIWYG: the dig clears exactly that sample, ~1 m³ per dig, and the cube tracks the crosshair one lattice step at a time. A SPHERE-tool dig shows the half-sunk sphere ghost instead.
3. **LMB** → `BuildController._try_dig()` → `DigAction.begin(actor, grid, center, BuildLibrary.DIG_TOOL)`.
4. The gauge duration is `work_time × hp(at the dig position) / 100 ÷ mining-skill multiplier`; the label reads **"Digging <display_name>"** from the def at the dig position (a BOX resolves the first solid sample in its span) — the in-game oracle for the whole chain.
5. On completion `_apply` resolves the def **before** carving (after the carve the position is air), carves the shape — BOX: `carve_box` hard-writes air (+2) to every sample in the ghost box (a 1×1×1 dig: the single anchored sample), deliberately not a blended `do_box` (F15: blends leave "pyramid" fringe spikes; hard per-sample writes are deterministic); SPHERE: `MODE_REMOVE do_sphere` — then grants the def's `yields` to the digger's pocket inventory and records a `mining` skill use.
6. A cancelled dig banks nothing (v1 semantics — no partial-HP state on smooth terrain).

## Flow Trace: Dig Box Designation

**Trigger:** Player presses `Shift+G` (`dig_box_toggle`).

1. `InputComponent` fires `dig_box_toggle_pressed` $\rightarrow$ `Player` switches to `Mode.DIG_BOX_DESIGNATION` and emits `EventBus.dig_box_toggled(true)`.
2. `DigBoxHud` on `HUDLayer` becomes visible, showing initial dimensions ($W=1, H=3, D=3$) and the controls guide.
3. `DigBoxController._physics_process` casts a screen-center raycast to the terrain via `VoxelGridAdapter`. When terrain is struck, it derives 6-way orthogonal orientation from the player's camera view direction (Depth forward into view, Height screen-up $+Y$, Width screen-right) and positions the green `GhostPreview` box.
4. **Resizing:**
   - **Scroll Wheel**: Adjusts **Width** $\pm 1$ using alternating Right/Left single-block expansion (odd widths centered, even widths +1 right).
   - **Shift + Scroll** (or horizontal scroll): Adjusts **Depth** $\pm 1$.
   - **Ctrl + Scroll**: Adjusts **Height** $\pm 1$.
   - All dimensions clamp between $1$ and $11$, emitting `EventBus.dig_box_dimensions_changed` to update the HUD live.
5. **Orientation Flip:** **Right-Click (`RMB`)** toggles between **Horizontal Mode** (ground plane tunneling) and **Vertical Mode** (vertical shaft digging down $-Y$ or up $+Y$).
6. **LMB Designation:** **Left-Click (`LMB`)** gathers all voxel coordinates in the volume, filters them through `is_terrain_at` (requiring terrain height $\ge Y + \text{terrain\_solidity\_threshold}$), logs the coordinates to stdout and `GameLog`, places persistent translucent amber `MeshInstance3D` unit cube markers on solid blocks under `DesignationContainer`, and emits `EventBus.dig_box_designated`.
7. **Exit:** Pressing `Esc` or `Shift+G` restores `Player.Mode.GAMEPLAY` and hides preview and HUD; amber markers remain visible in the world.

## Visuals: how a material becomes visible

The renderer can't carry material identity (F8/F14), so looks are indirect and ride the identity system:

- **Natural terrain** — `SmoothGrid._apply_visuals` puts one `ShaderMaterial` (`assets/terrain/terrain_shader.gdshader`) on `VoxelTerrain.material_override` (F11). The shader blends the two **band endpoints**' triplanar textures by depth below the pristine surface: `_pick_band_materials` picks the surface material (smallest `min_depth`) and the dominant deep material (highest `spawn_weight` starting at/below the surface material's `max_depth`) — today `ground` → `rock`, so the world reads dirt-over-stone exactly where the strata say it is. The depth basis is a 512² RF height bake written from `_pristine_height` (same F13 math as strata, no per-column cache).
- **Authored blobs** — every smooth add through `add_material` spawns one **Decal** per (block, material), a radial disc tinted the def's `color` (iron rust, gold yellow), reconstructed from the F12 sidecar as blocks load — so markers survive reloads with zero extra save state. The surface material skips marking (its blobs match the terrain's own top band).
- **Designation overlays** — `DigBoxController` spawns unshaded translucent amber (`Color(1.0, 0.65, 0.15, 0.35)`) `BoxMesh` unit markers on designated terrain cells, grouped under `DesignationContainer`.

## Class Reference

### Class: DigBoxController

**Extends:** `Node3D`  
**Script:** `subsystems/mining/dig_box_controller.gd`  
**Description:** Manages the Dig Box Designation tool: screen-center raycasting, 6-way camera-look orientation math, green preview ghost placement, dynamic mousewheel resizing, manual RMB orientation flipping, terrain solidity filtering, and persistent designation marker instantiation.  
**Used by:** `MapWiring`, `Player`  
**Lifecycle:** Mounted on map root dynamically or in map scene. Connects to `EventBus.dig_box_toggled`.

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
