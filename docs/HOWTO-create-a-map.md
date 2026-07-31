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
├── map.sqlite        # voxel terrain database (authored; copied to user:// at runtime)
└── map_def.tres      # MapDef resource — the catalog entry (id, name, scene, spawns)
```

- **`map.sqlite`** — the Zylann `VoxelStreamSQLite` database. Authored in the
  editor via Voxel Paint. **Never written to at runtime** — `SceneManager` copies
  it to `user://maps/<map_id>/map.sqlite` on first load and redirects the stream
  there, so authored maps stay pristine.
- **`map_def.tres`** — a `MapDef` resource (see `data/maps/map_def.gd`). This is
  the bridge between "a folder exists" and "the game can load this map". It
  carries the id, display name, which scene to load, spawn points, and POI
  metadata. `MapLibrary` scans for `map_def.tres` at startup.

> **The map id is the folder name.** `MapDef.id` must match the directory name —
> `SceneManager` derives the runtime sqlite path from `id`.

All POI maps share a single scene, `res://subsystems/maps/map_template.tscn`,
which has **no stream baked in** — `SceneManager` injects the per-map
`VoxelStreamSQLite` at runtime. The base colony uses its own scene
(`res://subsystems/voxel/map.tscn`).

---

## Step 1: Create the map folder + database

1. Open any scene that contains a `VoxelTerrain` (e.g.
   `subsystems/maps/map_template.tscn`).
2. Select the `VoxelTerrain` node in the scene tree.
3. Click the **Voxel Paint** button in the 3D editor toolbar.
4. In the side panel, under **Database**, click **New**.
5. Enter a map name in the dialog. **No spaces** (use `snake_case`, e.g.
   `abandoned_factory`). This becomes the folder name **and** the `MapDef.id`.
6. Click **Create**.

This creates:
- `res://data/maps/<map_id>/` (the folder)
- `res://data/maps/<map_id>/map.sqlite` (empty database, assigned to the terrain)
- `res://data/maps/<map_id>/map_def.tres` (a default `MapDef`: `map_type = POI`,
  `scene_path` → `map_template.tscn`)

The FileSystem dock refreshes automatically. The terrain stream is now wired to
the new database, and the scene is saved.

> **Why "New" creates a POI by default:** the Voxel Paint tool assumes authored
> maps are expedition destinations. To author the base colony or a different map
> type, edit `map_def.tres` afterward (Step 3).

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
| `scene_path` | The scene to load. POIs → `res://subsystems/maps/map_template.tscn`. Leave as-is unless you have a custom scene. |
| `map_type` | `POI` (default), `BASE`, `BUILDING`, or `TOWN`. |
| `difficulty` | 1–N; shown in the world map list. |
| `player_spawn` | Fallback spawn position if the scene has no `PlayerSpawn` marker. |
| `enemy_spawns` | Array of `{ "pos": Vector3, "count": int }`. |

> **Scene markers override the def.** If the scene contains a
> `SpawnPoints/PlayerSpawn` (Marker3D), its global position takes precedence over
> `player_spawn`. Same for `SpawnPoints/EnemySpawn_*`. See `spawn_helpers.gd`.

---

## Step 4 (optional): Author spawn points in the scene

For POIs that use `map_template.tscn`, you can place markers directly in the
scene instead of (or in addition to) the def:

1. Open `res://subsystems/maps/map_template.tscn`.
2. Under the `SpawnPoints` node, position `PlayerSpawn` (Marker3D).
3. Add `EnemySpawn_*` Marker3D children for enemy spawn points.

`SpawnHelpers.read_spawns()` reads these at load time. Non-zero marker positions
override the def's fallback values.

> **`map_template.tscn` is shared by all POIs.** Spawn markers placed here apply
> to every POI that uses it. For per-POI spawns, set them in `map_def.tres`
> instead, or create a dedicated scene and point `scene_path` at it.

---

## Step 5: Test in-game

1. Run the project (F5).
2. The base colony loads on startup.
3. Press **M** to open the **World Map**.
4. Your new map appears in the POI list (all `map_type = POI` maps are
   auto-discovered at startup).
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
2. Frees the current map.
3. Instantiates the scene at `map_def.scene_path`.
4. **Copy-on-load:** `_redirect_sqlite_stream()` —
   - If the terrain has a `VoxelStreamSQLite` pointing at `res://`, copies the
     pristine database to `user://maps/<id>/map.sqlite` (only if the runtime copy
     doesn't already exist) and redirects the stream there.
   - If the terrain has **no stream** (the template case), injects a new
     `VoxelStreamSQLite` pointing at `user://maps/<id>/map.sqlite`.
5. Awaits one frame (for child `_ready` calls, esp. camera wiring).
6. Wires subsystems via `MapWiring` (build controller, player, camera).
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
- The terrain has no stream assigned (the Database label shows red). Click
  **New** to create one, or **Pick...** to assign an existing `.sqlite`.

**Wrong map loads / id mismatch.**
- `MapDef.id` must equal the folder name. `SceneManager` derives the runtime
  path from `id`; a mismatch means the copied database lands in the wrong place.
