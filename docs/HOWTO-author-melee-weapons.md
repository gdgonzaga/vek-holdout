# How To: Author Melee Weapon Models in Blender

> End-to-end guide for modeling, scaling, orienting, texturing, exporting, and integrating 3D melee weapons (batons, swords, axes, clubs) for *Xeno Frontier: Colony Defense*.
> Covers grip origin placement, coordinate alignment for humanoid hand sockets, glTF export settings, `ItemDef`, `EquippableParams`, and `MeleeActionParams` resource configuration.
>
> **Prerequisites:** Blender 4.x+, basic Godot resource editing, and familiarity with `docs/architecture/equipment.md` and `docs/architecture/combat.md`.

---

## 1. Modeling Specifications & Scale Standards

All measurements in *Xeno Frontier: Colony Defense* follow Godot's standard metric units (**1 Blender Unit = 1.0 meter**).

### Standard Melee Dimensions

| Weapon Type | Total Length | Handle Length | Grip Diameter | Blade / Head Width |
|---|---|---|---|---|
| **Baton / Truncheon** | 0.45m - 0.60m | 0.15m - 0.20m | 0.035m (3.5cm) | 0.04m - 0.05m |
| **Dagger / Knife** | 0.25m - 0.40m | 0.12m - 0.15m | 0.030m (3.0cm) | 0.04m - 0.06m |
| **1H Sword / Axe / Club** | 0.75m - 1.00m | 0.18m - 0.25m | 0.035m (3.5cm) | 0.08m - 0.20m |
| **2H Greatsword / Polearm** | 1.30m - 1.80m | 0.35m - 0.50m | 0.038m (3.8cm) | 0.15m - 0.30m |

```
                       [ +Z Blade / Striking End ]
                                  ▲
                                  │
                          ┌───────────────┐
                          │               │
                          │   Blade /     │  <-- Striking Area / Hitbox Range
                          │   Baton Tip   │
                          │               │
                          ├───────────────┤
                          │  Crossguard   │
                          ├───────────────┤
   (0, 0, 0) Origin --->  │ [ Grip Point ]│  <-- Hand wraps here (Z = 0.0)
                          ├───────────────┤
                          │    Pommel     │
                          └───────────────┘
                                  │
                                  ▼
                              [ -Z Base ]
```

---

## 2. Pivot & Coordinate Orientation Rules

Proper pivot and orientation in Blender ensure that the weapon snaps into character hands naturally without awkward offsets in Godot.

### A. The Grip Pivot Rule
> [!IMPORTANT]
> **The Object Origin (0, 0, 0) MUST be at the center of the grip handle.**
> When Godot attaches the weapon mesh to a character's hand bone (`RightHand`), the mesh's origin aligns directly with the bone socket.
> 1. In Blender Edit Mode, select the loop of vertices in the center of the handle where the palm rests.
> 2. Press `Shift + S` → **Cursor to Selected**.
> 3. Switch to Object Mode, right-click the weapon object → **Set Origin → Origin to 3D Cursor**.

### B. Standard Hand Alignment
- **Upright (`+Z`)**: The striking head / blade tip extends upward along the positive **Z-axis**.
- **Forward (`-Y` or `+Y`)**: The cutting edge or front strike face points forward along the **Y-axis**.
- **Lateral (`+/- X`)**: The crossguard / width extends across the **X-axis**.

### C. Apply Transforms Before Export
Always apply object transforms so the mesh scale is strictly `(1.0, 1.0, 1.0)`:
1. In Object Mode, select your weapon object.
2. Press `Ctrl + A` → **Apply Rotation & Scale** (do NOT apply location if your origin is already at the grip).

---

## 3. Hitbox (`Area3D`) Authoring in Blender (`-areaonly` Convention)

Godot's glTF importer supports special naming suffixes. Authoring an invisible `Area3D` collision volume directly in Blender avoids manual scene-tree edits in Godot.

### A. The `-areaonly` Naming Rule

> [!TIP]
> Any mesh object in Blender named with the suffix **`-areaonly`** (e.g. `Hitbox-areaonly` or `BladeHitbox-areaonly`) will be imported into Godot as an **`Area3D`** node containing a child **`CollisionShape3D`**, automatically discarding the visual geometry. In addition, character equipment sockets automatically sanitize and hide any auxiliary collision, area, or hitbox mesh nodes when mounting items.

```
Blender Hierarchy:
Baton                         <-- Visible weapon mesh (Origin at Grip)
└── Hitbox-areaonly           <-- Simplified low-poly Box/Capsule over striking head

Godot Imported Scene:
Baton (MeshInstance3D / Node3D)
└── Hitbox (Area3D)
    └── CollisionShape3D      <-- Convex / Box collision shape
```

### B. Step-by-Step Hitbox Creation in Blender

1. **Add Collision Primitive**:
   - In Object Mode, press `Shift + A` → **Mesh → Cube** (or **Cylinder**).
2. **Fit to Striking Region Only**:
   - Scale and translate the shape in Edit Mode so it encloses the **damaging part of the weapon** (the baton head, axe blade, or sword edge).
   - **Do NOT enclose the grip/handle**: The character's hand should remain outside the damage volume.
3. **Name the Object**:
   - In the Outliner or Item Properties (`N` panel), rename the collision object to `Hitbox-areaonly`.
4. **Parent to Weapon**:
   - Select `Hitbox-areaonly` → Shift-select the main weapon object → press `Ctrl + P` → **Set Parent To: Object (Keep Transform)**.
5. **Apply Transforms**:
   - Select `Hitbox-areaonly` and press `Ctrl + A` → **Apply Rotation & Scale**.

