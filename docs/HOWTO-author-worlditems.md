# How To: Author World Item Meshes

> End-to-end guide for modeling, scaling, exporting, and extracting 3D World Item meshes for `ItemDef` resources in *Vek: Holdout*.
> Covers Blender sizing constraints (0.4 m max dimension), pivot/origin alignment, glTF `.glb` export settings, and extracting standalone `.res` `Mesh` resources via Godot's Import dock.
> 
> **Prerequisites:** Basic knowledge of 3D modeling in Blender and Godot `.tres` Resource editing.
> Read [`docs/architecture/inventory.md`](architecture/inventory.md) and `data/items/item_def.gd` for subsystem details.

---

## 1. Blender Modeling Guidelines & Sizing Rules

World items exist physically in the 3D voxel environment when dropped on the ground or placed in containers. To ensure consistent visual scale across all items (ingots, tools, springs, flasks, resources):

### A. Maximum Dimension Constraint (0.4 m)

- **Bounding Box Size**: The **largest dimension** (X, Y, or Z) of the 3D mesh MUST be at most **0.4 meters** (`0.4 m` / 40 cm).
- **Blender Units**: Set Scene Units to **Metric** with Unit Scale **1.0** (Length: Meters).
- **Bounding Check**: In Blender's Item Sidebar (`N` panel), check **Dimensions**. Ensure `max(Dimensions.x, Dimensions.y, Dimensions.z) <= 0.4 m`.

> [!IMPORTANT]
> **Why 0.4 m Max Scale?**  
> Voxel grid blocks in *Vek: Holdout* are 1.0 m³ units. Restricting dropped item models to a maximum size of 0.4 m prevents items from clipping into adjacent voxel walls, floating weirdly, or cluttering the ground when multiple items drop in the same block space.

### B. Pivot & Origin Placement

