# How To: Author Wearable Gear Models in Blender

> Comprehensive authoring guide for modeling, rigging, scaling, orienting, exporting, and integrating 3D wearable equipment (helmets, armor, shirts, pants, boots, and accessories) for *Xeno Frontier: Colony Defense*.
> Covers both **Rigid Gear** (helmets, pauldrons, backpacks, boots) and **Skinned Garments** (deformable clothing), glTF export settings, Godot humanoid BoneMap retargeting, and `ItemDef` / `WearableParams` resource configuration.
>
> **Prerequisites:** Blender 4.x+, basic Godot resource editing, and familiarity with [Equipment Architecture](architecture/equipment.md) and [Data Schemas](architecture/data-schemas.md).

---

## 1. Overview & Pipeline Philosophy

*Xeno Frontier* supports two distinct wearable visualization modes through `EquipmentVisualizer`:

```
                             [ Equipped ItemDef ]
                                      │
                         Is item.is_wearable()?
                                      │
                   ┌──────────────────┴──────────────────┐
                   ▼                                     ▼
        [ Path A: Rigid Parts ]               [ Path B: Skinned Garment ]
       (Helmets, Shields, Boots)               (Shirts, Jackets, Pants)
                   │                                     │
         Attached to bone sockets               Reparented to character
         "WearBone_<bone>" on                    GeneralSkeleton; deforms
         GeneralSkeleton (static)                with skeletal animations
```

1. **Path A: Rigid Parts (`WearablePart`)**:
   - Best for rigid gear: helmets, masks, pauldrons, backpacks, holstered gear, and footwear.
   - Each piece is a rigid mesh positioned relative to a single bone.
   - Handled via `WearBone_<bone>` (`BoneAttachment3D`) nodes created on first use on `GeneralSkeleton`.
2. **Path B: Skinned Garments (`skinned_scene`)**:
   - Best for clothing that must bend at joints: jackets, tunics, shirts, and trousers.
   - Meshes carry vertex weights bound to the Mixamo/Humanoid armature.
   - Handled by reparenting the imported `MeshInstance3D` directly under the character's `GeneralSkeleton`.

---

## 2. Scale Standards & Skeleton Reference

All assets follow Godot's standard metric convention: **1 Blender Unit = 1.0 meter**.

### Character Proportions (`man_a.glb` Reference)
- **Total Character Height**: Approximately 1.80m (from ground to top of head).
- **Head Center**: Y = ~1.65m above ground.
- **Chest / Torso Center**: Y = ~1.25m above ground.
- **Hips / Waist**: Y = ~0.95m above ground.
- **Knees**: Y = ~0.50m above ground.
- **Feet**: Y = 0.0m to 0.10m.

### Canonical Humanoid Bone Names (`SkeletonProfileHumanoid`)
When authoring rigid parts or naming vertex groups, use the exact canonical humanoid profile bone names:

| Body Region | Canonical Bone Names |
|---|---|
| **Head & Neck** | `Head`, `Neck` |
| **Torso** | `Chest`, `UpperChest`, `Spine`, `Hips` |
| **Arms & Hands** | `LeftUpperArm`, `RightUpperArm`, `LeftLowerArm`, `RightLowerArm`, `LeftHand`, `RightHand` |
| **Legs** | `LeftUpperLeg`, `RightUpperLeg`, `LeftLowerLeg`, `RightLowerLeg` |
| **Feet** | `LeftFoot`, `RightFoot`, `LeftToes`, `RightToes` |

---

## 3. Path A: Authoring Rigid Gear (Helmets, Shields, Accessories)

Rigid items attach directly to an auto-created `BoneAttachment3D` node on the skeleton.

### Step 1: Set the Origin to the Mounting Point
For rigid equipment, the object's origin `(0, 0, 0)` in Blender serves as the connection point to the bone:
- **Helmets / Hats**: Center of the head (between the ears). In Blender, align the origin to the center of the cranial cavity so it sits naturally when attached to `Head`.
- **Pauldrons / Shoulder Pads**: Top-outer edge of the shoulder joint (`LeftUpperArm` / `RightUpperArm`).
- **Backpacks**: Flat back surface where straps meet the spine (`Chest` or `Spine`).
- **Shields**: Center of the grip handle on the forearm (`LeftLowerArm` or `LeftHand`).

