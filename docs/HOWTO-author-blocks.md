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
3. At engine/tool startup, `VoxelLibraryGenerator.register_block_in_library()` automatically generates the 4 or 24 `VoxelBlockyModelMesh` rotational variants programmatically and registers them into Zylann's `VoxelBlockyLibrary`.

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
| `type_id` | `10` | Unique 11-bit integer voxel block type ID (`0..2047`). |
| `base_library_id` | `240` | Base Model ID offset in `VoxelBlockyLibrary` (allocate 24 slots for `FULL_3D`). |
| `rotation_mode` | `FULL_3D` (`24`) | `NONE` (1), `YAW_ONLY` (4), or `FULL_3D` (24). |
| `base_mesh` | `res://assets/blocks/wedge_wood.obj` | Unrotated base source mesh. |
| `texture` | `res://assets/blocks/wood_albedo.png` | Albedo texture map. |
| `texture_variation` | `true` | Enables UV/brightness shader variation. |
| `hp` | `100` | Block durability. |
| `material_cost` | `[10 x wood_block]` | Crafting/building cost (Array of `ItemAmount`). |

---

## 5. Verification & Map Editor Usage

### Testing Your Block in the Map Editor:
1. Open and run the Map Editor scene (`tools/map_editor/map_editor.tscn` or press `F6`).
2. Press `F2` to switch to **Block Mode**.
3. Select your new block in the **Block Palette** panel on the left.
4. Test **3-Axis Rotation Hotkeys**:
   - `R`: Cycle **Yaw** ($Y$-axis, horizontal turn).
   - `Shift + R`: Cycle **Pitch** ($X$-axis, vertical tilt).
   - `Ctrl + R` / `Cmd + R`: Cycle **Roll** ($Z$-axis, lateral twist).
   - `Z` / `~`: Reset rotation to default (`0`).
5. Observe the `%OrientationLabel` in the HUD updating `Rot: #<index> [Yaw <deg>°, Pitch <deg>°]`.
6. Click to place the rotated block into the terrain.
7. Test the **Eyedropper / Pick Tool**:
   - Press `I` or `Alt + LMB` / `MMB` on a placed block.
   - Verify that both the block type ID and the rotation index are correctly picked up by the brush.
8. Save (`Ctrl + S`) and reload the map to confirm full rotation persistence.
