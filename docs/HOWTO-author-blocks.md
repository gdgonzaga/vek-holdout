# How To: Author a Voxel Block

> End-to-end guide for modeling, texturing, configuring, and registering new voxel block types in *Xeno Frontier: Colony Defense*.
> Covers Blender mesh sizing, origin placement, export settings, texture variation shaders, 3-axis rotation configuration, and registering blocks into the Map Editor and Voxel Engine.
>
> **Prerequisites:** Basic knowledge of Blender 3D modeling and Godot `.tres` Resource creation.
> Read [`docs/architecture/voxel-world.md`](architecture/voxel-world.md) and [`docs/architecture/data-schemas.md`](architecture/data-schemas.md) for subsystem details.

---

## 1. Blender Modeling Guidelines & Requirements

Voxel blocks in *Xeno Frontier: Colony Defense* are discrete 1-meter cubic units rendered by Zylann's blocky voxel mesher (`VoxelMesherBlocky`). To ensure clean face-stitching and alignment across chunk boundaries, every authored 3D mesh MUST adhere strictly to the following rules:

### A. Block Sizing & Bounding Box
- **Dimensions**: Exactly **1.0 m × 1.0 m × 1.0 m**.
- **Bounding Box**: All vertices MUST span strictly from `(0.0, 0.0, 0.0)` to `(1.0, 1.0, 1.0)`:
  - `X` in `[0.0, 1.0]` (Left = 0.0, Right = 1.0)
  - `Y` in `[0.0, 1.0]` (Bottom = 0.0, Top = 1.0)
  - `Z` in `[0.0, 1.0]` (Front = 0.0, Back = 1.0)
- **Blender Units**: Set Scene Units to **Metric** with Unit Scale **1.0** (Length: Meters).

> [!CAUTION]
> **CRITICAL: Mesh Coordinates MUST Be in Positive [0, 1]³ Space!**  
> `VoxelMesherBlocky` in the voxel engine generates rotation variants and collision shapes by rotating the source mesh around the unit cell center `(0.5, 0.5, 0.5)`.  
> - **Never center the mesh around (0, 0, 0)**: Centered geometry spanning `[-0.5, 0.5]³` renders half a block off-grid.
> - **Never export with negative Z space `[-1.0, 0.0]`**: In Blender, if the model extends toward negative Z or is exported with inverted Z, rotating the block in-game will shift the rendered block and collision mesh by **1 to 2 cells away from the ghost preview**!
> - Verify in Godot after import: `mesh.get_aabb()` MUST be `[P: (0.0, 0.0, 0.0), S: (1.0, 1.0, 1.0)]`.

### B. Visual Origin & Pivot Placement in Blender

For a 3D artist authoring a block, the simplest way to position the origin is by **visual reference**:

When you look directly at the **front** of your block (e.g. standing at the bottom of the stairs looking up the steps, or at the base of a ramp looking up the slope):

