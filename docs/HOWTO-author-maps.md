# How To: Author Maps

> Complete guide for creating and authoring dual-voxel maps in *Xeno Frontier: Colony Defense* using the standalone **Map Editor** (`tools/map_editor/map_editor.tscn`).
>
> Covers end-to-end map authoring: smooth terrain sculpting, block construction, furniture placement, spawn point configuration, metadata editing, and runtime testing.

---

## 1. Overview and Architecture

Every map in *Xeno Frontier: Colony Defense* lives under `res://data/maps/<map_id>/` and is composed of:

| File | Purpose |
|---|---|
| `map_def.tres` | `MapDef` resource catalog entry (id, display name, scene path, map type, player spawn, difficulty). |
| `map.tscn` | Stamped scene holding the blocky terrain, smooth terrain, and `SpawnPoints` container with marker nodes. |
| `terrain_gen.tres` | Optional per-map `TerrainGenDef` — written when the map is created from a heightmap image (embedded texture). |
| `map.sqlite` | Authored blocky voxel database (copied to `user://maps/<map_id>/` at runtime). |
| `terrain.sqlite` | Optional authored Transvoxel smooth terrain database (copied to `user://maps/<map_id>/` at runtime). |

The **Map Editor** is an in-engine authoring tool that runs the actual game voxel engine, giving you true WYSIWYG rendering of dual-voxel terrain (smooth Transvoxel SDF hills + blocky voxel structures).

---

## 2. Launching the Map Editor

1. In the Godot editor, navigate to `tools/map_editor/map_editor.tscn`.
2. Press **F6** (or click *Play Current Scene*).
3. The **Map Launcher** modal will open with a list of all detected maps in `res://data/maps/`.

### Creating a New Map

1. In the Map Launcher, fill in the **CREATE NEW MAP** form: enter a unique map name (lowercase `snake_case`, no spaces) and select the map type (`BASE`, `POI`, `BUILDING`, or `TOWN`).
2. Set **World Dimensions (m)**: **Span** (horizontal XZ width/depth, default 192 m), **Floor** (minimum Y / underground depth, default −48 m), **Ceil** (maximum Y / height ceiling, default 16 m).
3. Pick a **Terrain** mode:
   - **Procedural (noise)** — choose a shared terrain def from `data/terrain/` (the default, `ground_default`, is preselected).
   - **Heightmap (image)** — pick a grayscale image from disk (see section 5).
   - **None** — blocky-only map, no smooth terrain.
