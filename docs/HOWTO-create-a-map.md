# How To: Create a New Map

> End-to-end guide for authoring a new map (base, POI, or otherwise) and making it
> loadable at runtime. Covers the editor authoring flow (Voxel Paint) and the
> data-file conventions that the runtime loader (`SceneManager`) expects.
>
> **Prerequisites:** the Voxel Paint plugin enabled (`addons/voxel_paint/`).

---

## How a map is structured

Every map lives in its own subdirectory under `res://data/maps/<map_id>/`:

```
data/maps/<map_id>/
├── map.tscn         # the map's own scene, stamped from the template (per-map stream baked in)
├── map.sqlite       # voxel terrain database (authored; copied to user:// at runtime)
└── map_def.tres     # MapDef resource — the catalog entry (id, name, scene, spawns)
```

- **`map.tscn`** — the map's own scene, stamped from `subsystems/maps/map_template.tscn`
  by the plugin at creation time, with a `VoxelStreamSQLite` pointed at this map's
  database already wired in. Spawn markers and painted furniture live here, per map.
- **`map.sqlite`** — the Zylann `VoxelStreamSQLite` database. Authored in the
  editor via Voxel Paint. **Never written to at runtime** — `SceneManager` copies
  it to `user://maps/<map_id>/map.sqlite` on first load and redirects the stream
  there, so authored maps stay pristine.
- **`map_def.tres`** — a `MapDef` resource (see `data/maps/map_def.gd`). This is
  the bridge between "a folder exists" and "the game can load this map". It
  carries the id, display name, which scene to load, spawn points, and POI
  metadata. `MapLibrary` scans for `map_def.tres` at startup; `scene_path`
  points at this folder's `map.tscn`.

> **The map id is the folder name.** `MapDef.id` must match the directory name —
> `SceneManager` derives the runtime sqlite path from `id`.

Every map — POI and base alike — gets its own stamped scene; nothing loads the
bare template directly (the base colony loads `data/maps/base/map.tscn`). The
template itself has **no stream baked in**; the stamping step injects the
per-map `VoxelStreamSQLite` at creation time, and `SceneManager` redirects that
stream to `user://` at runtime.

---

## Step 1: Create the map folder + database

1. Click the **Voxel Paint** button in the 3D editor toolbar (visible for any
   node selection — no need to select a `VoxelTerrain` first).
2. In the side panel, find the **Maps** section (it lists existing maps as
   open-to-edit buttons).
3. Click **+ New Map**.
4. In the dialog, enter a map name. **No spaces** (use `snake_case`, e.g.
   `abandoned_factory`). This becomes the folder name **and** the `MapDef.id`.
5. Pick a **Type** — `POI` (expedition destination; the default) or `BASE`
   (home colony, never listed as a POI).
6. Click **Create**.

This creates:
- `res://data/maps/<map_id>/` (the folder)
- `res://data/maps/<map_id>/map.tscn` — a fresh scene stamped from the template,
  with a `VoxelStreamSQLite` pointing at the new database already wired in
