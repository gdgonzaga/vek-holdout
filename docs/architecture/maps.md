# Subsystem: Maps

The catalog, wiring, and per-map scenes for loadable maps. Hosts the `MapLibrary` autoload (the `id → MapDef` registry that `SceneManager` and `ExpeditionManager` read), `MapWiring` + `SpawnHelpers` (the runtime setup extracted from the proven build-test wiring), and `map_template.tscn` (the pristine template — each authored POI gets its own copy stamped to `data/maps/<id>/map.tscn` with per-map `VoxelStreamSQLite` resources injected — `map.sqlite` for the blocky terrain, `terrain.sqlite` for the optional smooth terrain). This subsystem is the **map authoring + loading backbone**; see `docs/HOWTO-create-a-map.md` for the end-to-end authoring workflow.

**Authoring vs. runtime split (the core invariant):**
- Authored maps live under `res://data/maps/<id>/` as `map.tscn` (per-map scene with furniture markers) + `map.sqlite` (terrain DB) + `map_def.tres` (catalog entry). **These are never written at runtime** — `res://` is read-only at export.
- The pristine `map_template.tscn` ships with **no streams baked in** and no furniture markers. The Voxel Paint plugin stamps a copy per map, injecting `VoxelStreamSQLite` resources for `map.sqlite` (blocky) and `terrain.sqlite` (smooth — harmless on maps whose `terrain_gen` is null, since the SmoothGrid then frees itself). `SceneManager` redirects **both** streams to `user://` copies at runtime (copy-on-load) so runtime mutations never touch authored data; SaveSystem's park/save/load persists both (see [Save / Load](save.md)). The paint tool binds the **blocky** terrain only — identified by its owning `BlockyGrid`, never by node name (two `VoxelTerrain` nodes share one name since the dual-voxel template).
- Furniture isolation is automatic: each map's `.tscn` has its own `Furniture_*` markers under `SpawnPoints`. `SpawnHelpers.read_spawns()` scans the loaded scene's markers, so furniture placed in one map never bleeds into another.

## Files

