# How To: Author a Voxel Block

> End-to-end guide for modeling, texturing, configuring, and registering new voxel block types in *Vek: Holdout*.
> Covers Blender mesh sizing, origin placement, export settings, texture variation shaders, 3-axis rotation configuration, and registering blocks into the Map Editor and Voxel Engine.
>
> **Prerequisites:** Basic knowledge of Blender 3D modeling and Godot `.tres` Resource creation.
> Read [`docs/architecture/voxel-world.md`](architecture/voxel-world.md) and [`docs/architecture/data-schemas.md`](architecture/data-schemas.md) for subsystem details.

---

## 1. Blender Modeling Guidelines & Requirements

Voxel blocks in *Vek: Holdout* are discrete 1-meter cubic units rendered by Zylann's blocky voxel mesher (`VoxelMesherBlocky`). To ensure clean face-stitching and alignment across chunk boundaries, every authored 3D mesh MUST adhere strictly to the following rules:

### A. Block Sizing & Scale
- **Dimensions**: Exactly **1.0 m × 1.0 m × 1.0 m**.
- **Bounding Box**: The mesh geometry must span from `(0, 0, 0)` to `(1, 1, 1)` in 3D space.
- **Blender Units**: Set Scene Units to **Metric** with Unit Scale **1.0** (Length: Meters).

> [!IMPORTANT]
> **Do NOT center the mesh at (0, 0, 0)!**  
> In Godot's voxel coordinate convention, cell origins sit at the minimum corner. A centered mesh spanning `(-0.5, -0.5, -0.5) → (0.5, 0.5, 0.5)` will render shifted by half a block. Always align the bottom-left-back vertex/corner to `(0, 0, 0)`.

### B. Origin Positioning
- Place the Object Origin at **`(0.0, 0.0, 0.0)`** (the minimum corner).
- In Blender:
  1. Move the 3D Cursor to World Origin (`Shift + C` or `Shift + S` → **Cursor to World Origin**).
  2. Select your mesh object in Object Mode.
  3. Go to **Object → Set Origin → Origin to 3D Cursor**.

### C. Orientation & Facing Convention
- Author non-symmetric shapes (e.g. wedges, stairs, slopes) in their **default unrotated orientation**:
  - **Front/Facing Direction**: `+Z` (Forward)
  - **Top/Up Direction**: `+Y` (Up)
  - **Side Direction**: `+X` (Right)

### D. Geometry & Normals
- **Face Normals**: Ensure all face normals point outward (`Shift + N` in Edit Mode).
- **UV Unwrapping**: Unwrap UVs cleanly into normalized `[0.0, 1.0]` UV space.
- **No Duplicate Vertices**: Merge by distance (`M` → **By Distance**) to remove overlapping vertices.

### E. Export Settings & File Formats
We recommend exporting as **GLTF / GLB (`.glb`)** or **Wavefront OBJ (`.obj`)**:

#### Exporting as GLTF/GLB (`.glb`):
1. **File Format**: `gTF Binary (.glb)`
2. **Transform**:
   - `+Y` Up
   - **Apply Modifiers**: Checked
3. **Include**: Selected Objects only

#### Exporting as OBJ (`.obj`):
1. **Forward**: `-Z Forward`
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
| `base_mesh` | `res://assets/blocks/wedge_wood.obj` | Unrotated base source mesh variants are baked from (falls back to `mesh`). |
| `texture` | `res://assets/blocks/wood_albedo.png` | Albedo texture map. |
| `texture_variation` | `true` | Enables UV/brightness shader variation. |
| `hp` | `100` | Block durability. |
| `material_cost` | `[10 x wood_block]` | Crafting/building cost (Array of `ItemAmount`). |
| `type_id` / `base_library_id` | *(leave defaults)* | Informational fields — library indices are assigned automatically by `BlockLibrary` at startup; you never allocate them. |

---

## 5. Verification & Map Editor Usage

### Testing Your Block in the Map Editor:
1. Open and run the Map Editor scene (`tools/map_editor/map_editor.tscn` or press `F6`).
2. Press `F2` to switch to **Block Mode**.
3. Select your new block in the **Block Palette** panel on the left.
4. Test **3-Axis Rotation Hotkeys**:
   - `R`: Cycle **Yaw** (`Y`-axis, horizontal turn).
   - `Shift + R`: Cycle **Pitch** (`X`-axis, vertical tilt).
   - `Ctrl + R` / `Cmd + R`: Cycle **Roll** (`Z`-axis, lateral twist).
   - `Z` / `~`: Reset rotation to default (`0`).
5. Observe the `%OrientationLabel` in the HUD updating `Rot: #<index> [Yaw <deg>°, Pitch <deg>°]`.
6. Click to place the rotated block into the terrain.
7. Test the **Eyedropper / Pick Tool**:
   - Press `I` or `Alt + LMB` / `MMB` on a placed block.
   - Verify that both the block type ID and the rotation index are correctly picked up by the brush.
8. Save (`Ctrl + S`) and reload the map to confirm full rotation persistence.
