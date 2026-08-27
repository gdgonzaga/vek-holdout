# HOWTO: Integrate MakeHuman (MPFB) and Mixamo Characters

This guide outlines the complete pipeline for generating a character with the **MakeHuman Plugin for Blender (MPFB2)**, auto-rigging it with **Mixamo**, assembling textured meshes in **Blender**, exporting as **glTF 2.0 (.glb)**, and integrating the model into Godot 4.7.

---

## High-Level Pipeline Overview

```
 [ Blender (MPFB2) ]
        │ (1. T-Pose ➔ 2. Reduced Doll ➔ 3. Export OBJ)
        ▼
   [ Mixamo ]  ───► Auto-rig mesh & download T-Pose FBX + skinless animations
        │
        ▼
 [ Blender Assembly ] ➔ Re-parent Reduced Doll & textured asset meshes to Mixamo Armature
        │ (Apply All Transforms ➔ Set Rest Pose ➔ Export .glb)
        ▼
 [ Godot 4.7 Importer ] ➔ Model (.glb) BoneMap: None | Animation FBXs ➔ SkeletonProfileHumanoid (.tres)
        │
        ▼
 [ Vek Holdout Gameplay ]
```

---

## Phase 1: Blender & MPFB2 Setup

MakeHuman base characters contain hidden helper geometries (genital/body proxy meshes, face rigs, tongue/teeth) that cause skin bleeding/glitches if exported raw. We use MPFB2's **Reduced Doll** to create a clean base mesh.

### 1. T-Pose Requirement & Rest Pose Application
Godot 4's humanoid retargeting profile (`SkeletonProfileHumanoid`) assumes a default T-pose rest pose.

1. Select the character's armature and enter **Pose Mode** (`Ctrl + Tab`).
2. Rotate upper arms upward (~45 degrees) until arms are parallel to the ground and palms face down.
3. Open the **MPFB** sidebar tab (`N` panel) ➔ **Operations** ➔ **Poses**.
4. Click **`Apply as rest pose`** (synchronizes armature rest state and attached meshes).

---

### 2. Create the "Reduced Doll" Mesh
To avoid body mesh glitches (e.g. genital/helper geometry rendering over clothing):
1. Select your character in Object Mode.
2. In the MPFB sidebar panel (`N`), go to **Operations** ➔ **Animation** ➔ **Reduced Doll**.
3. Click **Reduced Doll** to generate a clean, watertight single-surface body mesh.

---

### 3. Export OBJ for Mixamo
1. Select **only** the Reduced Doll body mesh in **Object Mode**.
2. Go to **File** ➔ **Export** ➔ **Wavefront (.obj)**.
3. In export settings:
   - Check **Selected Only** (excludes cameras, lights, and extra objects).
   - Ensure **Write Materials** is checked.
4. Export the `.obj` file.

---

## Phase 2: Rigging and Animating in Mixamo