| File | Type | Responsibility |
|---|---|---|
| `map_library.gd` | Autoload | Read-only `id → MapDef` catalog. `_ready` scans `data/maps/*/map_def.tres` (subdirectories only — loose top-level `.tres` are ignored). Exposes `get_def` / `has_def` / `get_all` / `get_maps_by_type`. Tolerates a missing `data/maps/` (silent-null DirAccess, like `build_library.gd`). Read-only after `_ready`. |
| `map_wiring.gd` (`MapWiring`) | Script (`RefCounted`, static) | Extracted wiring utilities: `wire_build(map)` (adapter→grid + smooth grid, `FurnitureLayer`→container, `BlueprintLayer`→container/grid/furniture, `BlueprintPlacementStrategy`→blueprint_layer) + `wire_player(map, player)` (reparent persistent Player, wire camera/exclude into BuildController, reuse the player's `VoxelViewer` so repeated swaps don't stack viewers) + `wire_colonists(map)` (hand the `ColonistContainer` + `ColonistSpawn` positions to `Colony.on_map_wired`, then pass the walkability predicate, stand-cell hint, and ground query to Colony). Also the walkability ground probes (`blocky_ground_probe` / `hybrid_ground_probe`, D4) and `smooth_stand_hint`. The single source of truth for post-instantiate setup. |
| `spawn_helpers.gd` (`SpawnHelpers`) | Script (`RefCounted`, static) | `read_spawns(map)` reads the `SpawnPoints` container: `PlayerSpawn` → player spawn, `EnemySpawn_*` → enemy spawns, `Furniture_*` markers → authored furniture records (`def_id`/`anchor`/`yaw`) replayed by SceneManager. Also `clear_furniture_markers(map)` frees the `Furniture_*` markers after replay. Scene markers override `MapDef` fallback values (non-zero wins). |
| `map_template.tscn` | Scene | Pristine template — root `Map` with BlockyGrid/VoxelTerrain (blocky mesher + baked library, **no generator** — the blocky layer is structures-only; no stream — injected per-map), SmoothGrid/VoxelTerrain (Transvoxel mesher; generator from `MapDef.terrain_gen` at runtime — new maps default to the 50 m deep `data/terrain/default_ground.tres`, frees itself when null), the standard containers, a BuildController, and `SpawnPoints/PlayerSpawn`. Never edited directly; the Voxel Paint plugin stamps a copy into each `data/maps/<id>/map.tscn` on map creation. |
| `../data/maps/<id>/map.tscn` | Scene | Per-map authored scene — stamped from the template with `VoxelStreamSQLite` resources for `map.sqlite` (blocky) and `terrain.sqlite` (smooth). Furniture `Furniture_*` markers accumulate under `SpawnPoints` as you author. This is the file `MapDef.scene_path` points at; `SceneManager.swap_map()` loads this. |
| `../voxel/map.tscn` | Scene | A `Map`-rooted scene with `VoxelGeneratorFlat` (no authored terrain DB). **Not referenced by any `MapDef`** — the base map actually loads `data/maps/base/map.tscn` (which has a `VoxelStreamSQLite`). Kept as a minimal/standalone scene; not the runtime base. |
| `../data/maps/map_def.gd` | Data (script) | `MapDef` Resource class. See [Data Schemas](data-schemas.md). |
| `../data/maps/<id>/map_def.tres` | Data | One `MapDef` per map. `id` **must equal the folder name** — `SceneManager` derives the runtime sqlite path from it. |
| `../data/maps/<id>/map.sqlite` | Data | The authored blocky terrain database (Zylann `VoxelStreamSQLite`). Created by the Voxel Paint "+ New Map" button. |
| `../data/maps/<id>/terrain.sqlite` | Data | The authored smooth-terrain database, stamped by the plugin but often absent — generator-only maps (like `dev`) ship no baseline db; the runtime copy appears on first save. |

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
| `wire_build(map: Map) -> FurnitureLayer` | Wires BuildController deps: adapter→grid (+ the live `SmoothGrid` for ground-support queries), `FurnitureLayer`→container, `BlueprintLayer`→container/grid/furniture, `BlueprintPlacementStrategy`→blueprint_layer. Returns the FurnitureLayer or `null` if no BuildController. |
| `wire_player(map: Map, player: Player) -> void` | Attaches the player, wires its camera into BuildController, adds the player's exclude body. Reuses an existing `VoxelViewer` child (creates one on first swap) so repeated swaps don't stack viewers. |
| `wire_colonists(map: Map) -> Node3D` | Hands the map's `ColonistContainer` + authored `ColonistSpawn` positions to `Colony.on_map_wired` (spawn on empty roster, reparent on non-empty — the base↔POI persist idiom), calls `Colony.storage_registry.on_map_wired(map.get_furniture_container())` (re-home the storage registry on the new map), then composes the walkability predicate (`_compose_walkability`: an injectable ground probe — `blocky_ground_probe` on smooth-less maps (air cell with solid floor below, head clearance above, the 1.6 m capsule spans two cells), `hybrid_ground_probe` where the smooth grid is live (adds slope-gated stand-on-surface cells and cancels blocky cells buried inside hills, D4) — ANDed with occupancy: neither the cell nor its overhead neighbour may hold non-steppable furniture or a blueprint; furniture <= 0.5 m mesh height is steppable). Passes the predicate to `Colony.set_walkability_predicate`, the column stand-cell hint (`smooth_stand_hint`, explicitly reset on smooth-less maps so swaps never leak a stale hint) to `Colony.set_stand_cell_hint`, and `Map.ground_height_at` to `Colony.set_ground_query`. Returns the container (or `null`). Called after `wire_player`; re-run per map load so swaps pick up the new map's layers. |

### Class: SpawnHelpers

**Extends:** RefCounted (static class)
**Script:** `spawn_helpers.gd`
**Description:** Reads authored spawn positions and furniture records from a `Map`'s `SpawnPoints` container. Scene markers override `MapDef` values when present (non-zero) — an authored POI scene can place `PlayerSpawn` / `EnemySpawn_*` Marker3Ds to control exactly where actors enter, and `Furniture_*` markers to author furniture placement.
**Used by:** `SceneManager._wire_map` (player spawn resolution + authored-furniture replay + marker cleanup).

**Static functions:**

| Function | Description |
|---|---|
| `read_spawns(map: Map) -> Dictionary` | `{ "player": Vector3, "enemies": Array[Vector3], "colonists": Array[Vector3], "furniture": Array[{def_id, anchor, yaw}] }` from the `SpawnPoints` node's children (`ColonistSpawn` markers feed the colonists list). Zeros/empty if absent. |
| `clear_furniture_markers(map: Map) -> void` | Frees the `Furniture_*` markers after their records have been replayed into the live `FurnitureLayer` (each also carries an editor `PreviewMesh` child that would otherwise duplicate the spawned mesh). No-op if the map has no `SpawnPoints`. |
