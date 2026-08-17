# Subsystem: Voxel / World

The voxel world: blocky structures + smooth natural terrain (the dual-voxel conversion, `docs/TODO.md`). Wraps Zylann's `voxel_tool` plugin. All voxel coupling lives here — other subsystems (Build) interact via the `IBlockGrid` interface, never `voxel_tool` directly.

> **Voxel-tool gotchas & verified facts** (editor hit-detection, the 40-frame settle, library/stream behavior, the smooth-edit spike F8) live in `docs/VOXEL-TOOL-NOTES.md`.

## Collision layers

The dual-voxel layer plan (locked decisions in `docs/TODO.md`): blocky structures and smooth natural terrain each own a layer, so physics queries can address one ground without the other. Both grids assign their terrain's layer + mask in `_ready` code — map templates don't carry them, so already-stamped POIs get them at runtime.

| Layer | Name | Who lives there |
|---|---|---|
| 1 | World | Furniture trimesh statics |
| 2 | TerrainBlocky | The blocky `VoxelTerrain` (`BlockyGrid`) |
| 3 | TerrainSmooth | The smooth `VoxelTerrain` (`SmoothGrid`) |
| 4 | Player | Player capsule |
| 5 | Build | Furniture/blueprint `BuildBody` interaction boxes |
| 6 | Colonist | Colonist capsules |

Masks that follow from it: player + colonist bodies and the camera spring arm mask `1|2|4` (statics + both terrains — never Build boxes or other capsules); the build/deconstruct ray masks `1|2|4|16` (statics + both terrains + Build boxes — see `BlockyGrid.BUILD_RAY_MASK`); terrain bodies mask `8|32` (the bodies that stand on terrain). F7 (VOXEL-TOOL-NOTES): a terrain's layer and mask must move together — assigning only `collision_layer` silently stops body interaction while rays keep hitting.

## Files

| File | Type | Responsibility |
|---|---|---|
| `map.tscn` / `map.gd` | Scene/Script | The MapRoot — the current game world (`Map`, structural container only — no gameplay logic). Swapped by SceneManager on base↔POI transitions. Holds BlockyGrid + optional SmoothGrid + containers for player/colonists/enemies/furniture. Authored POIs have per-map scenes at `data/maps/<id>/map.tscn` (see [Maps](maps.md) subsystem); the pristine template lives at `subsystems/maps/map_template.tscn`. |
| `blocky_grid.gd` | Script | The structures half. Implements `IBlockGrid` (in `build/`); wraps `voxel_tool` get/set + the surface-tagged Godot-physics raycast (see `docs/VOXEL-TOOL-NOTES.md`). Owns block get/set, per-cell HP, the damage surface, and the blocky terrain's collision layer (2). Does NOT own placement UX (that's Build). |
| `smooth_grid.gd` | Script | The natural-terrain half — BlockyGrid's mirror, different mesher/generator. `carve`/`add_material` sphere primitives (F8 semantics), cached `height_at` with D4 invalidation, `raycast_to_surface` masked to TerrainSmooth. Opt-in: a `MapDef` without `terrain_gen` makes the node free itself at `_ready` (SceneManager injects the def pre-tree). |
| `block_library.gd` | Script (Resource) | Owns the `VoxelBlockyLibrary` the blocky mesher renders with; maps string block_id ↔ integer library index, and id → `BlockDef`. Enforces the index convention (0 = air, terrain = 1) and bakes the library from `data/blocks/`. |
| `../data/blocks/` | Data | One `.tres` per block type (wood, scrap, stone, metal, reinforced, terrain). See [Data Schemas](data-schemas.md). |
| `../data/terrain/` | Data | `TerrainGenDef` (generator params + walk slope gate) and `materials/TerrainMaterialDef` (identity + hardness + dig `yields` — no visual refs, see F8). `data/mining/dig_tool.tres` carries the dig action's stats. See [Data Schemas](data-schemas.md). |

**Walkability seam (D4):** `MapWiring.hybrid_ground_probe` composes the smooth grid's `height_at` with the blocky probe — a cell is standable when the smooth surface passes through it on a walkable slope (`TerrainGenDef.max_walk_slope_deg`, ≤ 45° so the ±1 step model holds), or when the plain blocky rules hold anywhere the smooth terrain doesn't reach. It also **cancels blocky cells buried inside hills** (a plate-top column reads air-above-solid to the blocky grid, but a colonist routed there would grind into the hillside) — the one deviation from "smooth only adds cells", and it applies only to buried cells. `MapWiring.smooth_stand_hint` derives column stand cells (`floor(h)`) for the pathfinder's resolvers. See [Maps](maps.md) `wire_colonists` and [Colonists](colonists.md) VoxelPathfinder.

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `block_placed(pos: Vector3i, block_id: String)` | `blocky_grid.gd` | Build (ghost validation), colonists (pathfinding re-bake) | No (same scene) | Place Blueprint |
| `block_destroyed(pos: Vector3i)` | `blocky_grid.gd` | colonists (pathfinding), raids (breach detection) | No | Enemy Attack Block |
| `material_placed(pos: Vector3, material_id: String)` | `smooth_grid.gd` | (none yet — `SmoothPlacementStrategy` calls `add_material` directly; the signal is the future sound/particles hook) | No | — |
| `material_carved(pos: Vector3)` | `smooth_grid.gd` | (none yet — DigAction calls `carve` directly; the signal is the future sound/particles hook) | No | — |