```
                    ┌─────────────────────────┐
                    │      Helmet Crown       │
                    │   ┌─────────────────┐   │
                    │   │  Head Cavity    │   │
(0, 0, 0) Origin -> │   │   * Origin *    │   │  <-- Snaps to "Head" bone
                    │   └─────────────────┘   │
                    │       Neck Guard        │
                    └─────────────────────────┘
```

### Step 2: Alignment & Transforms
1. Align the item to face forward along the **-Y or +Y axis** matching the character rest pose.
2. In Object Mode, press `Ctrl + A` -> **Apply Rotation & Scale**.
3. Keep the origin at your intended mounting pivot.

### Step 3: Export as glTF (.glb) or Extract Mesh
- For standalone rigid items, export as `.glb` (`File -> Export -> glTF 2.0 (.glb)`), with **Include -> Selected Objects**, **Transform -> +Y Up**, **Apply Modifiers**.
- In Godot, you can either reference the exported `Mesh` directly or use the `.glb` scene.

---

## 4. Path B: Authoring Skinned Garments (Shirts, Pants, Coats)

Skinned garments bend naturally with the character's limbs during locomotion, jumps, and combat swings.

### Step 1: Open the Character Workfile
Open `assets/custom/man_a/man_a.blend` (or your base humanoid character file containing the rigged armature).

### Step 2: Duplicate Geometry from the Body Mesh
To guarantee matching proportions and topologies:
1. Select the character's base body mesh and enter **Edit Mode** (`Tab`).
2. Select the vertices covering the garment area:
   - **Shirt/Jacket**: Torso, neck base, shoulders, and upper/lower arms.
   - **Pants**: Waist, hips, upper legs, and lower legs down to ankles.
3. Press `Shift + D` to duplicate the selected faces.
4. Press `P -> Selection` to separate the duplicate into its own independent object.
5. Exit Edit Mode (`Tab`) and rename the new object (e.g. `Garment_Trenchcoat` or `Garment_Pants`).

### Step 3: Inflate Along Normals (Preventing Skin Clipping)
Because the garment was duplicated directly from the skin, it will occupy the exact same surface space.
1. Select the new garment object and enter **Edit Mode** (`Tab`).
2. Select all vertices (`A`).
3. Press `Alt + S` (Shrink/Fatten) and pull outward slightly (+0.005m to +0.015m / 5mm to 15mm) to give the garment thickness and clearance over the skin.
4. Extrude cuffs, collars, hems, pockets, or buttons as desired.

```
       Skin Surface        Garment Surface (Inflated +8mm)
           │                        │
           ▼                        ▼
     ═════════════             ─────────────
      Body Mesh                 Cloth Mesh
     ═════════════             ─────────────
           ▲                        ▲
           └──────────┬─────────────┘
                      │
           Both share identical bone weights!
```

### Step 4: Verify Vertex Groups
Because the mesh was duplicated from the rigged body, it inherits the exact vertex weights for `mixamorig_Spine`, `mixamorig_LeftArm`, etc.
- Check Object Data Properties -> **Vertex Groups**. Do not rename or delete these groups unless modifying sleeve or leg lengths.
- If you add new geometry (e.g. loose coat tails or a hood), use **Weight Paint** mode or transfer weights from the base body (`Weight Paint -> Weights -> Transfer Weights`).

### Step 5: Export Garment with Armature
1. In Object Mode, select the **Armature** AND the **Garment mesh object(s)**.
2. Ensure the underlying base character mesh is **NOT selected**.
3. Go to **File -> Export -> glTF 2.0 (.glb)**.
4. Configure export settings:
   - **Include**: Selected Objects = **Checked**.
   - **Transform**: +Y Up = **Checked**.
   - **Geometry**: Apply Modifiers = **Checked**, UVs = **Checked**, Normals = **Checked**.
   - **Armature**: Export Deformation Bones Only = **Checked**.
   - **Animation**: Animation = **Unchecked** (animations are shared from the character library).
5. Save the file into `res://assets/clothing/<id>.glb` (e.g. `res://assets/clothing/cloth_shirt.glb`).

---

## 5. Godot Import & Retargeting

For skinned garments to bind to the in-game character, the imported glTF must be retargeted with the standard humanoid profile:

