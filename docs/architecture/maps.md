# Subsystem: Maps

The catalog, wiring, and per-map scenes for loadable maps. Hosts the `MapLibrary` autoload (the `id → MapDef` registry that `SceneManager` and `ExpeditionManager` read), `MapWiring` + `SpawnHelpers` (the runtime setup extracted from the proven build-test wiring), and `map_template.tscn` (the pristine template — each authored POI gets its own copy stamped to `data/maps/<id>/map.tscn` with a per-map `VoxelStreamSQLite` injected). This subsystem is the **map authoring + loading backbone**; see `docs/HOWTO-create-a-map.md` for the end-to-end authoring workflow.

**Authoring vs. runtime split (the core invariant):**
- Authored maps live under `res://data/maps/<id>/` as `map.tscn` (per-map scene with furniture markers) + `map.sqlite` (terrain DB) + `map_def.tres` (catalog entry). **These are never written at runtime** — `res://` is read-only at export.
- The pristine `map_template.tscn` ships with **no stream baked in** and no furniture markers. The Voxel Paint plugin stamps a copy per map, injecting a `VoxelStreamSQLite` pointing at that map's `map.sqlite`. `SceneManager` additionally copies the sqlite to `user://` at runtime (copy-on-load) to preserve authored data from runtime mutations.
- Furniture isolation is automatic: each map's `.tscn` has its own `Furniture_*` markers under `SpawnPoints`. `SpawnHelpers.read_spawns()` scans the loaded scene's markers, so furniture placed in one map never bleeds into another.

## Files

| File | Type | Responsibility |
|---|---|---|
| `map_library.gd` | Autoload | Read-only `id → MapDef` catalog. `_ready` scans `data/maps/*/map_def.tres` (subdirectories only — loose top-level `.tres` are ignored). Exposes `get_def` / `has_def` / `get_all` / `get_maps_by_type`. Tolerates a missing `data/maps/` (silent-null DirAccess, like `build_library.gd`). Read-only after `_ready`. |
| `map_wiring.gd` (`MapWiring`) | Script (`RefCounted`, static) | Extracted wiring utilities: `wire_build(map)` (adapter→grid, `FurnitureLayer`→container, `BlueprintLayer`→container/grid/furniture, `BlueprintPlacementStrategy`→blueprint_layer) + `wire_player(map, player)` (reparent persistent Player, wire camera/exclude into BuildController, reuse the player's `VoxelViewer` so repeated swaps don't stack viewers). The single source of truth for post-instantiate setup. |
| `spawn_helpers.gd` (`SpawnHelpers`) | Script (`RefCounted`, static) | `read_spawns(map)` reads the `SpawnPoints` container: `PlayerSpawn` → player spawn, `EnemySpawn_*` → enemy spawns, `Furniture_*` markers → authored furniture records (`def_id`/`anchor`/`yaw`) replayed by SceneManager. Also `clear_furniture_markers(map)` frees the `Furniture_*` markers after replay. Scene markers override `MapDef` fallback values (non-zero wins). |
| `map_template.tscn` | Scene | Pristine template — root `Map` with VoxelGrid/VoxelTerrain (no stream — injected per-map), the standard containers, a BuildController, and `SpawnPoints/PlayerSpawn`. Never edited directly; the Voxel Paint plugin stamps a copy into each `data/maps/<id>/map.tscn` on map creation. |
| `../data/maps/<id>/map.tscn` | Scene | Per-map authored scene — stamped from the template with a `VoxelStreamSQLite` pointing at `data/maps/<id>/map.sqlite`. Furniture `Furniture_*` markers accumulate under `SpawnPoints` as you author. This is the file `MapDef.scene_path` points at; `SceneManager.swap_map()` loads this. |
| `../voxel/map.tscn` | Scene | A `Map`-rooted scene with `VoxelGeneratorFlat` (no authored terrain DB). **Not referenced by any `MapDef`** — the base map actually loads `data/maps/base/map.tscn` (which has a `VoxelStreamSQLite`). Kept as a minimal/standalone scene; not the runtime base. |
| `../data/maps/map_def.gd` | Data (script) | `MapDef` Resource class. See [Data Schemas](data-schemas.md). |
| `../data/maps/<id>/map_def.tres` | Data | One `MapDef` per map. `id` **must equal the folder name** — `SceneManager` derives the runtime sqlite path from it. |
| `../data/maps/<id>/map.sqlite` | Data | The authored terrain database (Zylann `VoxelStreamSQLite`). Created by the Voxel Paint "+ New Map" button. |