## Flow Trace: Player targets ground (raycast)

**Trigger:** Build mode active; player moves cursor.

1. BuildController fires the Godot physics raycast from camera each frame (`BlockyGrid.raycast_to_voxel`, masked `1|2|4|16`).
2. The collider's collision layer tags the hit (`surface`: `"blocky"` / `"smooth"` / `"body"`). Blocky/body hits compute the struck cell via `floor(hit.position - hit.normal * 0.001)`; a smooth hit returns the **pre-derived placement cell** `floor(hit.position + normal * 0.5)` with a zero normal (slope normals aren't axis-aligned — F7) plus float `smooth_point`/`smooth_normal`.
3. BuildController derives the placement cell through `_placement_cell` (smooth = as-is; blocky/body = struck + face normal).
4. Ghost preview position + validity tint update.

**End state:** Ghost preview shows valid/invalid placement under cursor — on plate, blocks, or hillside alike.

## Class Reference

### Class: Map

**Extends:** Node3D
**Script:** `map.gd`
**Description:** The MapRoot — the current game world, swapped by SceneManager on base↔POI transitions. A structural container only; holds no gameplay logic. The voxel world's behavior lives in `BlockyGrid` / `SmoothGrid` / `BlockLibrary`. The base scene (`map.tscn`) and each authored POI (per-map `data/maps/<id>/map.tscn` stamped from `maps/map_template.tscn`) use this root script.
**Used by:** SceneManager (swaps the whole node), subsystems that fetch their containers/grids via the accessors.
**Lifecycle:** `@onready` resolves its child refs at `_ready`.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `blocky_grid` | `BlockyGrid` | `@onready` ref to the `BlockyGrid` child (the `IBlockGrid` owner). |
| `smooth_grid` | `SmoothGrid` | `@onready` ref via `get_node_or_null` — **null on maps without natural terrain** (node absent, or freed itself for lack of `terrain_gen`). |
| `colonist_container` | `Node3D` | `@onready` ref; parent of active colonist instances. |
| `enemy_container` | `Node3D` | `@onready` ref; parent of active enemy instances. |
| `furniture_container` | `Node3D` | `@onready` ref; parent Node3D for free-standing furniture placed at runtime (Build subsystem). |

**Functions:**

| Function | Description |
|---|---|
| `get_blocky_grid() -> BlockyGrid` | Convenience proxy (most callers want the grid, not the world). |
| `get_smooth_grid() -> SmoothGrid` | The natural-terrain grid, or null — callers null-check; terrain-less maps are the default. |
| `get_blocky_terrain() -> VoxelTerrain` | Delegates to `blocky_grid.get_terrain()`. |
| `get_smooth_terrain() -> VoxelTerrain` | The smooth `VoxelTerrain`, or null when the map has none (node absent, or a SmoothGrid that freed itself on null `terrain_gen`). |
| `persisted_streams()` / `stream_dbs()` / `flush_voxel_streams()` | The two-stream persistence pairing (Phase 4): `{terrain, db}` pairs — blocky `map.sqlite` always, smooth `terrain.sqlite` when present. One source shared by SceneManager's copy-on-load redirect and SaveSystem's park flush / slot snapshot-restore, so the sites can't drift. `flush_voxel_streams` saves modified blocks on both grids (INV-3's voxel half). |
| `ground_height_at(x: float, z: float) -> float` | Combined spawn query (D4/Phase 3): one downward ray masked `TerrainBlocky\|TerrainSmooth` — the first hit from above is the highest surface (hill or plate), so player/colonist spawn markers snap onto real ground regardless of authored Y. Furniture statics and bodies never answer. `NAN` when neither terrain reaches the column. Per-grid `height_at` stays layer-specific — this is a placement query, not the walkability source. |
| `get_furniture_container() -> Node3D` | The furniture parent node. |
| `get_colonist_container() -> Node3D` | The colonist parent node (where persistent colonists reparent on map swaps). |