- **The Origin (Blender's orange dot) must be located at the REAR-RIGHT corner on the floor.**
- From that origin dot, the entire 1.0 m × 1.0 m × 1.0 m block body extends:
  - **Forward** (towards you)
  - **To your Left**
  - **Upward** from the floor

```
                    TOP (High Step / Top of Ramp)
                   +-----------------------+
                  /                       /|
                 /                       / |
                /                       /  |
               +-----------------------+   |
               |                       |   |
               |                       |   | 📍 ORIGIN DOT (0, 0, 0)
               |                       |   |   (Rear-Right Corner on Floor)
               |                       |   +
               |                       |  /
               |                       | /
               +-----------------------+/
             FRONT (Low Step / Entrance)
            ▲
      Looking from front
```

#### Step-by-Step in Blender:
1. In Edit Mode, position the object so that when viewing its front, its **rear-right-bottom corner** sits at the 3D Cursor / World Origin `(0, 0, 0)`.
2. The entire 1m³ geometry should sit in front of and to the left of the origin point, resting on the floor grid.
3. In Object Mode, press `Ctrl + A` → **Apply All Transforms** (or **Object → Set Origin → Origin to 3D Cursor**).
4. Verify that the orange Origin dot sits at the **rear-right corner on the floor**.

### C. Orientation & Facing Convention
Author non-symmetric shapes (e.g. wedges, stairs, slopes) in their **default unrotated orientation**:
- **Front / Low Edge**: `Z = 0.0`
- **Back / High Edge**: `Z = 1.0`
- **Bottom / Base**: `Y = 0.0`
- **Top**: `Y = 1.0`
- **Side Faces**: `X = 0.0` (Left) and `X = 1.0` (Right)

### D. Geometry & Normals
- **Face Normals**: Ensure all face normals point outward (`Shift + N` in Edit Mode).
- **UV Unwrapping**: Unwrap UVs cleanly into normalized `[0.0, 1.0]` UV space.
- **No Duplicate Vertices**: Merge by distance (`M` → **By Distance**) to remove overlapping vertices.

### E. Export Settings & File Formats
We recommend exporting as **GLTF / GLB (`.glb`)** or **Wavefront OBJ (`.obj`)**:

#### Exporting as GLTF/GLB (`.glb`):
1. **File Format**: `glTF Binary (.glb)`
2. **Transform**:
   - `+Y Up`
   - **Apply Modifiers**: Checked
3. **Include**: Selected Objects only

#### Exporting as OBJ (`.obj`):
1. **Forward**: `+Z Forward` (or ensure exported vertex lines `v x y z` have `z >= 0.0`)
2. **Up**: `Y Up`
3. **Scale**: `1.0`
4. **Triangulate Faces**: Optional (Godot automatically handles quad triangulation).

---

## 1.1 Guidelines for Non-Cubic Shapes (Wedges, Corners, Arcs, Stairs, Slabs)

While standard blocks are solid `1.0 m³` cubes, non-cubic blocks (wedges, slopes, stairs, corner blocks, arches, and half-slabs) have unique geometry and face-culling requirements.

### A. Cell Envelope & Vertex Snapping
- **`1.0 m³` Envelope**: Non-cubic meshes MUST still fit entirely inside the `1.0 m × 1.0 m × 1.0 m` bounding cube `[0, 1]³`.
- **Origin Alignment**: The Object Origin MUST remain at `(0, 0, 0)` (bottom-left-back corner).
- **Boundary Vertex Snapping**: Vertices that touch the cell boundaries MUST snap exactly to `0.0` or `1.0` on the corresponding axis plane:
  - Bottom vertices: `Y = 0.0`
  - Top vertices: `Y = 1.0`
  - Back vertices: `Z = 1.0`
  - Front vertices: `Z = 0.0`
  - Left / Right vertices: `X = 0.0` / `X = 1.0`
  *Snapping ensures seamless alignment without micro-gaps when non-cubic blocks meet standard full-cube walls.*

### B. Geometry Specifications per Shape Type

#### 1. Wedges / Ramps (`FULL_3D`)
- **Slope Orientation**: Low edge at `Z = 0.0` (`Y = 0.0`); High edge at `Z = 1.0` (`Y = 1.0`).
- **Side Faces**: Vertical triangular faces at `X = 0.0` and `X = 1.0`.
- **Bottom & Back**: Fully flat faces covering `Y = 0.0` and `Z = 1.0`.

#### 2. Stairs & Steps (`YAW_ONLY` or `FULL_3D`)
- **Step Footprint**:
  - Lower Step: `Y in [0.0, 0.5]`, `Z in [0.0, 0.5]`
  - Upper Step: `Y in [0.5, 1.0]`, `Z in [0.5, 1.0]`
- **Back & Bottom**: Fully flat faces at `Z = 1.0` and `Y = 0.0`.
- **Smooth Collision**: Keep riser and tread geometry clean (quads) so kinematic character step-up physics functions smoothly.

#### 3. Corner Slopes (`FULL_3D`)
- **Outer Corner Slope**: Slopes down toward two adjacent edges (`X = 0.0` and `Z = 0.0`), forming a pyramid-like corner.
- **Inner Corner Slope**: Valley slope joining two perpendicular wedge slopes.

#### 4. Arcs / Tunnels (`YAW_ONLY` or `FULL_3D`)
- **Arch Opening**: Vaulted opening aligned along the `Z`-axis (through-tunnel along `Z`).
- **Outer Bounds**: Surrounding top and side edges sit at `Y = 1.0`, `X = 0.0`, and `X = 1.0`.

#### 5. Slabs / Half-Blocks (`FULL_3D` or `NONE`)
- **Bottom Half-Slab**: Occupies `Y in [0.0, 0.5]`, `X in [0.0, 1.0]`, `Z in [0.0, 1.0]`.
- *Note*: With 3-axis rotation (`FULL_3D`), a single bottom half-slab mesh can be rotated in-game into a top slab or vertical side slab without creating separate assets.

### C. Neighbor Face Culling & Transparency Note
In Zylann's voxel mesher (`VoxelMesherBlocky`), adjacent opaque cubes cull touching faces to optimize rendering.
- Because non-cubic meshes leave parts of their `1 m³` cell open, `VoxelLibraryGenerator` sets model transparency/cull masks so that adjacent solid blocks do **not** mistakenly cull their visible faces when touching sloped or recessed sides of a non-cubic block.
- **Blender Rule**: Do NOT create interior faces inside the mesh (e.g. inside a hollow arch). Delete all internal, invisible geometry before exporting.

### D. Transparent Surfaces (Windows, Glass, Grates)

Transparency is already supported by the block pipeline: water sets `transparency_index = 1`,
`culls_neighbors_of_same_type = true` and a `custom_material` (see `data/blocks/water.tres`),
and `VoxelMesherBlocky` renders transparent surfaces in their own pass. A window is the same
mechanism plus a second material, because it has an opaque frame and a see-through pane.

**One block, two surfaces.** A voxel cell holds a single block, so the frame and the glass must
be one mesh with two material slots, not two blocks.

#### Blender
- Model the window as a single mesh inside the `[0, 1]` cell (all rules in 1.1A still apply).
- Give the object two material slots: `frame` and `glass`. Name them; the surface index in
  Godot follows slot order (`frame` = surface 0, `glass` = surface 1).
- Glass pane: either a thin closed slab (about 2 to 4 cm thick) or a double-sided quad. Use a slab
  if the pane should block movement or projectiles via collision.
- Keep the pane at mid-depth of the cell, not flush with a cell face. A flush pane gets culled
  by, or z-fights with, the neighbouring wall.
- Delete interior faces as usual. Do not leave a face between the frame and the pane where they touch.
- Only the material names matter on export. Colour and alpha set in Blender are replaced by the
  Godot material.
- Iron Bars and other grates do not need alpha. Model the bars as real geometry (cheap at 1 m and
  it avoids sorting problems). If a cutout texture is used instead, use `ALPHA_SCISSOR`, not blended alpha.

#### Godot
- Set `transparency_index > 0` on the `BlockDef` so opaque neighbours do not cull faces seen through the glass.
- Glass material: a `StandardMaterial3D` with `transparency = ALPHA`, a light tint, low roughness,
  and shadow casting off. Store it in `assets/materials/`.
- **Planned, does not exist yet:** `BlockDef.custom_materials: Array[Material]`, where index N maps
  to mesh surface N and a null entry keeps the default generated material. Today
  `tools/voxel_library_generator.gd` only sets `material_override_0` (from `custom_material`),
  which is enough for single-surface blocks like water but not for a frame plus glass. The generator
  must loop over the array and set `material_override_N` for each surface. Check `docs/TODO.md` and
  `docs/architecture/tech-debt.md` before adding it, and update this section when it lands.

#### Caveats
- Alpha-blended surfaces do not cast normal shadows, so leave shadow casting off on the glass.
- Overlapping transparent surfaces (glass next to water) can sort incorrectly. Set `render_priority`
  on the materials to fix it.
- Confirm in game that light passes through the window, since the block otherwise reads as solid
  to lighting.

---

## 2. Textures & Shaders

There is no dedicated `assets/blocks/` folder — custom-authored block meshes live in
`assets/custom_meshes/`, their textures in `assets/custom_images/`, and any purchased/
sourced texture packs under their own top-level folder (e.g. `assets/ambientcg/`),
per `docs/art.md`.

### A. Adding Textures
Pack the downloaded material with the PBR packer (see [Authoring PBR Textures](HOWTO-author-pbr-textures.md)) and assign the resulting `res://data/pbr/<id>.tres` to the def's `pbr`; an albedo-only set is fine.

### B. Texture Variations Shader (`texture_variation`)
To prevent large blocky surfaces (walls, ground) from looking like repeating grid tiles, `BlockDef` provides a `texture_variation` toggle:
- When `texture_variation = true`, `PbrMaterialFactory.variation(pbr)` builds the shader material with every map bound (missing maps are the neutral set's).
- The shader applies subtle per-voxel UV flipping and brightness offsets derived from world position, making seamless blocky surfaces look natural and organic.

---

## 3. Handling Rotations (No Manual Permutations Needed!)

You **DO NOT** need to author 24 separate mesh files in Blender for rotatable shapes!

*Xeno Frontier: Colony Defense* features an automated 3-axis rotation pipeline:
1. You export **1 base mesh** from Blender.
2. In the block's `BlockDef` resource, you set `rotation_mode`:
   - `NONE` (1 variant): Standard symmetric cubic blocks.
   - `YAW_ONLY` (4 variants): Horizontal-only rotation around Y-axis (stairs, logs, directional indicators).
   - `FULL_3D` (24 variants): 3-axis orthogonal rotation (wedges, corner slopes, diagonal ramps).
3. That's it — at startup `BlockLibrary` bakes the 4 or 24 `VoxelBlockyModelMesh`
   rotational variants itself and appends them to the voxel library. Every
   variant **shares your one mesh** and differs only in
   `mesh_ortho_rotation_index` (the mesher rotates geometry at bake time).
   No manual ID/slot allocation: variant indices are assigned after the base
   block table automatically, and placing a rotated block stores the matching
   variant index. Full mechanism: `docs/architecture/voxel-world.md`
   ("Rotation variant mechanism") and `docs/VOXEL-TOOL-NOTES.md`.

---

## 4. Step-by-Step Block Creation in Godot Editor

### Step 1: Place Mesh & Texture Assets
Save your exported `.glb` or `.obj` mesh file to `assets/custom_meshes/<block_id>.obj` or `assets/custom_meshes/<block_id>.glb`.

### Step 2: Create `BlockDef` Resource
1. In Godot's FileSystem dock, navigate to `res://data/blocks/`.
2. Right-click → **New Resource...** → select `BlockDef` (or create a file `data/blocks/<block_id>.tres` with script `res://data/blocks/block_def.gd`).
3. Configure the inspector properties:

| Property | Value Example | Notes |
|---|---|---|
| `id` | `"wedge_wood"` | Unique string key (matches filename). |
| `display_name` | `"Wooden Wedge"` | UI label in Map Editor & Build Menu. |
| `rotation_mode` | `FULL_3D` (`24`) | `NONE` (1), `YAW_ONLY` (4), or `FULL_3D` (24). Triggers automatic variant baking. |
| `scene` | `res://assets/custom_meshes/wedge_wood.glb` | *(Recommended)* Direct `.glb` scene — `BlockLibrary` extracts the base mesh automatically. |
| `mesh` | `res://assets/custom_meshes/wedge_wood.obj` | *(Alternative)* Unrotated base source mesh in `[0, 1]³` bounding box (variants are baked from this). |
| `pbr` | `res://data/pbr/wood_planks.tres` | PbrTextureSet (albedo required, normal and ORME optional). |
| `texture_variation` | `true` | Enables UV/brightness shader variation. |
| `hp` | `100` | Block durability. |
| `material_cost` | `[10 x wood_block]` | Crafting/building cost (Array of `ItemAmount`). |
| `is_fluid` | `false` | Marks non-solid fluids like water or lava. |
| `wading_speed_mult` | `1.0` | Locomotion multiplier for a body whose lower torso is inside this block (`0.0`-`1.0`). Only read for fluids; solids and air never slow anyone. Water uses `0.6`. |
| `collision_enabled` | `true` | Set `false` for non-solid blocks (water, tall grass). |
| `transparency_index` | `0` | `0` = opaque, `>0` = transparent (for `VoxelMesherBlocky` face culling). |
| `culls_neighbors_of_same_type` | `false` | When `true`, touching blocks of the same model cull their shared internal faces. |
| `custom_material` | `null` | Optional custom Material (e.g. animated water ShaderMaterial) overriding the standard generated material. |
| `fixed_index` | `-1` | Explicit base library index override (`> 0`) for guaranteed save-compatible index assignment across updates; leave `-1` for the default auto-assigned sequential index — there is no `type_id`/`base_library_id` field, `BlockLibrary` owns that mapping. |

### Step 3: Bake Voxel Library (`voxel_library.tres`)
1. In Godot's Script Editor, open `tools/bake_voxel_library.gd`.
2. Go to **File** → **Run** (or click **Run** on the EditorScript toolbar).
3. Confirm the Godot Output panel prints: `bake_voxel_library: wrote res://data/blocks/voxel_library.tres (N models)`.

*Why this step is required*: Game runtime dynamically scans `data/blocks/*.tres` and builds the library in memory, but Godot Editor viewports and `.tscn` map scenes (`subsystems/maps/map_template.tscn`, `data/maps/dev/map.tscn`) require `voxel_library.tres` baked on disk so block meshes render in the editor.

---

## 5. Verification & Map Editor Usage

### Testing Your Block in the Map Editor:
1. Open and run the Map Editor scene (`tools/map_editor/map_editor.tscn` or press `F6`).
2. Press `F2` to switch to **Block Mode**.
3. Select your new block in the **Block Palette** panel on the left.
4. Test **Unified Rotation Inputs**:
   - **Mouse Wheel Up / Down**: Rotate **±90°** along the active rotation axis.
   - **`R` Key**: Cycle the active rotation axis (**Y [Yaw] → X [Pitch] → Z [Roll] → Y [Yaw]**).
   - **3D Axis Visualizer**: A colored line through the preview center indicates the active axis (🟢 **Green** = Y, 🔴 **Red** = X, 🔵 **Blue** = Z).
   - **`Z` or `~` Key**: Reset rotation orientation to identity (`0`) and axis to **Y [Yaw]**.
5. Observe the `%OrientationLabel` in the HUD updating `Rot: #<index> [Y <deg>°, X <deg>°] | Axis: <axis> [R]`.
6. Click to place the rotated block into the terrain.
7. Test the **Eyedropper / Pick Tool**:
   - Press `I` or `Alt + LMB` / `MMB` on a placed block.
   - Verify that both the block type ID and the rotation index are correctly picked up by the brush.
8. Save (`Ctrl + S`) and reload the map to confirm full rotation persistence.

---

## 6. Save Compatibility: What Breaks Old Maps (and What Doesn't)

Maps store **raw voxel values = library model indices** (`map.sqlite`), so old
maps keep loading correctly only as long as the library's index layout stays
compatible with what was saved. `BlockLibrary` builds the layout as:
**base table** (0 = air, then all blocks in registry order — there is no terrain
block; natural ground is the smooth grid's `TerrainMaterialDef` vocabulary)
followed by a **variant appendix** (rotation variants of rotatable blocks, in
base-table order). The rules below follow from that layout.

> One-time breakage (2026-08-21): removing the blocky terrain block shifted
> every base index down by one. Authored map data stored no terrain-block
> cells, but older `map.sqlite`s (and `user://` save copies) may render stone
> cells as scrap, etc. — re-author affected maps or clear `user://maps`. No
> migration: pre-release, ~130 affected cells.

**Registry order is not raw alphabetical id sort.** `BlockLibrary._sort_block_defs_stably`
ranks every `BlockDef` by (in priority order): an explicit `fixed_index` (if `> 0`, wins
outright and pins that exact index); else its position in the hardcoded
`LEGACY_BLOCK_ORDER` list (the 13 blocks shipped as of the dual-voxel rewrite —
currently alphabetical by coincidence, not by rule); else a shared fallback rank, tie-broken
by `.tres` file path — so **any block not in `LEGACY_BLOCK_ORDER` and without a
`fixed_index` always sorts after every locked/fixed block**, regardless of how
its `id` compares alphabetically to them.

### Safe: adding rotation to a previously single-variant block

Old maps only contain **base** indices for that block (it couldn't rotate when
they were saved). Base indices never move when a def becomes rotatable, and the
base model *is* the rotation-0 variant — so every stored value resolves to the
same block, same orientation, same mesh. Existing maps load unchanged. Go
ahead and add `rotation_mode` to any existing block.

### Hazard: making an *earlier-ranked* block rotatable later

Variant indices in the appendix depend on **which** blocks are rotatable, appended
in base-index (i.e. registry-rank) order. If map A was saved with rotated `wood`
voxels (variant index 7, say) and you then make `metal` rotatable too — and `metal`
outranks `wood` (lower `LEGACY_BLOCK_ORDER` position, or a smaller `fixed_index`) —
metal's variants now occupy 7–9 and wood's shift to 10–12. Map A's stored `7`
silently renders as rotated **metal**. The voxels still render and collide (every
in-range value is a real model), but they are the wrong block. Rule: once maps with
rotated voxels of a block are in circulation, don't make any block that outranks
it rotatable too (and re-save those maps only in the same content configuration
they were painted in).

### Dangerous: *removing* rotation from a block

If a map was saved while the block was rotatable, it may store variant indices
from the larger library. Removing the rotation shrinks the library, and stored
values beyond the new model count render **nothing** — invisible, non-colliding
voxels that still persist across saves (the same failure class as the
2026-08-20 stamping bug, but caused by content drift instead of packed values).
Rule: never un-mark `rotation_mode` on a block whose rotated voxels may exist
in saved maps.

### Safe by design: adding a brand-new block type

A new `BlockDef` is never in `LEGACY_BLOCK_ORDER` and (unless you set `fixed_index`)
always falls back to the shared rank — which sorts after every locked/fixed block
regardless of the new block's `id`. This means, unlike the pre-hardening scheme,
**adding a new block never shifts any existing block's base index**, no matter
what its id is (e.g. adding `id = "aardvark"` today still lands after `wood_stairs`,
not before `full_block_wood`). The one thing that *is* still filename-order-dependent:
two or more new (non-legacy, no `fixed_index`) blocks added together are ordered
relative to **each other** by `.tres` file path — set an explicit `fixed_index` on
each if you need a guaranteed relative order regardless of filename.

### Quick reference

| Change | Old maps… |
|---|---|
| Add `rotation_mode` to an existing block | load unchanged — safe |
| Make a lower-ranked (earlier) block rotatable after another block's rotated voxels are saved | re-interpret its variant indices as the wrong block |
| Remove `rotation_mode` from a block | may contain out-of-range values → invisible voxels |
| Add any new block (no `fixed_index`, not in `LEGACY_BLOCK_ORDER`) | load unchanged — safe, regardless of `id` |
| Add two+ new blocks together without `fixed_index` | their relative order follows `.tres` file path, not `id` |

If these rules ever become real friction, the durable fix is a per-map library
manifest (record the index layout a map was saved against and remap on load) —
see `docs/architecture/tech-debt.md` before designing one. The full layout
convention lives in `docs/architecture/voxel-world.md` (BlockLibrary) and
`docs/VOXEL-TOOL-NOTES.md`.
