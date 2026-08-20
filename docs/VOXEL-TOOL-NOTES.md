# Zylann's `voxel_tool` — Notes & Gotchas

> Consolidated, durable knowledge about the `zylann.voxel` GDExtension (Godot 4.7)
> as it behaves **in this project**. Everything here was established by experiment
> against this exact build — implement to match it; do not re-derive.
>
> Source: verified-fact writeups from `tmp/map_authoring/` (the map authoring
> spike) plus the older `tmp/project-vek/docs/gotchas/` notes. Those temp dirs
> are scheduled for cleanup, so the durable parts live here.
>
> Companion docs: `docs/HOWTO-create-a-map.md` (authoring workflow),
> `docs/ARCHITECTURE.md` (Voxel/World + Maps subsystems).

---

## TL;DR — the load-bearing rules

1. **No paint tool ships with the addon.** WYSIWYG painting is the project-local
   `addons/voxel_paint/` `EditorPlugin`. (See F1.)
2. **In the editor viewport, `VoxelTerrain` emits no chunks/collision/mesh.** So
   both `VoxelTool.raycast()` and Godot's physics `intersect_ray()` are **dead in
   the editor**. Editor hit-detection is a `get_voxel()` ray-march. At *runtime*
   the player's `VoxelViewer` makes chunks/collision exist, so physics raycast
   works there. (See F4 + the Raycast section.)
3. **Voxel writes to an un-streamed coordinate are silent no-ops**
   (`WARNING: Area not editable at: set_voxel`). Poll `get_voxel` until the write
   lands, or defer ~40 frames for a fresh process. (See F3.)
4. **Index 0 must be air.** Set the first `VoxelBlockyLibrary` model to
   `VoxelBlockyModelEmpty`, or every air cell renders as a solid cube. (See
   VoxelBlockyLibrary section.)
5. **The baked library is what makes terrain visible in the editor.** Not the
   stream, not a `VoxelViewer`. (See F5.)
6. **Smooth terrain (`VoxelMesherTransvoxel`) works at RUNTIME** — renders,
   collides, and coexists with a blocky terrain in one scene. Keep terrain
   nodes at the origin: a translated `VoxelTerrain` collides at the offset but
   renders no meshes. (See F7.)
7. **Smooth terrain is editable + persistent at runtime** — `do_sphere`
   carve/remove and add/set both move the collision surface, and a
   `VoxelStreamSQLite` flush survives full terrain teardown/rebuild with saved
   blocks overriding the generator. The mesher has **no material API** (one
   fixed appearance; voxel values are pure SDF density). (See F8.)

---

## Verified facts (F1–F8)

### F1 — No in-editor paint tool ships with zylann.voxel
`VoxelTerrainEditorPlugin` auto-registers but provides only previews + a monitor
bar — no brush/gizmo/paint. **WYSIWYG painting must be a custom `EditorPlugin`.**
This is the reason `addons/voxel_paint/` exists.

### F2 — VoxelStreamSQLite persistence is proven
Writes via `VoxelTool.set_voxel(Vector3i, int)` to a terrain with a
`VoxelStreamSQLite` **survive a cold restart** when flushed with
`VoxelTerrain.save_modified_blocks()`. The stream is **authoritative over the
generator** — edited blocks replay on top of generated terrain. The `.sqlite` is
created lazily on first flush. This is the paint plugin's persistence mechanism.

> **Runtime caveat (this project):** the authored `res://` database is
> read-only at export. `SceneManager._redirect_sqlite_stream()` copies it to
> `user://maps/<id>/map.sqlite` on first load and repoints the stream there. See
> ARCHITECTURE.md "Subsystem: Maps".

### F3 — The 40-frame settle (voxel writes)
Voxel writes to a coordinate not yet streamed in are **silent no-ops**
(`WARNING: Area not editable at: set_voxel`). Rule: when writing to a coordinate
that may not be loaded, poll `get_voxel` until it reflects the write, or defer
generously (~40 frames for a fresh process targeting an unloaded coordinate).
- **Click-painting is mostly exempt** — the ray-march hits an already-rendered
  surface block, which is streamed. Guard strokes with a retry on
  "Area not editable" (the paint plugin does: up to 5 retries, 0.1s apart).
