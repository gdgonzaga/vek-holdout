# Subsystem: Voxel / World

The buildable blocky-voxel world. Wraps Zylann's `voxel_tool` plugin. All voxel coupling lives here — other subsystems (Build) interact via the `IBlockGrid` interface, never `voxel_tool` directly.

> **Voxel-tool gotchas & verified facts** (editor hit-detection, the 40-frame settle, library/stream behavior, Blender export) live in `docs/VOXEL-TOOL-NOTES.md`.

## Collision layers

The dual-voxel layer plan (locked decisions in `docs/TODO.md`): blocky structures and the future smooth natural terrain each own a layer, so physics queries can address one ground without the other. `VoxelGrid._ready` assigns its terrain layer 2 in code — the map templates don't carry it, so already-stamped POIs get it at runtime.

| Layer | Name | Who lives there |
|---|---|---|
| 1 | World | Furniture trimesh statics |
| 2 | TerrainBlocky | The blocky `VoxelTerrain` (this subsystem) |
| 3 | TerrainSmooth | Reserved for the smooth terrain (conversion Phase 2) |
| 4 | Player | Player capsule |
| 5 | Build | Furniture/blueprint `BuildBody` interaction boxes |
| 6 | Colonist | Colonist capsules |

Masks that follow from it: player + colonist bodies and the camera spring arm mask `1|2|4` (statics + both terrains — never Build boxes or other capsules); the build/deconstruct ray masks `1|2|16` (statics + blocky terrain + Build boxes — see `VoxelGrid.BUILD_RAY_MASK`); terrain bodies mask `8|32` (the bodies that stand on terrain). F7 (VOXEL-TOOL-NOTES): a terrain's layer and mask must move together — assigning only `collision_layer` silently stops body interaction while rays keep hitting.

## Files

| File | Type | Responsibility |
|---|---|---|
| `map.tscn` / `map.gd` | Scene/Script | The MapRoot — the current game world (`Map`, structural container only — no gameplay logic). Swapped by SceneManager on base↔POI transitions. Holds VoxelGrid + containers for player/colonists/enemies/furniture. Authored POIs have per-map scenes at `data/maps/<id>/map.tscn` (see [Maps](maps.md) subsystem); the pristine template lives at `subsystems/maps/map_template.tscn`. |
| `voxel_grid.gd` | Script | Implements `IBlockGrid` (in `build/`); wraps `voxel_tool` get/set + the Godot-physics raycast (see `docs/VOXEL-TOOL-NOTES.md`). Owns block get/set, per-cell HP, the damage surface, and the terrain's collision layer (2, TerrainBlocky — assigned in `_ready`). Does NOT own placement UX (that's Build). |
| `block_library.gd` | Script (Resource) | Owns the `VoxelBlockyLibrary` the mesher renders with; maps string block_id ↔ integer library index, and id → `BlockDef`. Enforces the index convention (0 = air, terrain = 1) and bakes the library from `data/blocks/`. |
| `../data/blocks/` | Data | One `.tres` per block type (wood, scrap, stone, metal, reinforced, terrain). See [Data Schemas](data-schemas.md). |

## Signals

| Signal | Emitted by | Listeners | Via EventBus? | Flows |
|---|---|---|---|---|
| `block_placed(pos: Vector3i, block_id: String)` | `voxel_grid.gd` | Build (ghost validation), colonists (pathfinding re-bake) | No (same scene) | Place Blueprint |
| `block_destroyed(pos: Vector3i)` | `voxel_grid.gd` | colonists (pathfinding), raids (breach detection) | No | Enemy Attack Block |

## Flow Trace: Player targets a block (raycast)

**Trigger:** Build mode active; player moves cursor.

1. BuildController fires Godot physics raycast from camera each frame.
2. On hit, computes voxel index via `floor(hit.position - hit.normal * 0.001)` (per gotcha).
3. Queries `VoxelGrid.get_block_at(pos)` to determine target validity (empty/full, owned).
4. Updates ghost preview position + validity tint.

**End state:** Ghost preview shows valid/invalid placement under cursor.

## Class Reference

### Class: Map