1. **Auto-Rig the Character:**
   - Open [Mixamo](https://www.mixamo.com/) and click **Upload Character**.
   - Upload the `.obj` exported from Blender.
   - Place the chin, wrist, elbow, knee, and groin markers. Click **Next** to rig.

2. **Download T-Pose Character Model:**
   - Download setting: Format: **FBX Binary**, Skin: **With Skin**, FPS: **30**, Keyframe Reduction: **None**.

3. **Download Locomotion & Interaction Animations:**
   - Search Mixamo for `Walk`, `Idle`, `Sprint`, `Jump`, `Interact`/`Digging`.
   - Download settings for each: Format: **FBX Binary**, Skin: **Without Skin**, FPS: **30**.

---

## Phase 3: Blender Assembly & `.glb` Export

Rather than fixing materials in Godot, assemble the textured asset meshes (clothes, hair, eyes) and Reduced Doll body with the Mixamo armature in Blender for 1-click automatic texture export.

### 1. Assemble in Blender
1. Open the original `.blend` file containing your textured MakeHuman character.
2. Go to **File** ➔ **Import** ➔ **FBX** and select the Mixamo T-pose FBX (`character_model.fbx`).
3. Scale the imported Mixamo **`Armature`** to match human height (Z: ~1.8m).
4. Use the **Reduced Doll** body mesh + asset meshes (clothing, hair, eyes, eyebrows) — delete the raw un-reduced body mesh and old `Human.rig` armature.

### 2. Weighting & Re-parenting
1. **Clear Old Parent Offsets:** Select the textured asset meshes ➔ press **`Alt + P`** ➔ **Clear and Keep Transformation**.
2. **Clear Old Vertex Groups:** For each mesh, go to **Object Data Properties** (green triangle) ➔ **Vertex Groups** dropdown ➔ **Delete All Groups**.
3. **Head Assets (Hair, Eyes, Eyebrows):** Parent directly to the **Head** bone (`Ctrl + P` ➔ **Bone**) or assign 100% weight to `mixamorig:Head` to prevent hair from stretching down to the feet.
4. **Body & Clothing Meshes:** Select meshes, hold `Shift` + click Mixamo **`Armature`** ➔ **`Ctrl + P`** ➔ **With Automatic Weights**.

### 3. Apply Transforms & Set Rest Pose
1. In Object Mode, select all ➔ **`Ctrl + A`** ➔ **All Transforms**.
2. In Pose Mode (`Ctrl + Tab`), select all bones (`A`) ➔ **`Alt + R`**, **`Alt + G`**, **`Alt + S`**.
3. Go to **Armature Data Properties** (green running-man icon) ➔ expand the **Pose** section ➔ click **`Rest Position`** (or `Pose` ➔ `Apply` ➔ `Apply Pose as Rest Pose`).

### 4. Export as `.glb` (glTF 2.0)
1. In Object Mode, select the Mixamo **`Armature`** and the character meshes (`A`).
2. Go to **File** ➔ **Export** ➔ **glTF 2.0 (.glb)**.
3. Export settings:
   - **Include:** Check **Selected Objects**.
   - **Data ➔ Mesh:** Ensure **Skinning** is checked.
   - **Data ➔ Material:** Ensure **Materials** is set to `Export`.
4. Export as `man1_rigged.glb` directly into `res://assets/makehuman/`.

---

## Phase 4: Godot 4.7 Import & Code Integration

### 1. Import Settings in Godot
- **`man1_rigged.glb` (Character Model):** Keep **`Bone Map` = `<null>` / None** (do NOT apply BoneMap to character models).
- **Animation FBX Files (`Walk.fbx`, `Digging.fbx`):**
  1. Select animation file in FileSystem dock ➔ open **Advanced Import Settings**.
  2. Under `Skeleton3D`, set **Retarget ➔ Bone Map** to **`New SkeletonProfileHumanoid`**.
  3. Under `AnimationPlayer`, check **Save to File: Enabled** and extract to `res://assets/makehuman/animations/Walk.tres`.
  4. Click **Reimport**.

### 2. Scene Setup (`player.tscn` & `colonist.tscn`)
1. Replace `%CharacterModel` under `Visuals` with `res://assets/makehuman/man1_rigged.glb`.
2. In `AnimationPlayer`:
   - Add/configure `mixamo` library with `Walk` (`Walk.tres`) and `Idle` (`Idle.tres`).

### 3. Animation Controller Skeleton Rebinding
Because `PlayerAnimationController` and `ColonistAnimationController` rename the skeleton node to `GeneralSkeleton` at runtime, you must re-bind all imported `MeshInstance3D.skeleton` paths so the skinned meshes remain visible:

```gdscript
func _setup_skeleton() -> void:
	if not _player:
		return
		
	var skeleton: Skeleton3D = _player.find_child("*Skeleton*", true, false) as Skeleton3D
	if skeleton:
		skeleton.name = "GeneralSkeleton"
		skeleton.owner = _player
		skeleton.unique_name_in_owner = true
		
		# Re-bind all imported meshes to the renamed skeleton so skinned meshes stay visible
		for child in _player.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi and mi != _player.get_node_or_null("MeshInstance3D"):
				mi.skeleton = mi.get_path_to(skeleton)
				mi.visible = true
		
		if anim_player:
			anim_player.clear_caches()
```

---

## Troubleshooting & Tips

- **Invisible Skinned Mesh:** Occurs when `skeleton.name = "GeneralSkeleton"` runs at runtime without re-binding `mi.skeleton = mi.get_path_to(skeleton)`, or if `Bone Map` was mistakenly applied to the character `.glb` model instead of `None`.
- **Hair Stretching to Feet:** Caused by running Automatic Weights on hair/eyebrows across the whole armature. Parent hair/eyebrows/eyes directly to the `Head` bone (`mixamorig:Head`).
- **Magenta / Bright Pink Textures:** Universal missing texture color. Ensure textures are plugged into `Principled BSDF ➔ Base Color` in Blender before glTF export.
- **Pink warning in console (`couldn't resolve track: %GeneralSkeleton:...`):** Non-fatal warning when an extracted Mixamo animation includes tracks for extra finger/face bones not mapped on the model. Safe to ignore or delete the unused track in the Animation editor.