```
                       [ +Z Blade / Striking End ]
                                  ▲
                          ┌───────────────┐  ▲
                          │ ┌───────────┐ │  │
                          │ │  Hitbox   │ │  │
                          │ │ -areaonly │ │  │  <-- Active Damage Zone
                          │ └───────────┘ │  │      (Area3D Hitbox)
                          ├───────────────┤  ▼
                          │  Crossguard   │
                          ├───────────────┤
   (0, 0, 0) Origin --->  │ [ Grip Point ]│  <-- Safe zone (no hitbox)
                          ├───────────────┤
                          │    Pommel     │
                          └───────────────┘
                                  │
                                  ▼
                              [ -Z Base ]
```

---

## 4. Materials & Texturing

Xeno Frontier: Colony Defense uses low-poly stylization and palette texture atlases:
1. **Palette Atlas (Preferred)**: Map the weapon's UV faces to the shared texture atlas (`res://assets/animpic-mega-survival-construction/MainTexture.png`).
2. **Dedicated Material**: If using a custom texture, keep resolution at 512x512 or 1024x1024 with clean albedo, roughness, and metallic channels.
3. Name your material cleanly in Blender (e.g. `Mat_Baton`, `Mat_Sword`).
4. Note: You do not need to assign materials or UV unwrap `Hitbox-areaonly` since its visual mesh is discarded upon import.

---

## 5. Blender glTF (.glb) Export Settings

1. Select both your weapon mesh and the child `Hitbox-areaonly` (or select the parent and its hierarchy).
2. In Blender, go to **File → Export → glTF 2.0 (.glb)**.
3. Configure the export preset with the following settings:

| Section | Setting | Value |
|---|---|---|
| **Include** | Limit to Selected Objects | **Checked** |
| **Transform** | +Y Up | **Checked** |
| **Geometry** | Apply Modifiers | **Checked** |
| | UVs | **Checked** |
| | Normals | **Checked** |
| | Tangents | **Unchecked** (unless normal maps are used) |
| **Animation** | Animation | **Unchecked** |

4. Save the file to your project directory (e.g. `res://assets/weapons/baton.glb`).

---

## 6. Godot Integration & Data Authoring

Once imported into Godot, author the gameplay data resources in `res://data/`:

### Step 1: Create or Update the `ItemDef` Resource

Create a new `ItemDef` resource in `res://data/items/<id>.tres` (e.g. `res://data/items/baton.tres`):

```tres
[gd_resource type="Resource" script_class="ItemDef" format=3]

[ext_resource type="Script" path="res://data/items/item_def.gd" id="1_def"]
[ext_resource type="Script" path="res://data/capability_params/equippable_params.gd" id="2_equip"]
[ext_resource type="Script" path="res://data/capability_params/melee_action_params.gd" id="3_melee"]
[ext_resource type="PackedScene" path="res://assets/weapons/baton.glb" id="4_scene"]

[sub_resource type="Resource" id="Resource_combat_action"]
script = ExtResource("3_melee")
id = "baton_strike"
cooldown_seconds = 0.4
audio_event = "melee_swing"
damage = 5.0
range_meters = 1.0
windup_seconds = 0.15
active_seconds = 0.2
hit_audio_event = "melee_impact"

[sub_resource type="Resource" id="Resource_equippable"]
script = ExtResource("2_equip")
stance_animation = &"melee_1h"
use_animation = &"swing"
primary_action = SubResource("Resource_combat_action")

[resource]
resource_name = "Baton"
script = ExtResource("1_def")
id = "baton"
weight = 1.8
scene = ExtResource("4_scene")
tags = Array[String](["weapon", "melee", "untrained"])
equippable = SubResource("Resource_equippable")
```

> **Tag-Based Slot Routing**: `EquippableParams` contains no slot fields. Equipment slot eligibility is resolved purely via `ItemDef.tags` (e.g. `"weapon"` maps to weapon/main hand slots, `"tool"` to tool slots per `Equipment.SLOT_ACCEPTED_TAGS`).

### Step 2: Configure Melee Timing Parameters

Tune `MeleeActionParams` to match the weapon's weight and visual swing animation:
- **`damage`**: Scalar HP damage dealt on impact (e.g. `5.0` for baton, `25.0` for short sword, `35.0` for broadsword).
- **`range_meters`**: Maximum strike reach in world space (e.g. `1.0m` for baton, `2.5m` - `3.0m` for swords).
- **`windup_seconds`**: Delay before the attack hitbox activates (matches the animation backswing).
- **`active_seconds`**: Duration the hitbox stays dangerous during the forward swing.
- **`cooldown_seconds`**: Recovery period before another attack can be initiated.

---

## 7. Verification Checklist

- [ ] Origin (0,0,0) is centered on the handle grip where fingers wrap.
- [ ] Weapon points upward along `+Z` and faces forward along `Y`.
- [ ] Hitbox volume is authored as a child object named `Hitbox-areaonly` enclosing only the striking area.
- [ ] Object scale is applied to `(1.0, 1.0, 1.0)` on both the weapon and hitbox.
- [ ] Exported as `.glb` with `+Y Up` enabled.
- [ ] Godot imports the scene with an `Area3D` child named `Hitbox` and no visible collider mesh.
- [ ] `EquippableParams` defines `stance_animation` (e.g. `&"melee_1h"`) and `use_animation` (e.g. `&"swing"`).
- [ ] `MeleeActionParams` defines `damage`, `range_meters`, `windup_seconds`, and `active_seconds`.