- `res://data/maps/<map_id>/map.sqlite` (empty database)
- `res://data/maps/<map_id>/map_def.tres` (a default `MapDef`: your chosen
  `map_type`, `scene_path` → this folder's `map.tscn`)

The plugin then opens the new `map.tscn` in the editor and binds its terrain
for painting. The FileSystem dock refreshes automatically.

> **Why POI is the default:** the Voxel Paint tool assumes authored maps are
  expedition destinations. To author the base colony or a different map type,
  pick `BASE` in the dialog (or edit `map_def.tres` afterward — Step 3).

---

## Step 2: Paint the terrain

With Voxel Paint active and the database assigned:

1. Pick a **block type** from the dropdown (terrain, metal, reinforced, scrap,
   stone, wood).
2. Set the **brush radius** (0.5–5.0).
3. **LMB** to paint, **Shift+LMB** (or the Erase toggle) to erase.
4. Edits flush to the database automatically via
   `VoxelTerrain.save_modified_blocks()`.

Paint your structures, terrain features, walls, etc. Persistence is immediate —
edits survive scene close/reopen and editor restarts.

> **Hit detection in the editor** uses a `get_voxel()` ray-march (NOT a physics
> raycast — `VoxelTerrain` emits no collision in the editor viewport). See
> `addons/voxel_paint/voxel_paint_plugin.gd` if brush targeting feels off.

---

## Step 3: Edit `map_def.tres` metadata

Open `res://data/maps/<map_id>/map_def.tres` in the inspector. Set:

| Field | What to set |
|---|---|
| `id` | Must match the folder name (already set by "New"). |
| `display_name` | Player-facing name (e.g. "Abandoned Factory"). |
| `description` | One-liner for the world map UI. |
| `scene_path` | The scene to load — already points at this map's own `data/maps/<id>/map.tscn`. Leave as-is unless you have a custom scene. |
| `map_type` | `POI` (default), `BASE`, `BUILDING`, or `TOWN`. |
| `difficulty` | 1–N; shown in the world map list. |
| `player_spawn` | Fallback spawn position if the scene has no `PlayerSpawn` marker. |
| `enemy_spawns` | Array of `{ "pos": Vector3, "count": int }`. |

> **Scene markers override the def.** If the scene contains a
> `SpawnPoints/PlayerSpawn` (Marker3D), its global position takes precedence over
> `player_spawn`. Same for `SpawnPoints/EnemySpawn_*` and
> `SpawnPoints/ColonistSpawn`. See `spawn_helpers.gd`.

---

## Step 4 (optional): Author spawn points in the map scene

Place markers directly in the map's own scene instead of (or in addition to)
the def:

1. Open `res://data/maps/<map_id>/map.tscn`.
2. Under the `SpawnPoints` node, position `PlayerSpawn` (Marker3D).
3. Add `EnemySpawn_*` Marker3D children for enemy spawn points, and
   `ColonistSpawn_*` Marker3D children where colonists should spawn on a fresh
   New Game (base map).

`SpawnHelpers.read_spawns()` reads these at load time. Non-zero marker positions
override the def's fallback values.

> **Each map owns its scene.** Spawn markers placed in one map's `map.tscn`
> affect only that map — the template the scene was stamped from is pristine,
> and nothing loads it directly.

---

## Step 5: Test in-game

1. Run the project (F5) — the game boots to the Splash → Main Menu (no map
   loads until you start a run).
2. Click **New Game** — the base colony loads, and every `map_type = POI` map
   is discovered at this moment (the discovery loop runs in the New Game flow,
   not at boot).
3. Press **M** to open the **World Map**.
4. Your new map appears in the POI list.
5. Click **Depart** to travel there.
6. Click **Return to Base** to come back.

> **What happens on depart:** `ExpeditionManager.start_expedition()` →
> `SceneManager.swap_map(map_id)` → the template scene loads, the pristine
> `map.sqlite` is copied to `user://maps/<map_id>/map.sqlite` (first load only),
> and the stream is redirected there. Subsequent loads reuse the runtime copy.

---

## Under the hood: the runtime load flow

For reference, here's what `SceneManager.swap_map(map_id)` does:

1. Looks up the `MapDef` in `MapLibrary` (autoload).
2. Frees the current map (emits `map_unloading` first — SaveSystem parks the
   outgoing map's state).
3. Instantiates the scene at `map_def.scene_path`.
4. **Copy-on-load:** `_redirect_sqlite_stream()` —
   - If the terrain has a `VoxelStreamSQLite` pointing at `res://`, copies the
     pristine database to `user://maps/<id>/map.sqlite` (only if the runtime copy
     doesn't already exist) and redirects the stream there.
   - If the terrain has **no stream** (the bare-template case), injects a new
     `VoxelStreamSQLite` pointing at `user://maps/<id>/map.sqlite`.
5. Awaits one frame (for child `_ready` calls, esp. camera wiring).
6. Wires subsystems via `MapWiring` (build controller, player, colonists) —
   then **parked-state branch:** if SaveSystem has parked state for this map
   (a loaded save), it applies voxel HP + furniture + blueprints and the wiring
   *skips* authored `Furniture_*` marker replay (`SpawnHelpers.clear_furniture_markers`)
   to avoid double-spawning; otherwise the authored markers are replayed into the
   live `FurnitureLayer` and then cleared.
7. Emits `map_loaded`.

The `user://` copy means **runtime mutations (building, combat damage) never
touch the authored `res://` database.** To reset a map to its authored state,
delete `user://maps/<id>/map.sqlite`.

---

## Troubleshooting

**The map doesn't appear in the world map.**
- Check `map_def.tres` exists at `data/maps/<id>/map_def.tres`.
- Check `MapDef.id` is non-empty and `map_type == POI`.
- `MapLibrary` only scans subdirectories of `data/maps/` for `map_def.tres`.
  Loose `.tres` files at the top level are ignored.

**11k errors on boot ("Could not open database").**
- A scene has a `VoxelStreamSQLite` pointing at a deleted/moved `res://`
  database. The stream path is baked into the `.tscn`. Either remove the
  `VoxelStreamSQLite` sub-resource (the template case — let `SceneManager`
  inject one) or repoint it at a valid database.

**Painted edits don't persist.**
- The open scene's terrain has no stream bound. The panel's terrain-status
  label (under **Maps**) tells you the binding state — open an existing map
  from the **Maps** grid or create one with **+ New Map**, both of which bind
  the terrain automatically. (Stamped map scenes always carry their stream.)

**Wrong map loads / id mismatch.**
- `MapDef.id` must equal the folder name. `SceneManager` derives the runtime
  path from `id`; a mismatch means the copied database lands in the wrong place.