- **The one-frame `await get_tree().process_frame`** used in `SceneManager.swap_map`
  / `MapWiring` is for **camera wiring only** (child `_ready` must run before
  camera refs are read), **not** voxel writes.

### F4 — Editor viewport: no chunks/collision/mesh from VoxelTerrain
The **bare** scene (`VoxelGeneratorFlat` + `VoxelMesherBlocky`, **no library**)
produces zero chunks, zero-size `aabb`, no collision — so both editor hit-paths
are dead:
- `direct_space_state.intersect_ray()` → nothing to hit (no collision bodies).
- `VoxelTool.raycast()` → returns `null` even on valid ground.

**Hit-detection in the editor plugin is therefore a `get_voxel()` ray-march**
along the camera ray (the generator's *data* layer IS queryable in the editor
even with no chunks). Do **not** use physics raycast or `VoxelTool.raycast` in
the editor plugin.

> **Contrast with runtime:** `BlockyGrid.raycast_to_voxel` *does* use the Godot
> physics raycast, because at runtime the player's `VoxelViewer` drives streaming
> and chunks/collision exist. That code is correct for runtime; do not "port" it
> into the editor plugin, and do not "fix" the editor plugin to use physics.

### F5 — Editor VISIBILITY is solved (decisive ingredient = baked library)
The full authoring scene (`VoxelGeneratorFlat` + `VoxelMesherBlocky` + **baked
`VoxelBlockyLibrary`** + `VoxelStreamSQLite`) **renders** a visible ground plane
in the editor viewport. The library is the decisive ingredient; the stream is an
inert cache for flat terrain; **no editor `VoxelViewer` is required** (the editor
camera is an adequate implicit viewer).
- The library does **not** make physics raycast work in the editor (still no
  collision bodies). It serves rendering only.
- `VoxelGeneratorGraph` + `VoxelMesherTransvoxel` does **NOT** render in this
  build even with a valid graph and the warning cleared → **do not plan on
  graph-based live editor authoring.** Sculpted terrain is done with the paint
  plugin (or MagicaVoxel import), same as structures. (Runtime smooth meshing
  itself was later proven fine — see F7; it is the editor viewport that fails.)

### F6 — Scripts on VoxelGenerator/VoxelStream must not be `@tool`
Generators/streams are native resources (`VoxelGeneratorFlat`,
`VoxelStreamSQLite`), not scripts — so this doesn't bite. The paint plugin is an
`EditorPlugin`, **not** a `@tool` script on the terrain — the correct pattern.
(If you ever script a generator/stream, do not mark it `@tool`, or the terrain's
preview/streaming can misbehave in the editor.)

