# How To: Author a Voxel Block

> End-to-end guide for modeling, texturing, configuring, and registering new voxel block types in *Vek: Holdout*.
> Covers Blender mesh sizing, origin placement, export settings, texture variation shaders, 3-axis rotation configuration, and registering blocks into the Map Editor and Voxel Engine.
>
> **Prerequisites:** Basic knowledge of Blender 3D modeling and Godot `.tres` Resource creation.
> Read [`docs/architecture/voxel-world.md`](architecture/voxel-world.md) and [`docs/architecture/data-schemas.md`](architecture/data-schemas.md) for subsystem details.

---

## 1. Blender Modeling Guidelines & Requirements

Voxel blocks in *Vek: Holdout* are discrete 1-meter cubic units rendered by Zylann's blocky voxel mesher (`VoxelMesherBlocky`). To ensure clean face-stitching and alignment across chunk boundaries, every authored 3D mesh MUST adhere strictly to the following rules:

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

---

## 2. Textures & Shaders

Block textures are stored in `assets/blocks/` (or `assets/art/`).

### A. Adding Textures
1. Import your texture file (e.g., `wood_wedge_albedo.png`) into `assets/blocks/`.
2. Ensure Import Settings use **Lossless** or **VRAM Uncompressed** for crisp voxel textures.

### B. Texture Variations Shader (`texture_variation`)
To prevent large blocky surfaces (walls, ground) from looking like repeating grid tiles, `BlockDef` provides a `texture_variation` toggle:
- When `texture_variation = true`, `BlockLibrary` assigns `res://assets/blocks/block_shader.gdshader` instead of a plain `StandardMaterial3D`.
- The shader applies subtle per-voxel UV flipping and brightness offsets derived from world position, making seamless blocky surfaces look natural and organic.

---

## 3. Handling Rotations (No Manual Permutations Needed!)

You **DO NOT** need to author 24 separate mesh files in Blender for rotatable shapes!

*Vek: Holdout* features an automated 3-axis rotation pipeline:
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
Save your exported `.glb` or `.obj` mesh file to `assets/blocks/<block_id>.obj` or `assets/blocks/<block_id>.glb`.

### Step 2: Create `BlockDef` Resource
1. In Godot's FileSystem dock, navigate to `res://data/blocks/`.
2. Right-click → **New Resource...** → select `BlockDef` (or create a file `data/blocks/<block_id>.tres` with script `res://data/blocks/block_def.gd`).
3. Configure the inspector properties:

| Property | Value Example | Notes |
|---|---|---|
| `id` | `"wedge_wood"` | Unique string key (matches filename). |
| `display_name` | `"Wooden Wedge"` | UI label in Map Editor & Build Menu. |
| `rotation_mode` | `FULL_3D` (`24`) | `NONE` (1), `YAW_ONLY` (4), or `FULL_3D` (24). Triggers automatic variant baking. |
| `mesh` | `res://assets/blocks/wedge_wood.obj` | Unrotated base source mesh in `[0, 1]³` bounding box (variants are baked from this). |
| `texture` | `res://assets/blocks/wood_albedo.png` | Albedo texture map. |
| `texture_variation` | `true` | Enables UV/brightness shader variation. |
| `hp` | `100` | Block durability. |
| `material_cost` | `[10 x wood_block]` | Crafting/building cost (Array of `ItemAmount`). |
| `type_id` / `base_library_id` | *(leave defaults)* | Informational fields — library indices are assigned automatically by `BlockLibrary` at startup; you never allocate them. |

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
**base table** (0 = air, 1 = terrain, remaining blocks alphabetically) followed
by a **variant appendix** (rotation variants of rotatable blocks, in base-table
order). The rules below follow from that layout.

### Safe: adding rotation to a previously single-variant block

Old maps only contain **base** indices for that block (it couldn't rotate when
they were saved). Base indices never move when a def becomes rotatable, and the
base model *is* the rotation-0 variant — so every stored value resolves to the
same block, same orientation, same mesh. Existing maps load unchanged. Go
ahead and add `rotation_mode` to any existing block.

### Hazard: making an *earlier-sorting* block rotatable later

Variant indices in the appendix depend on **which** blocks are rotatable. If
map A was saved with rotated `wood` voxels (variant index 7, say) and you then
make `metal` rotatable too, `metal` sorts before `wood` — metal's variants now
occupy 7–9 and wood's shift to 10–12. Map A's stored `7` silently renders as
rotated **metal**. The voxels still render and collide (every in-range value is
a real model), but they are the wrong block. Rule: once maps with rotated
voxels of a block are in circulation, don't make any *alphabetically earlier*
block rotatable (and re-save those maps only in the same content configuration
they were painted in).

### Dangerous: *removing* rotation from a block

If a map was saved while the block was rotatable, it may store variant indices
from the larger library. Removing the rotation shrinks the library, and stored
values beyond the new model count render **nothing** — invisible, non-colliding
voxels that still persist across saves (the same failure class as the
2026-08-20 stamping bug, but caused by content drift instead of packed values).
Rule: never un-mark `rotation_mode` on a block whose rotated voxels may exist
in saved maps.

### Conditional: adding a new block type

The base table is alphabetical (after air and terrain). A new `BlockDef` whose
id sorts **after every existing one** (currently: after `wood` — e.g. `zinc`)
is appended and is fully safe. One that sorts **before** an existing block
(`brick` < `metal`) shifts that block's base index — every saved voxel of it
in old maps then misidentifies (wrong block, still renders). Rule: **new block
ids must sort alphabetically after all existing ids**.

### Quick reference

| Change | Old maps… |
|---|---|
| Add `rotation_mode` to an existing block | load unchanged — safe |
| Make an earlier-sorting block rotatable (after rotated saves exist) | re-interpret its variant indices as the wrong block |
| Remove `rotation_mode` from a block | may contain out-of-range values → invisible voxels |
| Add a block id sorting after `wood` | load unchanged — safe |
| Add a block id sorting before an existing block | shift that block's indices → wrong block |

If these rules ever become real friction, the durable fix is a per-map library
manifest (record the index layout a map was saved against and remap on load) —
see `docs/architecture/tech-debt.md` before designing one. The full layout
convention lives in `docs/architecture/voxel-world.md` (BlockLibrary) and
`docs/VOXEL-TOOL-NOTES.md`.
