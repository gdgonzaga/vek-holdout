# How To: Author Defensive Turrets

> End-to-end guide for modeling, rigging, scaling, exporting, and configuring 3D automated defensive turrets for `FurnitureDef` and `TurretParams` resources in *Vek: Holdout*.
> Covers Blender node hierarchy, `+Y` forward facing direction, pivot/origin placement, transform application rules (**never apply location**), glTF `.glb` export settings, and Godot scene extraction.
>
> **Prerequisites:** Basic knowledge of 3D modeling in Blender, Godot `.tres` Resource editing, and `docs/architecture/combat.md`.

---

## 1. Blender Modeling Guidelines & Hierarchy Rules

Defensive turrets in *Vek: Holdout* use a 2-axis aiming system (`TurretComponent`) to track hostile targets:
- **Yaw (Horizontal Tracking)**: Rotates 360° left and right around the vertical axis.
- **Pitch (Vertical Elevation)**: Tilts up and down around the horizontal elevation axle.
- **Muzzle Socket**: Visual launch point where `TurretProjectile` instances spawn.

### A. Critical Facing Direction (`+Y` Forward in Blender)

> [!IMPORTANT]
> **Turret Forward Direction is `+Y` in Blender**  
> In Blender, the front of the turret, the barrel, the projectile nozzle, and the `Muzzle` empty must point towards **`+Y`** (top of the screen in Top Orthographic View `Numpad 7`, or back in Front View).
> When exported to `.glb` with `+Y Up`, this maps correctly to Godot's forward aiming vector.

```
                  [ +Y Forward / Barrel Direction ]
                                ▲
                                │
                        ┌──────────────┐
                        │   (Muzzle)   │
                        │    [====]    │  <-- TurretPitch (Tilts on X-axis)
                        ├──────────────┤
                        │ (TurretYaw)  │  <-- Rotates 360° around Z-axis
                        ├──────────────┤
                        │  TurretBase  │  <-- Stationary Base (Z = 0.0)
                        └──────────────┘
                                │
                                ▼
                             [ -Y Rear ]
```

---

### B. Blender Scene Tree & Hierarchy

Separate your turret mesh into distinct child objects with the following exact naming convention:

```
TurretBase                    <-- Stationary ground mount
└── TurretYaw                 <-- Rotates horizontally (Yaw)
    └── TurretPitch           <-- Tilts vertically (Pitch)
        └── Muzzle            <-- Empty (Plain Axes) at barrel tip
```

#### Parenting Steps in Blender:
1. Select `Muzzle` → Shift-select `TurretPitch` → Press `Ctrl + P` → **Keep Transform**.
2. Select `TurretPitch` → Shift-select `TurretYaw` → Press `Ctrl + P` → **Keep Transform**.
3. Select `TurretYaw` → Shift-select `TurretBase` → Press `Ctrl + P` → **Keep Transform**.

---

### C. Pivot & Origin Placement

Each object must have its origin (the orange dot in Blender) placed at its exact mechanical pivot point:

1. **`TurretBase` Origin**: Centered at the bottom contact surface on the floor (`X = 0.0, Y = 0.0, Z = 0.0`).
2. **`TurretYaw` Origin**: Centered at the vertical rotation ring/turntable axis (`X = 0.0, Y = 0.0, Z = base_height`).
3. **`TurretPitch` Origin**: Placed at the exact center of the elevation axle / central hinge of the barrel wheel.
   - *How to set*: In Edit Mode (`Tab`), select all vertices of the elevation cylinder/hinge → `Shift + S` → **Cursor to Selected** → `Tab` to Object Mode → Right-click → **Set Origin → Origin to 3D Cursor**.
4. **`Muzzle` Origin**: Positioned directly at the tip of the barrel / nozzle where projectiles exit.

---

### D. Applying Transforms — Critical Invariant

> [!CAUTION]
> **DO NOT APPLY LOCATION!**  
> Applying location (`Ctrl + A` → *All Transforms* or *Location*) resets the object origin of `TurretPitch` and `Muzzle` back to the world origin `(0, 0, 0)`. This destroys the pivot points, snaps the muzzle to the floor, and causes the barrel to rotate around the ground rather than its axle!
>
> **Apply ONLY Rotation and Scale:**
> 1. Select all turret objects in Object Mode (`A`).
> 2. Press **`Ctrl + A` → Apply Rotation & Scale** (or apply *Rotation* and *Scale* individually).
> 3. Verify in the Sidebar (`N` panel under Item → Transform) that **Scale is `(1.0, 1.0, 1.0)`** and **Rotation is `(0°, 0°, 0°)`**, while **Location retains its relative offset values**.