### F7 — Smooth terrain works at RUNTIME; translated VoxelTerrain nodes don't render (2026-08-17 spike)
Validated by `testing/zylann/smooth_terrain_spike.tscn` (code-built world,
windowed run with viewport screenshots + a 441-column physics raycast scan;
automated via `--auto-quit`, see the scene's header for CLI flags):

- **`VoxelTerrain` AND `VoxelLodTerrain` with `VoxelMesherTransvoxel` +
  `VoxelGeneratorNoise2D` render, collide, and coexist with a blocky
  `VoxelTerrain` in the same scene.** F5's editor-viewport failure does NOT
  extend to runtime. This is the precondition for any "smooth terrain +
  blocky structures" split; verdict GO for both node types.
- **Smooth slopes produce non-axis-aligned raycast normals** (369/371 sampled
  columns). Anything deriving voxel cells from `hit.position + normal`
  (`BlockyGrid.raycast_to_voxel`) will need grid-snapping against such hits.
- **A translated `VoxelTerrain` (`position != origin`) collides at the offset
  but renders NO meshes** — bisect-proven: same blocky terrain at the origin
  renders, moved to `(96, 0, 0)` it is invisible while its collision still
  answers at world x=96. Rule: keep terrain nodes at the origin; offset
  content in voxel space or via a parent node. (The existing transform warning
  for `do_sphere` in the VoxelTool notes is the same landmine, different fuse.)
- **Body-vs-terrain collision is layer/mask bidirectional.** Setting only
  `collision_layer` on a terrain stops `RigidBody` interaction silently while
  physics raycasts still hit (a ray tests query-mask vs collider-layer only).
  Set `collision_mask` to include the probe/body layer whenever you assign a
  custom layer to a terrain.
- **`VoxelTerrain.aabb` stays zero in this build even when terrain visibly
  renders** (the known-good blocky control reads `(0,0,0)` while on screen).
  Never use `aabb` as a "did it mesh" probe; use screenshots or collision.
- Headless runs use the dummy rendering server, which rejects voxel mesh
  surfaces entirely — collision and raycasts still work headless, rendering
  does not. Judge rendering only from a windowed run.

### F8 — Smooth terrain is EDITABLE + PERSISTENT at runtime; no material API (2026-08-17 spike)
Validated by `testing/zylann/smooth_edit_spike.tscn` (windowed run, collision-
measured column probes; `--auto-quit` automated). All verdicts GO — this is the
green light for `smooth_grid.gd` (dual-voxel conversion Phase 2, docs/TODO.md):

- **`do_sphere` edits work on smooth terrain.** `MODE_REMOVE` carves (surface
  dropped exactly 2.0 for a r=2.5 sphere centered 0.5 above ground);
  `MODE_SET` + `value = 1` adds solid ground (surface rose to the sphere top).
- **Channel semantics (this build): channel 0 stores float SDF — solid ≤ 0,
  air > 0** (probed values: deep −1.999, surface 0.000, air +1.999). `MODE_SET
  value v` writes SDF `−v`, so **value 0 is still solid** — never "carve" with
  `MODE_SET 0`; use `MODE_REMOVE`. `get_voxel` (int) returns the raw bit
  pattern (3221216767 for −1.999) — meaningless; read `get_voxel_f`.
- **The smooth analogue of F2 holds: `VoxelStreamSQLite` +
  `save_modified_blocks()` persists carve AND add across a full terrain
  teardown/rebuild** (same generator, same db). Saved blocks override the
  generator; untouched columns regenerate identically.
- **`VoxelMesherTransvoxel` has NO material API in this build** — zero
  material-matching properties or methods (full property list in the spike
  log), and terrain meshes are **not node children** (no `MeshInstance3D`
  under the terrain; server-side). Voxel values are pure density — they cannot
  carry material identity. Consequence (D2): terrain material defs carry
  identity/hardness only; the smooth terrain has ONE fixed visual appearance
  in v1. No per-material rendering to design around.
- **Block-streaming signals (D4 heightfield-cache invalidation hooks), exact
  signatures:** `block_loaded(position: Vector3i)`,
  `block_unloaded(position: Vector3i)`,
  `mesh_block_entered(position: Vector3i)`,
  `mesh_block_exited(position: Vector3i)` — all single-arg, positions in
  block-grid coordinates. A rebuild streamed 5832 `block_loaded` / 4096
  `mesh_block_entered` emissions, so both fire generously during normal
  streaming — hook `block_unloaded`/`block_loaded` pairs for eviction.
- **`VoxelTool` surface in this build:** modes Add/Remove/Set (enum hint lists
  them; `MODE_SET` parses statically); brushes `do_hemisphere`, `do_point`,
  `do_sphere`, `do_box`, `do_path`, `do_mesh`; reads `get_voxel(_f)`,
  `set_voxel(_f)`, per-voxel `set/get_voxel_metadata`.

### F9 — Sqlite save timing: hot journals, lazy dirs, live flushes (2026-08-17, dual-voxel Phase 4)
Validated by the Phase-4 full-boot save/load smoke on the dev map plus
`tmp/` probes (sqlite3 CLI block counts over time). Facts any code that
copies, wipes, or repoints a `VoxelStreamSQLite` database needs:

- **Block saves commit in sqlite transactions; `flush()` does NOT guarantee
  they are on disk.** The only reliable outward sign of an in-flight
  transaction is a hot `<db>-journal` file beside the database (journal mode
  is `delete`), and sqlite removes it only after the db pages are flushed.
  A raw `DirAccess.copy_absolute` raced against a commit yields a STALE copy
  — byte-valid, schema-intact, missing the just-saved blocks (observed: slot
  snapshot of a db holding 1 saved block came out with 0). Consequence:
  SaveSystem quiesces (polls until no `-journal` remains anywhere under
  `user://maps/`, bounded) between the park flush and the slot snapshot, and
  again before `wipe_map_cache` unlinks files out from under live stream
  connections (which otherwise emits sporadic sqlite `disk I/O error` /
  `begin_transaction` failures).
- **`VoxelStreamSQLite` never creates the database's parent directory.** A
  missing dir means every block load fails ("Could not open database …
  unable to open database file") and the terrain silently stays empty.
  `SceneManager`'s redirect `make_dir_recursive`s the runtime dir before
  pointing a stream at it — keep doing that.
- **`save_modified_blocks()` works on a LIVE terrain** (no teardown needed,
  headless included) as long as the edited blocks were actually streamed in
  (F3: writes to never-loaded blocks are no-ops — a viewer must have visited
  them). It returns void in this build (no error code). Repointing
  `database_path` BEFORE the first block load/save is safe.
- **`VoxelStreamSQLite.flush()` exists** (plus `set_save_generator_output`,
  compression/key-cache options on the stream) but per the first bullet its
  return is not a durability barrier — treat journal clearance as the real one.

### F10 — VoxelGeneratorImage REPEATS its image out of bounds (2026-08-18, probed)

`VoxelGeneratorImage` tiles its image **periodically across the infinite
plane** — it neither clamps edge pixels nor falls back to `height_start`
beyond the image. Probed through the real pipeline (VoxelTerrain + teleported
VoxelViewer, `tmp/heightmap_bounds_probe2.gd`): a 32-px black/white image with
height 0/10 surfaces at world x=1000 (=1000 % 32 = 8, black → 0) and x=1017
(=25, white → 10), matching the periodic pattern and ruling out clamp (tall at
both) and flat (low at both). Consequences:

- The image is the texture of an endless tiled world, not a one-shot footprint:
  any discontinuity between opposite image edges becomes a visible cliff seam
  repeating at every image-width interval. Authors who care about far terrain
  must make the heightmap seamless (GIMP workflow: `tmp/HOWTO-heightmap-gimp.md`).
- A seam-free map edge is impossible to "fix in engine" without swapping
  generators — `VoxelGeneratorImage` has no wrap/clamp property in this build
  (property surface probed: image, height_start, height_range, blur_enabled,
  channel, iso_scale — see F-image-probe reference in
  `subsystems/voxel/smooth_grid.gd`).
- Note `VoxelGeneratorHeightmap` is ClassDB-registered but NOT instantiable in
  this build — it is not an available alternative.

---

## Raycast & hit-detection

### Runtime: use Godot's physics raycast
At runtime the player's `VoxelViewer` streams terrain + collision. Use Godot's
physics raycast against the collision bodies `VoxelTerrain` generates
(`BlockyGrid.raycast_to_voxel` does this). Requires the player's `VoxelViewer`
(added by `MapWiring.wire_player`) to precede any build interaction — chunks must
exist before the raycast hits anything.

```gdscript
# Requires VoxelViewer.requires_collision = true (set in MapWiring.wire_player)
var center := get_viewport().get_visible_rect().size / 2.0
var from := camera.project_ray_origin(center)
var dir  := camera.project_ray_normal(center)
var query := PhysicsRayQueryParameters3D.create(from, from + dir * 100.0)
var hit   := get_world_3d().direct_space_state.intersect_ray(query)
if hit.is_empty():
    return

# hit.position is a float Vector3 — nudge inward along the normal before flooring,
# or you land in the adjacent empty voxel (the hit lands on the face boundary).
var p: Vector3 = (hit.position - hit.normal * 0.001).floor()
var voxel_pos := Vector3i(int(p.x), int(p.y), int(p.z))
# Face the player is looking at (for placing a block adjacent):
var place_pos := voxel_pos + Vector3i(hit.normal.round())
```

**Why the nudge:** `hit.position` lands exactly on the face boundary between two
voxels. Without nudging inward by a small amount along the normal, flooring can
land in the adjacent (empty) voxel instead of the one that was hit.

**Screen center vs mouse:** for a first-person fly camera where the cursor isn't
locked to center, aim from the screen center, not the mouse position, so the
raycast matches where the camera is looking.

### Editor: use a `get_voxel()` ray-march (NOT physics, NOT `VoxelTool.raycast`)
Both runtime hit-paths are dead in the editor viewport (proven — F4):
1. `VoxelTool.raycast()` returns `null` even on valid hits.
2. Godot physics raycast has nothing to hit (no collision bodies in the editor).

The editor hit-path is a `get_voxel()` ray-march along the camera ray: step in
sub-voxel increments (`addons/voxel_paint/` uses `0.25`), sample
`vt.get_voxel(Vector3i(...))` at each step, and return the first air→solid
transition. It samples the generator's data layer directly, which is queryable in
the editor even though no chunks are built. The march returns **both** the solid
hit voxel and the previous air voxel (the empty cell a "place block" brush paints
into). See `_march_to_voxel` in `voxel_paint_plugin.gd`.

---

## VoxelBlockyLibrary

### Index 0 must be empty
The engine treats voxel ID 0 as air. Every cell above the flat surface has voxel
ID 0. If slot 0 in the library is a solid `VoxelBlockyModelCube`, those cells
render as opaque blocks — the camera sits inside solid geometry and sees nothing
(black screen, no artifacts).

**Fix:** set the first entry in the library's models array to
`VoxelBlockyModelEmpty`. Do this by changing the model *type* at slot 0, not by
adjusting `library_index` values elsewhere — `library_index` in block data files
only controls which voxel ID your code writes; it has no effect on what the
engine renders for voxel ID 0.

### This project's stable index table
`BlockLibrary` enforces: `0` = air (`VoxelBlockyModelEmpty`), **terrain forced to
1** (so `VoxelGeneratorFlat`'s `voxel_type = 1` renders as terrain without
remapping), the rest load alphabetically. The baked library is
`data/blocks/voxel_library.tres` (produced by `bake_voxel_library.gd`).

| index | block |
|---|---|
| 0 | air (`VoxelBlockyModelEmpty`) |
| 1 | terrain (forced) |
| 2 | metal |
| 3 | reinforced |
| 4 | scrap |
| 5 | stone |
| 6 | wood |

### The stored voxel value IS the library index — never pack bits into it
`VoxelMesherBlocky` addresses models by the raw voxel value: value N renders
(and collides) as library model N; values outside the model range produce no
mesh at all. There is no decoding step. So writing anything other than a plain
library index — e.g. packing 11 type bits + 5 rotation bits
(`VoxelBlockEncoder.encode`, c802b19) — yields voxels that **persist to
`map.sqlite` but never render or collide**, across saves and reloads. That was
the 2026-08-20 "stamped structures stay ghost-only" bug: the stamper, the block
brush, and in-game placement all wrote packed values (wood = 6<<5 = 192).
Verified by driving `VoxelMesherBlocky.build_mesh` directly: value 6 → 24-vert
cube, value 192 → no mesh. The packing functions were removed from
`VoxelBlockEncoder` — it is rotation-state math only.

### How per-voxel rotation works: baked variant models
Rotation rides in **which library index is stored**, never in bits of the
value. The mechanism, end to end:

1. **Authoring** — one unrotated mesh per block plus `rotation_mode` on the
   `BlockDef` (`NONE`/`YAW_ONLY`/`FULL_3D`). Authors never hand-make rotated
   meshes.
2. **Baking** — `BlockLibrary._bake_variants()` appends one `VoxelBlockyModelMesh`
   per orientation AFTER the whole base table (3 extra for YAW_ONLY, 23 for
   FULL_3D). Every variant **shares the def's mesh** and differs only in
   `mesh_ortho_rotation_index`; the mesher rotates the geometry at bake time.
   Because variants are appended, base indices never move — maps saved before
   a def became rotatable keep loading unchanged.
3. **Writing** — `BlockyGrid.set_block(pos, base_index, rot_index)` asks
   `BlockLibrary.get_stored_index()`: sanitize `rot_index` against the def's
   `rotation_mode` (`BlockDef.sanitize_rotation`), then store the variant's
   plain index (the base index itself when unrotated).
4. **Reading** — `get_block_type`/`get_block_rotation` decompose a stored
   index via `get_base_index`/`get_rotation_index`; `get_block_basis` turns
   the orientation into a `Basis` for previews.

### The orientation-index convention (mesh_ortho_rotation_index)
`VoxelBlockyModelMesh.mesh_ortho_rotation_index` selects one of 24 orthogonal
orientations. The convention is **not** Godot 3's `Basis.get_orthogonal_index()`
(removed in Godot 4) and does not follow any obvious math — it is a property
of the addon build. `VoxelBlockEncoder._ORTHO_BASES` hardcodes the table,
derived empirically: render an asymmetric probe mesh per index through
`VoxelMesherBlocky.build_mesh` and recover the rotation (method preserved in
`tmp/convention_derivation.gd`). Anchors: **index 0 = identity**; the four
yaws (rotation about +Y) are **{0, 22, 10, 16}** for 0/90/180/270 degrees —
this is `BlockDef.YAW_INDICES`, in quarter-turn order (so `sanitize_rotation`
accepts either a raw orientation index or a quarter-turn count 0..3).
`suite_voxel_block_encoder_test.test_ortho_table_matches_mesher_convention`
re-derives the table through the real mesher for all 24 indices: if an addon
update changes the convention, that test fails rather than content silently
mis-rotating. Ghost previews use the same bases
(`rot_index_to_basis`), so what you preview is what gets meshed.

### Painted voxels only render if the mesher library is set
A terrain with no `VoxelMesherBlocky.library` writes data fine but renders
nothing. The paint plugin's `_ensure_library()` handles this at activation;
authored map scenes reference the baked `voxel_library.tres` in their mesher.
Each `VoxelBlockyModelMesh` sets a `collision_enabled_0`-style property in
`block_library.gd`, so collision is on when the library is present. **The library
does not make physics raycast work in the editor** (F4) — it serves rendering
only.

---

## VoxelGeneratorFlat

### Save the scene after setting `voxel_type`
Godot omits properties from `.tscn` files when they equal the class default.
`VoxelGeneratorFlat`'s default `voxel_type` is 0 (air). If you set it to 1 in the
inspector but don't save the scene, the file still reads 0 at runtime — flat
terrain generates as all-air and nothing renders. **Always save the scene after
editing generator properties**, and verify the value appears in the `.tscn`.

No longer baked into `map_template.tscn` (2026-08-18 — initial terrain is the
smooth grid's), but the facts above still govern the temporary authoring-plane
workflow described in the authoring section below.

---

## VoxelTool API notes

- **`do_sphere(center, radius)`** takes **2 args** (a world-space `Vector3`
  center + radius), NOT 3. The voxel value must be set via the `_vt.value`
  property *before* calling `do_sphere`. (`set_voxel(Vector3i, int)` is the
  single-voxel variant.)
- **`mode`** — set `_vt.mode = VoxelTool.MODE_SET` for painting.
- Brush ops are **world-space**; convert a voxel index back to a world center via
  `terrain.to_global(Vector3(voxel_pos))` before calling `do_sphere`. Warn if the
  terrain has a non-identity transform — `do_sphere` uses the world-space center
  directly (the paint plugin's `_validate_transform` checks this).

---

## VoxelViewer

- **Required at runtime** for streaming terrain + collision around the player.
  `BuildController`'s physics raycast only hits something once chunks exist
  there, so the viewer must precede any build interaction. Added to the player by
  `MapWiring.wire_player` (`requires_visuals = true`).
- **Not required in the editor** — the editor camera is an adequate implicit
  viewer (F5). Authored map scenes bake none.
- **`requires_collision` is version-uncertain** in this GDExtension build — the
  codebase only sets it defensively via `"requires_collision" in viewer` + `set()`
  (never as a typed property). `requires_visuals` IS a real property. Keep the
  guard.
- **Reuse, don't stack.** Repeated map swaps would add a `VoxelViewer` per swap;
  `wire_player` looks for an existing one first and reuses it.

---

## EditorPlugin patterns (for `addons/voxel_paint/`)

Verified Godot 4 `EditorPlugin` API (use these exact identifiers):
- `_forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int` — the click
  hook. Return `AFTER_GUI_INPUT_STOP` (consume), `AFTER_GUI_INPUT_PASS` (let the
  editor handle), or `AFTER_GUI_INPUT_CUSTOM`.
- `_handles(object: Object) -> bool`, `_edit(object: Object)`,
  `_make_visible(visible: bool)` — object-type gating.
- Container: `add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, node)` /
  `remove_control_from_container(...)`.
- A project-local addon needs a `plugin.cfg` (unlike the auto-registering zylann
  plugin) and is enabled via Project Settings → Plugins.
- To create map data files from the plugin: `ResourceSaver.save(def, path)` for
  `.tres`, `EditorInterface.get_resource_filesystem().scan()` to refresh the
  FileSystem dock, `EditorInterface.save_scene()` to persist stream assignment.

---

## Authoring strategy (the WYSIWYG decision)

| Content type | Tool | Persistence |
|---|---|---|
| Hand-placed structures AND sculpted/organic terrain (hills, caves, plateaus) | **Custom `voxel_paint` EditorPlugin** | `VoxelStreamSQLite` (the map's `map.sqlite`) |
| Spawn points, decorations, markers | Godot Scene dock (`Marker3D`, `MeshInstance3D`) | Scene nodes |
| External props (optional) | MagicaVoxel `.vox` | PackedScene/ArrayMesh child of the map |

**One paint tool covers everything in-editor.** Structures and organic shaping
are both done with the paint plugin. Since 2026-08-18 the map template bakes
**no** `VoxelGeneratorFlat` — the blocky terrain is structures-only and the
initial ground at runtime is the smooth grid's (new maps default
`MapDef.terrain_gen` to the 50 m deep `data/terrain/default_ground.tres`). To
get a paintable ground plane while authoring, temporarily add a
`VoxelGeneratorFlat` (height 0, `voxel_type` 1) to `BlockyGrid/VoxelTerrain`
and **remove it before saving** — leaving it in would resurrect flat blocky
ground at runtime.

- **`VoxelGeneratorGraph` is demoted to runtime-only.** A render spike
  (2026-07-31) found a valid SDF graph + `VoxelMesherTransvoxel` produces **no
  visible geometry in this addon's editor viewport** even after the
  generator↔mesher warning clears. The "two WYSIWYG tools compose" framing is not
  supported for editor authoring. A graph may still be used for runtime-only
  generation — runtime smooth meshing itself is proven (F7) — but graph-in-editor
  remains dead.
- **MagicaVoxel is demoted to optional.** Its importer (`VoxelVoxEditorPlugin`)
  produces a PackedScene/ArrayMesh — not blocky `VoxelTerrain` data — and there
  is no built-in MagicaVoxel-color→block-type mapping (that's a DIY step on the
  color channel of a `VoxelBuffer` via `VoxelVoxLoader`). Do not block on it.
- **Fallback persistence form (proven):** if stream-based persistence ever proves
  awkward at scale, store authored structures as
  `Array[Dictionary]{pos: Vector3i, block_id: String}` and replay at runtime via
  `BlockyGrid.set_block_at()`. Verified to round-trip string ids exactly.

---

## Blender OBJ export (for custom `VoxelBlockyModelMesh` blocks)

Lessons learned exporting custom block meshes from Blender.

1. **Apply All Transforms before exporting.** Vertex coordinates in Edit Mode are
   in local space — they don't include the object's location/rotation/scale. If
   the object has an object-level transform, the exported OBJ will differ from
   what you see. *Symptom:* terrain renders on only one side; blocks offset.
   *Fix:* `Object > Apply > All Transforms` (Ctrl+A → All Transforms).
2. **Meshes must occupy exactly (0,0,0) to (1,1,1).** `VoxelBlockyModelMesh`
   expects the mesh to fill the unit cube from the origin. Offsets break
   placement and face culling (`culls_neighbors`). After applying transforms,
   confirm min vertex (0,0,0), max (1,1,1) in global coords.
3. **Use Forward: Y, Up: Z.** Maps Blender→OBJ/Godot as X→X, Z→Y, Y→Z (no sign
   flips). **Do not use Forward: -Y** — negating forward forces the exporter to
   also negate X to preserve right-handedness, so a cube at X 0→1 exports as
   -1→0. *Symptom:* terrain renders on only one side; block X negated in the OBJ.
4. **Face normals must point outward.** `VoxelBlockyModelMesh` uses backface
   culling; inward normals are invisible. *Check:* Viewport → Solid shading →
   Overlays → Face Orientation (blue=outward correct, red=inward broken). *Fix:*
   Edit Mode → select all (`A`) → `Mesh > Normals > Recalculate Outside`
   (Alt+N).