- **Origin Position**: Place the mesh origin (Blender's orange dot) at the **bottom-center** of the object (`Z = 0` / floor level).
- **Ground Alignment**: Position the lowest vertices exactly at `Z = 0.0` so the item rests cleanly on voxel surfaces without floating or sinking.
- **Apply Scale & Rotation**: Before exporting, select the object in Object Mode and press `Ctrl + A` → **Apply All Transforms** (or **Scale** and **Rotation**).

### C. Normals & Shading (Blender 4.1+)

- **Clear Custom Normals**: If importing meshes from external asset packs (FBX/OBJ), first go to **Object Data Properties** (green triangle) → **Geometry Data** → click **Clear Custom Normals Data**. Locked custom split normals will block normal modifiers from working.
- **Smooth by Angle**: In Blender 4.1+, the old Auto Smooth checkbox is replaced with the **Smooth by Angle** modifier.
  - In Object Mode, right-click the mesh → **Shade Auto Smooth** (or add modifier **Normals → Smooth by Angle** with angle `30°` or `45°`).
- **Weighted Normal Modifier**: Add **Normals → Weighted Normal** below *Smooth by Angle* in the modifier stack:
  - Check **Keep Sharp**.
  - Set **Weight** to `50` or `100`.
  - *Why:* Keeps large flat planar faces flat while smoothing transition edges cleanly without polygonal shading artifacts.

---

## 2. Advanced Material Realism & Anti-Cartoony Workflow (Blender Shader)

To eliminate the "plastic toy" low-poly look without adding geometry or runtime performance overhead, use procedural roughness and baked bevel normals in Blender's Shader Editor.

### A. Rounded Edges via Bevel Node (Fake Bevels)

Sharp polygonal edges destroy realism. The Bevel node simulates rounded edges in lighting highlights.

1. In the **Shader Editor** (using Cycles), press `Shift + A` → add **Input → Bevel**.
2. Set **Samples** to `8` or `16`.
3. Set **Radius** to `0.015 m` (adjust between `0.005 m` and `0.025 m` based on item scale).
4. Connect **`Bevel.Normal` → `Principled BSDF.Normal`**.

### B. Procedural Roughness Variation (Killing the Plastic Look)

Uniform roughness creates a toy-like appearance. Real surfaces have micro-scuffs and dirt in crevices.

#### 1. Micro-Noise Layer (Surface Scuffs & Imperfections)

- **Texture Coordinate** (`Object` output) → **Mapping** (`Vector`) → **Noise Texture** (`Vector`).
- **Noise Texture Settings**: `Scale = 20.0`, `Detail = 4.0`, `Roughness = 0.6`, `Distortion = 0.2`.
- **Tip (Streaking the Noise)**: By default, noise forms isotropic (circular) spots. In the **Mapping** node, use non-uniform **Scale** values (e.g. `X = 0.2, Y = 2.0, Z = 1.0` or `X = 5.0, Y = 0.2, Z = 1.0`) to heavily **streak** the noise along one axis. This simulates directional grain for wood, linear tool marks on machined parts, or brushed metal scratches.
- Connect `Noise Texture.Factor` → **Color Ramp (Top)**:
  - **Left Stop (Dark Grey)**: Value `0.45` at Pos `0.0`.
  - **Right Stop (Light Grey)**: Value `0.70` at Pos `1.0`.
  - *(Crucial: Avoid pure 0.0 black or 1.0 white stops so roughness stays within realistic PBR bounds).*

#### 2. Crevice Dirt Layer (Ambient Occlusion)

- Add **Input → Ambient Occlusion**:
  - Check **Only Local** (prevents external objects from casting dirt).
  - Set **Distance**: `0.2 m` to `0.5 m`, **Samples**: `16`.
- Connect `Ambient Occlusion.Color` → **Color Ramp (Bottom)**:
  - **The "Far-Right Pinch" for Shallow Crevices**: Shallow low-poly notches and cutouts produce subtle occlusion values (e.g. 0.85 vs 1.0 open air). If the ramp handles are at default positions, the mesh will look all one flat grey color.
  - Drag both handles toward the **far right** to heavily contrast shallow crevices:
    - **Black Stop**: Pos `0.75` to `0.85`.
    - **White Stop**: Pos `0.90` to `0.95`.
  - Preview with `Ctrl + Shift + Click` in Cycles Rendered mode until the notch/depression turns crisp white against a black body.

#### 3. Combining Layers via Mix Color

- Press `Shift + A` → **Color → Mix Color**:
  - Set blend mode to **`Mix`** (or **`Screen`**).
  - **Socket A (top)**: Connect Top Color Ramp (Micro-Noise).
  - **Socket B (bottom)**: Connect Bottom Color Ramp (AO Crevice Dirt).
  - **Factor**: Set to **`0.2` to `0.3`** (DO NOT leave at 1.0 or use pure `Add`, as high values or additions saturate the roughness to 1.0, flattening out all noise into chalk).
- Connect **`Mix Color.Result` → `Principled BSDF.Roughness`**.

```
[ Noise Texture ] ──────────> [ Color Ramp (0.45 to 0.70 grey) ] ────> Socket A \
                                                                                  [ Mix Color (Factor: 0.25) ] ───> [ Principled BSDF ]
[ Ambient Occlusion (Local) ] > [ Color Ramp (Inverted / Tight) ] ───> Socket B /                                   (Roughness)
```

### C. Procedural Albedo / Color Variation (Breaking Flat Colors)

Flat solid colors make assets look like untextured plastic. Adding subtle value and hue variation directly from the noise texture gives organic depth.

#### 1. Directional Grain (Mapping Node Scale)

- Real-world materials like wood, fabric, or brushed metal have directional grain.
- In the **Mapping** node, change the **Scale** axes (e.g. `X = 0.2`, `Y = 3.0`, `Z = 1.0`) to stretch the noise into directional wood grain instead of uniform spherical splotches.

#### 2. Color Ramp for Base Color

- Duplicate the Color Ramp (`Shift + D`) and connect `Noise Texture.Factor` → new `Color Ramp.Factor`.
- **Left Stop**: Dark base tone (e.g. dark weathered brown `#4a3525`).
- **Right Stop**: Slightly lighter warm tone (e.g. warm wood brown `#6b4f38`).
- Connect this Color Ramp output directly into **`Principled BSDF.Base Color`**.

#### 3. (Optional) Crevice Cavity Darkening

- To naturally darken deep cutouts, joints, and slits:
- Add a **Color → Mix Color** node set to **`Multiply`**:
  - **Socket A**: Wood Color Ramp output.
  - **Socket B**: Dark cavity dirt color (dark brown/black).
  - **Factor**: Bottom Ambient Occlusion Color Ramp output.
  - Connect **Result → `Principled BSDF.Base Color`**.

```
[ Noise Texture ] ──────────> [ Color Ramp (Dark to Light Wood) ] ───> Socket A \
                                                                                  [ Mix Color (Multiply) ] ───> [ Principled BSDF ]
[ Ambient Occlusion (Local) ] > [ Color Ramp (Cavity Mask) ] ────────> Factor   /                               (Base Color)
```

### D. Common Shader Pitfalls & Troubleshooting Checklist

- [ ] **Plank/Mesh looks solid white?** Check where `Mix (Result)` is plugged. It must go into **`Roughness`**, NOT **`Base Color`**.
- [ ] **AO mask is all one uniform grey color?** The crevice occlusion is subtle. Slide both Color Ramp stops to the **far right** (`0.75 - 0.95`) to amplify the contrast so notches and depressions snap into view. Ensure you are previewing in **Cycles Rendered mode** (`Z → Rendered`), as Material Preview does not evaluate raytraced AO.
- [ ] **Roughness variation disappears / looks flat?**
  - Check if `Result` was accidentally wired to **`Metallic`** instead of **`Roughness`** (ensure `Metallic` is `0.0` for non-metals).
  - Check the **Mix Factor**: If using `Add` or `Mix` with Factor `1.0`, the values add up to > 1.0 and wash out the noise. Lower the factor to `0.2 - 0.3`.
- [ ] **Bevel edge highlights missing?** Ensure `Bevel (Normal)` is plugged into `Principled BSDF (Normal)`.
- [ ] **Can't see specular highlights in viewport?** Switch Viewport Shading to **Material Preview** (3rd sphere) and rotate the HDRI environment light in the viewport dropdown. Solid shading disables specular response.

---

## 3. UV Unwrapping & Baking PBR Textures (Blender)

To transfer procedural materials, Bevel edge highlights, and surface details into Godot at zero runtime geometry cost, bake them into standard PBR texture maps.

### A. UV Unwrapping

Before baking, the mesh must have clean, non-overlapping UV coordinates:

1. Select your object and press `Tab` into **Edit Mode**.
2. Select all faces (`A`).
3. Press `U` → **Smart UV Project**:
   - **Angle Limit**: `66°`
   - **Island Margin**: `0.005` (prevents adjacent UV islands from bleeding color/normals into each other).
4. Press `Tab` to return to **Object Mode**.

### B. Baking the Normal Map (Capturing Bevel Highlights)

Blender bakes the active material passes onto whichever `Image Texture` node is currently **selected** in the Shader Editor.

1. In the **Shader Editor**, press `Shift + A` → add **Texture → Image Texture**.
2. Click **New** on the node:
   - **Name**: `Bake_Normal`
   - **Width / Height**: `1024 x 1024` (or `2048 x 2048` for hero props)
   - **32-bit Float**: Unchecked
   - **Color Space**: Change from `sRGB` to **`Non-Color`** *(Crucial: Normal maps store raw vector directions, not color)*.
3. Leave this node **floating and disconnected** in the graph, but make sure it is **selected** (has a white outline around it).
4. Go to **Render Properties** (Camera icon):
   - **Render Engine**: `Cycles`.
   - **Bake** section:
     - **Bake Type**: `Normal`
     - **Space**: `Tangent`
     - **Swizzle**: `+X`, `+Y`, `+Z` (OpenGL format, fully compatible with Godot).
5. Click the **Bake** button.
6. Open the **Image Editor** panel, select `Bake_Normal` from the dropdown. You will see a periwinkle-blue normal map with smooth pink/cyan bevel curves along all edges.
7. Click **Image → Save As...** → save as **`T_<item_id>_Normal.png`** (or in your Godot `assets/items/` folder).

### C. Baking the Albedo Map (Base Color & Cavity Grime)

Bakes pure surface color and procedural wood grain without capturing scene lights or shadows.

1. In the **Shader Editor**, add a new **Image Texture** node:
   - Click **New** → Name: `Bake_Albedo`, Resolution: `1024 x 1024`, Color Space: **`sRGB`**.
2. Click the node so it is **selected (white outline)**.
3. In **Render Properties → Bake**:
   - **Bake Type**: `Diffuse`
   - Under **Influence**: Uncheck *Direct* and *Indirect*, leave **ONLY Color checked**.
4. Click **Bake**.
5. In the **Image Editor**, select `Bake_Albedo` → **Image → Save As...** → `T_<item_id>_Albedo.png`.

### D. Baking the Roughness Map

1. In the **Shader Editor**, add a new **Image Texture** node:
   - Click **New** → Name: `Bake_Roughness`, Resolution: `1024 x 1024`, Color Space: **`Non-Color`**.
2. Click the node so it is **selected (white outline)**.
3. In **Render Properties → Bake**:
   - **Bake Type**: `Roughness`.
4. Click **Bake**.
5. In the **Image Editor**, select `Bake_Roughness` → **Image → Save As...** → `temp_roughness.png`.

### E. Baking the Ambient Occlusion (AO) Map

1. In the **Shader Editor**, add a new **Image Texture** node:
   - Click **New** → Name: `Bake_AO`, Resolution: `1024 x 1024`, Color Space: **`Non-Color`**.
2. Click the node so it is **selected (white outline)**.
3. In **Render Properties → Bake**:
   - **Bake Type**: `Ambient Occlusion`.
4. Click **Bake**.
5. In the **Image Editor**, select `Bake_AO` → **Image → Save As...** → `temp_ao.png`.

### F. Packing the ORM Texture (Blender Compositor)

Godot uses packed ORM textures to minimize GPU texture samplers:

* **Red Channel**: **O**cclusion (AO)
* **Green Channel**: **R**oughness
* **Blue Channel**: **M**etallic (`0.0` / black for non-metals)

To pack into a single texture:

1. Switch to Blender's **Compositing** workspace:
   - In **Blender 4.2+**: Click the **`+ New`** button in the top header bar of the Compositor editor.
   - In **Blender 4.1 and older**: Check the **Use Nodes** checkbox in the top header.
2. Add two **Input → Image** nodes:
   - Open `temp_ao.png` in the first node.
   - Open `temp_roughness.png` in the second node.
3. Add a **Color → Combine Color** node (Mode: `RGB`):
   - Connect `temp_ao.png (Image)` → **Red**.
   - Connect `temp_roughness.png (Image)` → **Green**.
   - Leave **Blue** at `0.0` (or plug in a baked metallic texture if metal).
4. Connect **Combine Color (Image)** → both **`Group Output` (Image)** (or `Composite` in older versions) AND **`Viewer` (Image)**. (Disconnect the `Render Layers` node).
5. Press **`F12`** (or top menu: *Render → Render Image*).
6. In the resulting Image Editor window, click **Image → Save As...**:
   - In the right sidebar under **Color Management**: Click **`Override`** (next to *Follow Scene*).
   - Change **`View`** from `AgX` to **`Raw`** (or `Standard`).
   - *(Crucial: Prevents Blender's AgX film tonemapper from bending raw mathematical roughness and AO data).*
   - Save as **`T_<item_id>_ORM.png`**.

---

## 4. Exporting to `.glb` Format

Godot requires PBR materials and 3D scenes to be exported in **glTF 2.0 Binary (`.glb`)** format. Legacy formats like `.obj` do NOT preserve PBR metallic or roughness settings.

### Export Steps in Blender:

1. Select your low-poly item model in Object Mode.
2. Go to **File → Export → glTF 2.0 (.glb)**.
3. In the Export settings panel:
   - **Format**: `glTF Binary (.glb)`
   - **Include → Limit to**: `Selected Objects` (checked)
   - **Transform → +Y Up**: Checked
   - **Geometry → Apply Modifiers**: Checked
4. Save the `.glb` file into your project directory (e.g., `assets/items/<item_id>.glb`).

---

## 5. Assigning the 3D Asset to `ItemDef`

`ItemDef` supports two ways to specify world visuals:
1. **Direct `.glb` Scene (`scene`) — Recommended**: Assign the imported `.glb` file directly to the **`scene`** property on `ItemDef`. No mesh extraction is required, and Godot preserves all embedded hierarchy and materials automatically.
2. **Standalone Mesh (`mesh`) — Alternative**: Assign an extracted `.mesh` / `.res` or primitive `Mesh` to the **`mesh`** property.

### Option 1: Direct `.glb` Scene Assignment (Recommended)

1. Open your target item definition resource in `data/items/<item_id>.tres` (e.g. `data/items/wooden_stake.tres`).
2. Drag the imported **`<item_id>.glb`** file directly into the **`scene`** property field of the `ItemDef` inspector.
3. *(Optional)* Adjust **`visual_scale`** (e.g. `Vector3(0.5, 0.5, 0.5)`) if the item needs scaling.
4. Save the `.tres` file.

### Option 2: Extracting a Standalone `.res` Mesh Resource (Alternative)

If using `mesh` instead of `scene`:
1. In Godot's **FileSystem dock**, select the imported `.glb` file.
2. Open the **Import tab** (top-left panel next to the Scene tab).
3. Expand the **Meshes** section, set **Save to File** to **Enabled**, and choose a destination (e.g. `res://assets/items/mesh_<item_id>.res`).
4. Click **Reimport**.
5. Drag the generated `.res` file into the **`mesh`** property of your `ItemDef` resource.

### B. Configuring the PBR Material with Baked Textures

In Godot, open the mesh's material (or create a `StandardMaterial3D` / `ORMMaterial3D`):

1. **Albedo**:
   - Assign **`T_<item_id>_Albedo.png`** to `Albedo → Texture`.
2. **Normal Map**:
   - Enable **Normal Map** → Assign **`T_<item_id>_Normal.png`** (Depth: `1.0`).
3. **ORM Texture (AO, Roughness, Metallic)**:
   - If using `StandardMaterial3D`:
     - **Roughness**: Assign **`T_<item_id>_ORM.png`** (Channel: **Green**).
     - **Metallic**: Assign **`T_<item_id>_ORM.png`** (Channel: **Blue**).
     - **Ambient Occlusion**: Enable AO → Assign **`T_<item_id>_ORM.png`** (Channel: **Red**, Light Affect: `0.5` to `0.8`).
   - If using `ORMMaterial3D`:
     - Assign **`T_<item_id>_ORM.png`** directly to the **ORM Texture** slot.

The item is now fully registered with its custom low-poly PBR 3D mesh for world drops, colony hauling, and inventory visuals!