## Signals

Maps has no signals of its own — it's read by `SceneManager` (load) and `ExpeditionManager` (POI discovery) and reacts to `EventBus.map_loaded` (the world map UI repopulates on it). The map swap lifecycle signals live on EventBus (`map_loading` / `map_loaded` / `map_unloading`, emitted by SceneManager).

## Flow Trace: New Game discovers POIs

**Trigger:** Main Menu → **New Game** (`main_menu._start_new_game`), during new-run setup (after `SaveSystem.create_save`, around `swap_map("base")`).

1. `main_menu._start_new_game` iterates `MapLibrary.get_maps_by_type(MapDef.MapType.POI)`.
2. For each, calls `ExpeditionManager.discover(def.id)` (appends to the discovered list, idempotent).
3. Every POI-type map is therefore visible in the world map from the start of a run. (Per-map unlock gating via `unlock_condition` is deferred.)

**End state:** All POI defs are discoverable for the new run; opening the world map (M) lists them. (On Load, discovery is restored from the save — no re-discovery.)

## Class Reference

### Class: MapLibrary

**Extends:** Node (autoload)
**Script:** `map_library.gd`
**Description:** Read-only registry of all loadable maps. Scans `data/maps/*/map_def.tres` at startup into an `id → MapDef` map.
**Used by:** `SceneManager.swap_map` (def lookup), `ExpeditionManager` (POI lookup via `get_def`/`has_def`), `main_menu._start_new_game` (the POI discovery loop — `get_maps_by_type(POI)`), world map UI (via `ExpeditionManager.get_available_pois`).
**Lifecycle:** `_ready` scans; if `data/maps/` doesn't exist yet it returns early (no error). Read-only after.

**Functions:**

| Function | Description |
|---|---|
| `get_def(id: String) -> MapDef` | The def for `id`, or `null`. |
| `has_def(id: String) -> bool` | Catalog membership. |
| `get_all() -> Array` | All defs. |
| `get_maps_by_type(type: int) -> Array` | Defs filtered by `MapType` (e.g. all POIs). |

### Class: MapWiring

**Extends:** RefCounted (static class)
**Script:** `map_wiring.gd`
**Description:** The single source of truth for wiring a freshly-instantiated `Map`. Extracted from `testing/build/build_test.gd` so `SceneManager` reuses one path instead of duplicating adapter/strategy/FurnitureLayer/camera plumbing per swap.
**Used by:** `SceneManager._wire_map`.

**Static functions:**

| Function | Description |
|---|---|
| `wire_build(map: Map) -> FurnitureLayer` | Wires BuildController deps: adapter→grid, `FurnitureLayer`→container, `BlueprintLayer`→container/grid/furniture, `BlueprintPlacementStrategy`→blueprint_layer. Returns the FurnitureLayer or `null` if no BuildController. |
| `wire_player(map: Map, player: Player) -> void` | Attaches the player, wires its camera into BuildController, adds the player's exclude body. Reuses an existing `VoxelViewer` child (creates one on first swap) so repeated swaps don't stack viewers. |

### Class: SpawnHelpers

**Extends:** RefCounted (static class)
**Script:** `spawn_helpers.gd`
**Description:** Reads authored spawn positions and furniture records from a `Map`'s `SpawnPoints` container. Scene markers override `MapDef` values when present (non-zero) — an authored POI scene can place `PlayerSpawn` / `EnemySpawn_*` Marker3Ds to control exactly where actors enter, and `Furniture_*` markers to author furniture placement.
**Used by:** `SceneManager._wire_map` (player spawn resolution + authored-furniture replay + marker cleanup).

**Static functions:**

| Function | Description |
|---|---|
| `read_spawns(map: Map) -> Dictionary` | `{ "player": Vector3, "enemies": Array[Vector3], "furniture": Array[{def_id, anchor, yaw}] }` from the `SpawnPoints` node's children. Zeros/empty if absent. |
| `clear_furniture_markers(map: Map) -> void` | Frees the `Furniture_*` markers after their records have been replayed into the live `FurnitureLayer` (each also carries an editor `PreviewMesh` child that would otherwise duplicate the spawned mesh). No-op if the map has no `SpawnPoints`. |