### Class: BlockyGrid

**Extends:** Node
**Script:** `blocky_grid.gd` (renamed from `voxel_grid.gd` in the dual-voxel conversion)
**Description:** Implements `IBlockGrid` (defined in `build/i_block_grid.gd`). The sole owner of voxel_tool access for structures. Block identity is a string `block_id` everywhere outside this class; internally the integer voxel-tool library index is stored and `BlockLibrary` does the id↔index translation. Tracks per-position HP (`_hp_by_pos`) so combat/raids can damage blocks below their `BlockDef.hp` before destroying them.
**Used by:** Build (placement + raycast), Colonists (A* pathfinding), Raids (breach + damage), Combat (`apply_damage`).
**Lifecycle:** `_ready()` assigns the terrain its collision layer + body mask (F7: they move together), constructs the `BlockLibrary`, wires its `VoxelBlockyLibrary` into the terrain mesher, and fetches the `VoxelTool` reference from the `VoxelTerrain` child.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `terrain_path` | `NodePath` | `[export]` Path to the `VoxelTerrain` child; default `^"VoxelTerrain"`. |
| `_terrain` | `VoxelTerrain` | `@onready` ref; owns the physics world its collision bodies live in. |
| `_voxel_tool` | `VoxelTool` | Fetched in `_ready`; `mode = MODE_SET`. |
| `_library` | `BlockLibrary` | Constructed in `_ready`. |
| `_hp_by_pos` | `Dictionary` | `Vector3i -> int` (current HP; absent = air). |

**Constants:** `TERRAIN_LAYER = 2`, `TERRAIN_BODY_MASK = 8|32`, `SMOOTH_TERRAIN_LAYER_VALUE = 4`, `BUILD_RAY_MASK = 1|2|4|16`.

**Signals:**

| Signal | Description |
|---|---|
| `block_placed(pos: Vector3i, block_id: String)` | A block was placed. Listeners: Build (ghost), colonists (re-bake), Functional Rooms (when wired). |
| `block_destroyed(pos: Vector3i)` | A block's HP hit 0 or was removed. Listeners: colonists (re-bake), raids (breach), Functional Rooms (when wired). |

**Functions:**

| Function | Description |
|---|---|
| `get_block_at(pos: Vector3i) -> String` | Returns block ID at position; empty string if air. |
| `set_block_at(pos: Vector3i, block_id: String) -> void` | Places a block; seeds `_hp_by_pos[pos] = def.hp`; emits `block_placed`. |
| `remove_block_at(pos: Vector3i) -> void` | Removes a block; clears its HP entry; emits `block_destroyed`. |
| `raycast_to_voxel(origin, dir, max_dist, exclude: Array = []) -> Dictionary` | Godot physics raycast masked to `BUILD_RAY_MASK`. Returns `{position, normal, hit, surface}` — see the flow trace for the per-surface contract; smooth hits carry `smooth_point`/`smooth_normal` floats. `exclude` is an `Array[RID]` to skip (player body). NOT `VoxelTool.raycast` (see gotcha). |
| `height_at(x: float, z: float, normal_out: Array = []) -> float` | Height of the highest **blocky** surface at column (x, z) — downward ray masked to layer 2, so statics/bodies/smooth never answer. `NAN` on no ground; `normal_out` receives the surface normal on hit (slope gating). |
| `get_hp_at(pos: Vector3i) -> int` | Current HP of the block at pos, or 0 if air/terrain. |
| `has_block_at(pos: Vector3i) -> bool` | Whether a buildable block exists at pos (HP entry present). |
| `apply_damage(pos: Vector3i, amount: int) -> void` | Applies damage to a buildable block; destroys it (and emits `block_destroyed`) when HP hits 0. Terrain is ignored (no HP entry). |
| `get_library() -> BlockLibrary` | The block library (id↔index + def lookup). |
| `get_terrain() -> VoxelTerrain` / `get_voxel_tool() -> VoxelTool` | Accessors for consumers that need the raw handles. |
| `serialize() -> Dictionary` / `deserialize(data)` | SaveSystem contract — buildable-block HP only; block types persist via the sqlite stream. |

### Class: SmoothGrid