**Extends:** Node3D
**Script:** `map.gd`
**Description:** The MapRoot — the current game world, swapped by SceneManager on base↔POI transitions. A structural container only; holds no gameplay logic. The voxel world's behavior lives in `VoxelGrid` / `BlockLibrary`. The base scene (`map.tscn`) and each authored POI (per-map `data/maps/<id>/map.tscn` stamped from `maps/map_template.tscn`) use this root script.
**Used by:** SceneManager (swaps the whole node), subsystems that fetch their containers/grid via the accessors.
**Lifecycle:** `@onready` resolves its child refs at `_ready`.

**Properties:**

| Property | Type | Description |
|---|---|---|
| `voxel_grid` | `VoxelGrid` | `@onready` ref to the `VoxelGrid` child (the `IBlockGrid` owner). |
| `colonist_container` | `Node3D` | `@onready` ref; parent of active colonist instances. |
| `enemy_container` | `Node3D` | `@onready` ref; parent of active enemy instances. |
| `furniture_container` | `Node3D` | `@onready` ref; parent Node3D for free-standing furniture placed at runtime (Build subsystem). |

**Functions:**

| Function | Description |
|---|---|
| `get_grid() -> VoxelGrid` | Convenience proxy (most callers want the grid, not the world). |
| `get_terrain() -> VoxelTerrain` | Delegates to `voxel_grid.get_terrain()`. |
| `get_furniture_container() -> Node3D` | The furniture parent node. |
| `get_colonist_container() -> Node3D` | The colonist parent node (where persistent colonists reparent on map swaps). |

### Class: VoxelGrid

**Extends:** Node
**Script:** `voxel_grid.gd`
**Description:** Implements `IBlockGrid` (defined in `build/i_block_grid.gd`). The sole owner of voxel_tool access for build/placement queries. Block identity is a string `block_id` everywhere outside this class; internally the integer voxel-tool library index is stored and `BlockLibrary` does the id↔index translation. Tracks per-position HP (`_hp_by_pos`) so combat/raids can damage blocks below their `BlockDef.hp` before destroying them.
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
| `raycast_to_voxel(origin: Vector3, dir: Vector3, max_dist: float, exclude: Array = []) -> Dictionary` | Godot physics raycast → voxel index + face normal. Returns `{position, normal, hit}`. Masked to `BUILD_RAY_MASK` (World statics + this terrain + Build bodies). `exclude` is an `Array[RID]` to skip (player body). NOT `VoxelTool.raycast` (see gotcha). |
| `height_at(x: float, z: float, normal_out: Array = []) -> float` | Height of the highest terrain surface at column (x, z) — downward ray masked to the terrain's layer, so statics/bodies never answer. `NAN` on no ground; `normal_out` receives the surface normal on hit (slope gating). |
| `get_hp_at(pos: Vector3i) -> int` | Current HP of the block at pos, or 0 if air/terrain. |
| `has_block_at(pos: Vector3i) -> bool` | Whether a buildable block exists at pos (HP entry present). |
| `apply_damage(pos: Vector3i, amount: int) -> void` | Applies damage to a buildable block; destroys it (and emits `block_destroyed`) when HP hits 0. Terrain is ignored (no HP entry). |
| `get_library() -> BlockLibrary` | The block library (id↔index + def lookup). |
| `get_terrain() -> VoxelTerrain` / `get_voxel_tool() -> VoxelTool` | Accessors for consumers that need the raw handles. |

### Class: BlockLibrary

**Extends:** Resource
**Script:** `block_library.gd`
**Description:** Registry of block types. Owns the `VoxelBlockyLibrary` the mesher renders with, maps string `block_id` ↔ integer library index, and resolves id → `BlockDef`. Assembled from `data/blocks/` in `_init()`.
**Used by:** `VoxelGrid` (mesher wiring, id↔index translation, def lookup for HP).
**Index convention:** `0` = air (`VoxelBlockyModelEmpty`); **terrain is forced to index 1** so `VoxelGeneratorFlat` (which emits `voxel_type = 1`) renders as terrain without remapping; the rest load alphabetically. Deterministic across runs.

**Functions:**

| Function | Description |
|---|---|
| `get_def(block_id) -> BlockDef` / `get_def_by_index(index) -> BlockDef` | Def lookup either way. |
| `get_index(block_id) -> int` | Library index; air (`""`) → 0, unknown → -1. |
| `get_id(index: int) -> String` | Inverse: index → block_id (0 → `""`). |
| `has_id(block_id) -> bool` / `get_all_defs() -> Array` | Membership + full def list. |
| `get_voxel_library() -> VoxelBlockyLibrary` | The baked mesher library. |