4. Optionally tune **Flora** (**Rate**: spawns/day, default 0/disabled; **Cap**: max concurrent flora, default 60; **Try**: placement attempts per spawn, default 15) and **Water** (**Enable Water** toggle, default on; **Level (Y)** spinbox, default −2 m) — all four are editable later too (flora via the Metadata panel §6, water via the Terrain drawer's Flood Water tool).
5. Click **Create & Open**. The editor will:
   - Create `res://data/maps/<map_id>/`
   - Stamp a fresh `map.tscn` with a dedicated SQLite voxel stream
   - Initialize `map_def.tres` (pointing at the chosen terrain def; heightmap maps also get their per-map `terrain_gen.tres`)
   - Load the new map directly into the editing viewport.

### Opening an Existing Map

Click any map entry in the list (e.g. `base`) to load it.

---

## 3. Navigation and Camera Controls

When a map is loaded, mouse look is automatically captured.

| Input | Action |
|---|---|
| `Mouse Move` | Look around (pitch / yaw) |
| `WASD` | Fly horizontally relative to camera facing |
| `Space / C` | Fly vertically Up / Down |
| `Shift` (Hold) | Fast fly speed boost |
| `G` | Toggle y=0 reference wireframe grid |
| `Esc` | Release mouse cursor. Pressing `Esc` again opens the exit confirmation prompt |

---

## 4. Modes and Tool Workflows

Switch between modes using **F1** through **F6**:

### Mode 1: Navigate (`F1`)
Free camera inspection mode. Crosshair reads out exact world-space coordinates without performing edits.

### Mode 2: Block Mode (`F2`)
Build or destroy blocky voxel structures.

- **`LMB`**: Paint block at the targeted cell (uses the surface normal to place against walls/floors).
- **`Shift + LMB`**: Erase targeted block.
- **`[` / `]`** or **`Tab` / `Shift + Tab`**: Cycle selected block type (Wood, Stone, Metal, Scrap, Reinforced, Water, etc.).
- **`B + Mouse Wheel`**: Adjust brush footprint diameter (1x1x1 up to 11x11x11).
- **`R`**: Cycle the active rotation axis (X/Pitch, Y/Yaw, Z/Roll — shown in the HUD).
- **`Mouse Wheel`** (without `B`): Rotate the block brush 90° around the active axis.
- **`Middle Click`**, **`Alt + LMB`**, or **`I`**: Eyedropper — pick the hovered block's type and rotation into the brush.
- **`` ` ``** (or `Z` without Ctrl): Reset brush rotation to identity.
- **`Ctrl + Z`**: Undo block paint or erase stroke.

### Mode 3: Terrain Mode (`F3`)
Sculpt continuous Transvoxel SDF terrain.

- **`LMB`**: Add terrain material at the crosshair point.
- **`Shift + LMB`**: Carve away smooth terrain.
- **`[` / `]`** or **`B + Mouse Wheel`**: Increase or decrease brush sculpt radius (0.5 m to 5.0 m).
- **`M` / `Shift + M`**: Cycle the terrain material added by `LMB` (from `data/terrain/materials/`; the HUD shows `name (i/N)`). The id persists in the voxel-metadata sidecar and drives mining (`architecture/mining.md`). Each blob shows a colored decal marker from the material's `color` (except the surface material, which matches the terrain's own top band) — iron reads rust, gold reads gold. The terrain itself is textured by depth, dirt fading into rock (a shader look — per-voxel texturing is a documented dead end, F14 in `docs/VOXEL-TOOL-NOTES.md`).
- **`Ctrl + Z`**: Undo terrain sculpt operation.

### Mode 4: Furniture Mode (`F4`)
Place interactive furniture and appliances (beds, workbenches, crates, doors, lights).

- **Furniture Palette Sidebar**: Lists all `FurnitureDef` resources in `res://data/furniture/`. Filter by typing in the search box.
- **`Tab` / `Shift + Tab`** or **`[` / `]`**: Cycle through filtered furniture items.
- **`Mouse Wheel`**: Rotate the ghost furniture by 90 degrees yaw per notch.
- **`LMB`**: Place furniture at target anchor position.
- **`Shift + LMB`**: Remove targeted furniture.

*(Note: Trees and vegetation are dynamically managed by the `PlantSpawner` runtime system based on `MapDef` settings rather than statically scattered during authoring.)*

### Mode 5: Spawn Mode (`F5`)
Place player, colonist, and enemy spawn markers.

- **Spawn Type Selector**: Choose `Player Spawn`, `Colonist Spawn`, `Enemy Spawn`, or `Remove Spawn` from the sidebar list, via number keys `1`-`4`, or by cycling with `Tab` / `Shift + Tab`.
- **`LMB`**: Place a marker of the selected type at the target surface position (single `PlayerSpawn`; multiple `ColonistSpawn_N` / `EnemySpawn_N`).
- **`Shift + LMB`**: Delete the nearest spawn marker within range (same as selecting `Remove Spawn` then clicking).

### Mode 6: Structure Mode (`F6`)
Stamp pre-authored `StructureDef` structures (`.vox` imports with palette mappings).

- **`[` / `]`** or **`Tab`**: Cycle structure. **`R` / Mouse Wheel**: Rotate. **`Ctrl + Mouse Wheel`**: Y-offset. **Arrows**: Nudge (**`Shift`** = 5 m).
- **`LMB`**: Stamp the structure at the ghost position (blocks via `set_block_at`, smooth-terrain palette targets as material blobs).

---

## 5. Terrain from a Heightmap Image

You can author the natural terrain's base shape in any external image editor (Krita, GIMP, Photoshop) and import it at map creation:

1. **Paint a grayscale heightmap**: bright pixels are high ground, dark pixels are low. One pixel = one world meter, centered on the world origin (image center sits at world (0,0); image +x → world +x, image +y → world +z). PNG/JPG/BMP/WebP/TGA are accepted; keep it at least 16 px and preferably under 1024x1024 (a 512x512 image is a 512x512 m map).
2. In the launcher's create form, set **Terrain** to **Heightmap (image)** and click **Browse…** to pick the file. The form previews the image and its footprint (`512x512 px → 512x512 m`).
3. Set **Min Height (m)** / **Max Height (m)**: pixel brightness 0–1 maps linearly between them (e.g. min −6, max 10 → the floor sits at −6 m and the brightest peaks at +10 m).
4. Toggle **Snap to 1m Grid (Terraced)** (enabled by default): quantizes continuous elevations into discrete 1-meter integer steps (integer Y). This creates flat plateaus and stepped terraces where building foundations, floors, and walls sit perfectly flush on the block grid without hovering or clipping.
5. **Create & Open** — the editor writes a self-contained `terrain_gen.tres` (quantized image embedded) into the map folder and loads the map with the terrain already generated.

**Sculpting on top still works**: F3 terrain brushes are overrides stored in `terrain.sqlite` — the heightmap stays the base that regenerates wherever you haven't sculpted. Changing the image or span later never rewrites existing sculpts, but they keep their *absolute* heights, so a lowered base may leave them floating (the terrain drawer warns about this).

**Adjusting later** — the **Terrain** toolbar button opens the terrain drawer: tweak Min/Max Height (or seed/frequency on noise maps), replace the image, convert a noise map to a heightmap, or remove terrain entirely. **Apply & Reload** saves the def and reloads the map (a deliberate reload, not a live swap — streaming makes hot-swapping generators unreliable). What reload does step-by-step (inject def + catalog → build generator → attach streams) is documented in [Voxel World](architecture/voxel-world.md) "Terrain generation when a map opens" and [Map Editor](architecture/map-editor.md) §3A.

**Known limits**: 8-bit precision (≈6 cm steps over a 16 m range — Transvoxel smoothing hides this well for organic terrain); no horizontal scaling (1 px is always 1 m — resize the image in your editor if you need a different footprint); the image **repeats periodically** across the infinite plane (F10 in VOXEL-TOOL-NOTES) — mismatched image edges become a cliff seam at every repetition, so keep the heightmap seamless if the far terrain matters (GIMP workflow: `tmp/HOWTO-heightmap-gimp.md`).

**Hand-authoring variant** (shared, reusable defs): drop a PNG next to your defs in `data/terrain/` — its import must be **Lossless** (VRAM compression destroys pixel data) — and reference it from a `TerrainGenDef`'s `heightmap` field. `data/terrain/heightmap_valley.tres` + `heightmap_valley.png` ship as a worked example.

---

## 6. Water Authoring

Water bodies are configured at creation time (§2) and can be adjusted or reflooded afterward:

- The **Terrain** toolbar button's drawer exposes the same **Enable Water** toggle and **Water Level (Y)** spinbox from the creation form, plus a **Flood Water** button.
- **Flood Water** sweeps every `(x, z)` column inside the map's `world_bounds`: it probes down to the solid floor (smooth terrain or blocky structure) and fills open air cells between that floor and `water_level` with `water` blocks, clearing any water above `water_level`.
- Enclosed interiors stay dry automatically — solid walls and roofed rooms displace the open-air cells the flood tool fills, so building a cofferdam or a sealed basement below the water line keeps it livable without manual draining.

---

## 7. Map Metadata Editing

Click the **Metadata** button in the top-right toolbar to open the metadata drawer:

- **Display Name**: User-friendly title displayed in UI and menus.
- **Description**: Summary text shown in expedition selectors and map logs.
- **Map Type**: `BASE` (colony headquarters), `POI` (expedition destination), `BUILDING`, or `TOWN`.
- **Difficulty**: Target difficulty tier (1 to 10).
- **Flora Regeneration**:
  - **Flora Spawns / Day**: Number of plant spawn attempts spread across a day (0 = disabled).
  - **Flora Spawn Cap**: Maximum simultaneous living flora entities allowed on the map.
  - **Max Spawn Attempts**: Placement attempt budget per spawn before skipping.
  - **Min Distance**: Minimum distance in meters between spawned plants and existing trees / player spawn.

Metadata edits are automatically saved to `map_def.tres` when saving.

---

## 8. Saving and Persistence

- Press **`Ctrl + S`** or click the **Save** button in the top-right toolbar.
- The editor will:
  1. Flush all pending voxel edits to `map.sqlite` and `terrain.sqlite`.
  2. Pack the updated map scene hierarchy (including `SpawnPoints` markers) to `map.tscn`.
  3. Save `map_def.tres` with updated spawn coordinates and metadata.
  4. Clear the dirty flag (`*`).

---

## 9. Testing In-Game

There is no debug console yet (see [Debug Console](architecture/debug-console.md) — planned, not built), so map testing goes through the normal gameplay flow:

1. Launch the game normally via `res://subsystems/core/main.tscn`.
2. Start a new run from the main menu — `main_menu._start_new_game` always swaps to the `base` map first (`SceneManager.swap_map("base")`).
3. **For `base`**: it's already loaded after step 2 — verify directly.
4. **For POI / Expedition maps**: every `MapDef` of type `POI` is auto-discovered at run start (`ExpeditionManager.discover`), so open the World Map screen (`M`) and depart to your map's POI entry to swap into it.
5. Verify that the player spawns at `PlayerSpawn`, colonists spawn at their markers, furniture has correct collisions, and voxel terrain matches the authored state.