1. Locate the exported `.glb` in Godot's FileSystem dock.
2. Double-click to open **Advanced Import Settings**.
3. Select the `Skeleton3D` node in the import tree.
4. In the inspector panel on the right:
   - Set **Retarget -> Bone Map** to **New SkeletonProfileHumanoid**.
   - Verify that bone mappings match standard humanoid names (`Hips`, `Chest`, `LeftUpperLeg`, etc.).
5. Click **Reimport**.

> [!IMPORTANT]
> The BoneMap retarget renames the internal glTF `bind_names` to canonical humanoid names. This allows `EquipmentVisualizer` to reparent the `MeshInstance3D` under the character's `GeneralSkeleton` and have all skeletal skinning bind seamlessly.

---

## 6. Configuring `ItemDef` & `WearableParams`

Create or configure the `.tres` resource in `res://data/items/<id>.tres`:

### Example 1: Rigid Helmet (`cloth_cap.tres`)

```tres
[gd_resource type="Resource" script_class="ItemDef" format=3]

[ext_resource type="Script" path="res://data/items/item_def.gd" id="1_def"]
[ext_resource type="Script" path="res://data/capability_params/wearable_params.gd" id="2_wearable"]
[ext_resource type="Script" path="res://data/capability_params/wearable_part.gd" id="3_part"]
[ext_resource type="ArrayMesh" path="res://assets/models/cloth_cap.mesh" id="4_mesh"]
[ext_resource type="Material" path="res://assets/materials/cloth_brown.tres" id="5_mat"]

[sub_resource type="Resource" id="Resource_part_head"]
script = ExtResource("3_part")
bone = &"Head"
mesh = ExtResource("4_mesh")
material = ExtResource("5_mat")
offset = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.05, 0)

[sub_resource type="Resource" id="Resource_wearable"]
script = ExtResource("2_wearable")
rigid_parts = Array[ExtResource("3_part")]([SubResource("Resource_part_head")])

[resource]
resource_name = "Cloth Cap"
script = ExtResource("1_def")
id = "cloth_cap"
weight = 0.2
tags = Array[String](["equip_head"])
wearable = SubResource("Resource_wearable")
```

### Example 2: Skinned Garment (`cloth_shirt.tres`)

```tres
[gd_resource type="Resource" script_class="ItemDef" format=3]

[ext_resource type="Script" path="res://data/items/item_def.gd" id="1_def"]
[ext_resource type="Script" path="res://data/capability_params/wearable_params.gd" id="2_wearable"]
[ext_resource type="PackedScene" path="res://assets/clothing/cloth_shirt.glb" id="3_scene"]

[sub_resource type="Resource" id="Resource_wearable"]
script = ExtResource("2_wearable")
skinned_scene = ExtResource("3_scene")

[resource]
resource_name = "Cloth Shirt"
script = ExtResource("1_def")
id = "cloth_shirt"
weight = 0.5
tags = Array[String](["equip_torso"])
wearable = SubResource("Resource_wearable")
```

### Slot Routing Tags (`ItemDef.tags`)
Ensure the item carries the appropriate slot tag recognized by `Equipment.SLOT_ACCEPTED_TAGS`:
- `head` slot: `"equip_head"`
- `torso` slot: `"equip_torso"`
- `legs` slot: `"equip_legs"`
- `feet` slot: `"equip_feet"`
- `back` slot: `"equip_back"`

---

## 7. Verification Checklist

- [ ] Metric scale: 1 Blender unit = 1.0 meter; character height is ~1.8m.
- [ ] Transforms applied: Rotation and Scale are `(1.0, 1.0, 1.0)` before export.
- [ ] For rigid gear: Pivot origin is set to the bone attachment center (e.g. cranial cavity for helmets).
- [ ] For skinned garments: Garment is slightly inflated (`Alt + S`) to prevent skin penetration.
- [ ] For skinned garments: Exported with Armature; base character body mesh was excluded.
- [ ] Godot Import: Skeleton3D retargeted with `SkeletonProfileHumanoid` BoneMap.
- [ ] Data resource: `ItemDef.tags` contains the matching slot tag (`equip_head`, `equip_torso`, etc.).
- [ ] Data resource: `ItemDef.wearable` is populated with `WearableParams`.
- [ ] In-game test: Equip gear onto colonist/player; verify movement, sprint, and interact animations play without detachment or distortion.
- [ ] Unequip test: Unequip item; verify visual mesh is completely removed with zero leftovers.