**Extends:** Node
**Script:** `smooth_grid.gd`
**Description:** The natural-terrain half of the dual-voxel world — BlockyGrid's mirror (same vocabulary, different mesher/generator; D1 in `docs/TODO.md`). Owns a `VoxelTerrain` + `VoxelMesherTransvoxel` + `VoxelGeneratorNoise2D` built from the injected `TerrainGenDef`, the sphere-edit primitives (`carve` is the mining dig action's edit, called by `DigAction` on completion; `add_material` for smooth placement), and the cached heightfield walkability composes with the blocky probe (see the Walkability seam note above). Edit semantics follow F8 (VOXEL-TOOL-NOTES): channel 0 is float SDF (solid ≤ 0); `MODE_SET value v` writes SDF `−v`, so **value 0 is still solid** — carving is `MODE_REMOVE`, never `MODE_SET 0`. No HP in v1: mining carves on action completion.
**Used by:** SceneManager (injects `terrain_gen`), MapWiring (`hybrid_ground_probe` + `smooth_stand_hint` via `height_at`; `is_ground_supported` in Build), Phase-5 mining/smooth-placement.
**Lifecycle:** Opt-in by data. SceneManager injects `MapDef.terrain_gen` before the map enters the tree; `_ready()` with a null def `queue_free()`s the node ("no smooth grid at all" — terrain-less maps play exactly as before). With a def: assigns layer 3 + body mask, builds generator + Transvoxel mesher, fetches the VoxelTool, and hooks `block_loaded`/`block_unloaded` for cache invalidation.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `terrain_path` | `NodePath` | `[export]` Path to the `VoxelTerrain` child; default `^"VoxelTerrain"`. |
| `terrain_gen` | `TerrainGenDef` | `[export]` Generator params; injected pre-tree by SceneManager. |
| `default_material` | `TerrainMaterialDef` | `[export]` The identity `get_material_at` reports for solid ground (no per-voxel identity exists — F8). |
| `_height_cache` | `Dictionary` | `Vector2i -> {h, n}` — the D4 heightfield; evicted by edits and block streaming. |

**Constants:** `TERRAIN_LAYER = 3` (`TERRAIN_LAYER_VALUE = 4`), `TERRAIN_BODY_MASK = 8|32`, `SOLID_DENSITY = 2`.

**Signals:**

| Signal | Description |
|---|---|
| `material_placed(pos: Vector3, material_id: String)` | add_material ran; Phase-5 yields hook. |
| `material_carved(pos: Vector3)` | carve ran; Phase-5 dig completion hook. |

**Functions:**

| Function | Description |
|---|---|
| `get_material_at(pos: Vector3i) -> String` | Material id at pos, `""` for air. Any solid position reports `default_material.id` — values are pure density, there is no identity channel (F8). |
| `add_material(pos: Vector3, material_id: String, radius: float) -> void` | Adds a sphere of solid ground (SDF `−SOLID_DENSITY`); evicts cached columns; emits `material_placed`. |
| `carve(pos: Vector3, radius: float) -> void` | Carves a sphere (`MODE_REMOVE`); evicts cached columns; emits `material_carved`. |
| `raycast_to_surface(origin, dir, max_dist, exclude: Array = []) -> Dictionary` | Ray masked to TerrainSmooth; returns **float** `{position, normal, hit}` — smooth normals are non-axis-aligned (F7), consumers derive their own cells. |
| `height_at(x: float, z: float, normal_out: Array = []) -> float` | Cached height of the natural surface at column (x, z); `NAN` where smooth terrain doesn't reach. `normal_out` receives the surface normal (Phase-3 slope gate). |
| `get_terrain() -> VoxelTerrain` / `get_voxel_tool() -> VoxelTool` | Accessors for consumers that need the raw handles. |
| `serialize() -> Dictionary` / `deserialize(data)` | v1 no-op — the smooth terrain's whole state lives in its sqlite stream (saved blocks override the generator, F8). Kept so SaveSystem can treat both grids uniformly. |

### Class: BlockLibrary

**Extends:** Resource
**Script:** `block_library.gd`
**Description:** Registry of block types. Owns the `VoxelBlockyLibrary` the mesher renders with, maps string `block_id` ↔ integer library index, and resolves id → `BlockDef`. Assembled from `data/blocks/` in `_init()`.
**Used by:** `BlockyGrid` (mesher wiring, id↔index translation, def lookup for HP).
**Index convention:** `0` = air (`VoxelBlockyModelEmpty`); **terrain is forced to index 1** so `VoxelGeneratorFlat` (which emits `voxel_type = 1`) renders as terrain without remapping; the rest load alphabetically. Deterministic across runs.

**Functions:**

| Function | Description |
|---|---|
| `get_def(block_id) -> BlockDef` / `get_def_by_index(index) -> BlockDef` | Def lookup either way. |
| `get_index(block_id) -> int` | Library index; air (`""`) → 0, unknown → -1. |
| `get_id(index: int) -> String` | Inverse: index → block_id (0 → `""`). |
| `has_id(block_id) -> bool` / `get_all_defs() -> Array` | Membership + full def list. |
| `get_voxel_library() -> VoxelBlockyLibrary` | The baked mesher library. |