---

## 2. Normals & Shading (Blender 4.1+)

To ensure clean specular highlights without shading artifacts across flat plates and curved barrels:

1. **Smooth by Angle**: Select all mesh objects in Object Mode → Right-click → **Shade Auto Smooth** (or add modifier **Normals → Smooth by Angle** with angle `30°`).
2. **Weighted Normal Modifier**: Add **Normals → Weighted Normal** to each mesh:
   - Check **Keep Sharp**.
   - Set **Weight** to `100`.
   - *Why*: Keeps large planar wooden/metal surfaces completely flat while smoothing transition bevels.

---

## 3. Exporting to `.glb` Format

1. Select the root `TurretBase` and all child components in Object Mode.
2. Go to **File → Export → glTF 2.0 (.glb)**.
3. Export Settings:
   - **Format**: `glTF Binary (.glb)`
   - **Include → Limit to**: `Selected Objects` (Checked)
   - **Transform → +Y Up**: Checked
   - **Geometry → Apply Modifiers**: Checked
4. Save file to project directory (e.g. `assets/custom/<turret_id>/<turret_id>.glb`).

---

## 4. Godot Scene Extraction & Setup

When Godot imports the `.glb` file, it builds the following node structure:

```
TurretBase (Node3D / MeshInstance3D)
└── TurretYaw (Node3D / MeshInstance3D)
    └── TurretPitch (Node3D / MeshInstance3D)
        └── Muzzle (Node3D / Marker3D)
```

### Extracting `PackedScene` for `FurnitureDef`:
1. In Godot's **FileSystem dock**, right-click `<turret_id>.glb` → **New Inherited Scene**.
2. Verify in the 3D viewport that `TurretYaw` and `TurretPitch` have their gizmos centered on their respective pivot points.
3. Save the scene as `res://assets/custom/<turret_id>/<turret_id>.tscn` (or keep as a bundled `.glb` scene).

---

## 5. Configuring `FurnitureDef` and `TurretParams` Resource

1. Open (or create) the turret's `FurnitureDef` in `data/furniture/<turret_id>.tres`.
2. Set core properties:
   - **`id`**: Unique string identifier (e.g. `"wooden_stake_turret"`).
   - **`dimensions`**: Grid footprint in voxels (e.g. `Vector3i(2, 2, 2)`).
   - **`scene`**: Assign the extracted `.tscn` or imported `.glb`.
3. In the **`turret_params`** property slot, create a new `TurretParams` sub-resource:
   - **`range`**: Maximum target scanning distance in meters (e.g. `18.0`).
   - **`fire_rate`**: Shots per second (e.g. `0.2` = 1 shot every 5s, `1.0` = 1 shot/s).
   - **`damage`**: Damage dealt per projectile hit (e.g. `15`).
   - **`ammo_type`**: Required ammunition `ItemDef` (e.g. `data/items/wooden_stake.tres`). Leave null for free ammo.
   - **`turn_speed`**: Rotation speed in radians per second (e.g. `2.0` to `5.0`).
   - **`min_pitch_deg`**: Minimum downward depression limit in degrees (e.g. `-15.0`).
   - **`max_pitch_deg`**: Maximum upward elevation limit in degrees (e.g. `60.0`).
   - **`projectile_speed`**: Travel speed in m/s (e.g. `30.0`).
   - **`projectile_type`**: `REGULAR` (direct single-target hit) or `EXPLOSIVE` (AoE splash).

---

## 6. Authoring Troubleshooting Checklist

| Issue in Godot | Root Cause | Fix |
| :--- | :--- | :--- |
| **Barrel rotates on its side / rolls like a wheel** | Model was pointing `+X` or `-X` instead of `+Y` in Blender. | Rotate model in Blender so the barrel points **`+Y` Forward**, then apply Rotation. |
| **Entire turret turns or snaps around the floor** | **Location was applied in Blender**, resetting child origins to `(0,0,0)`. | Re-center `TurretPitch` origin to its axle, `TurretYaw` origin to its turntable, and **never apply location**. |
| **Muzzle spawns bullets from the ground** | `Muzzle` empty origin reset to `0,0,0` or missing from hierarchy. | Position `Muzzle` at barrel tip parented to `TurretPitch`. Do not apply location to `Muzzle`. |
| **Turret ignores targets** | Targets missing `HealthComponent`, dead, or out of `range`. | Verify enemy is in group `"enemies"`, has alive `HealthComponent`, and distance `<= range`. |
| **Turret will not fire** | Required ammo missing from inventory and colony crates. | Ensure `ammo_type` item exists in local `StorageInventory` or colony storage registry crates. |
