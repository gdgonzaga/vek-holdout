# HOWTO: Import and Wire Mixamo Animations

Complete pipeline for downloading action animations from **Mixamo**, retargeting them in **Godot 4.7**, registering them in `AnimationLibrary`, and wiring them into character `AnimationTree` nodes and item `.tres` definitions.

```
 [ Mixamo ]  Download 'Without Skin' FBX (30 FPS, Keyframe Reduction: None)
     |
 [ Godot Import ]  Set Retarget -> BoneMap = SkeletonProfileHumanoid
     |
 [ AnimationLibrary ]  Save clip into res://assets/mixamo/animations.res
     |
 [ AnimationTree ]  Add transition input to ActionSelect in player.tscn & colonist.tscn
     |
 [ Data Definition ]  Set use_animation = &"MyAnim" in data/items/<id>.tres
```

---

## Step 1: Download from Mixamo

1. On [Mixamo](https://www.mixamo.com/), select your desired animation (e.g., **AttackOverhead**, **Slash**, **Firing**).
2. Click **Download** with the following settings:
   - **Format:** FBX Binary (`.fbx`)
   - **Skin:** **Without Skin** (only motion tracks, no redundant mesh)
   - **FPS:** 30
   - **Keyframe Reduction:** None
3. Save the downloaded `.fbx` file into `res://assets/mixamo/` (e.g., `res://assets/mixamo/AttackOverhead.fbx`).

---

## Step 2: Retarget and Save to `AnimationLibrary`

1. In Godot's **FileSystem** dock, double-click the imported `.fbx` to open the **Advanced Import Settings** dialog.
2. In the left panel, select the `Skeleton3D` node:
   - Under **Retarget -> Bone Map**, select **New SkeletonProfileHumanoid**.
   - Godot automatically maps `mixamorig_*` track names to standard humanoid profile bones (`Hips`, `Spine`, `RightHand`, etc.).
3. Under the **Animation** tab:
   - Select the animation clip entry.
   - Enable **Save to File** or extract the animation resource into `res://assets/mixamo/animations.res`.
4. Click **Reimport**.

---

## Step 3: Wire into Character `AnimationTree` (`player.tscn` & `colonist.tscn`)

Characters execute upper-body action overlays through an `AnimationNodeOneShot` driven by an `AnimationNodeTransition` selector named **`ActionSelect`**.

To add a new action animation:

1. Open `res://subsystems/player/player.tscn` (and `res://subsystems/colonists/colonist.tscn`).
2. Select the **`AnimationTree`** node.
3. Open the **AnimationTree panel** at the bottom of the editor view.
4. Click on the **`ActionSelect`** transition node:
   - In the **Inspector** dock (right side), expand **Inputs**.
   - Click **Add Input** (or increment input count).
   - Set the input **Name** to match your animation name (e.g., `"AttackOverhead"`).
5. Right-click in the empty space of the `AnimationTree` graph:
   - Select **Add Animation** -> choose your clip (e.g., `animations/AttackOverhead`).
6. Drag a connection from the output of the new animation node to the corresponding input port on **`ActionSelect`**.
7. Save the scene (`Ctrl + S`).

---

## Step 4: Wire to Item Definition (`ItemDef`)

Equippable items define which upper-body action animation triggers when used:

1. Open your item resource in `res://data/items/` (e.g., `res://data/items/baton.tres`).
2. Under the `EquippableParams` sub-resource, set **`use_animation`**:
   ```gdscript
   use_animation = &"AttackOverhead"
   ```
3. When the player or colonist uses this item, `use_animation` will automatically trigger the matching overlay animation on the character's `AnimationTree`.

---

## Step 5: (Optional) Alias Keywords in Script

If you want generic action terms (e.g., `swing`, `slash`, `attack`, `fire`, `dig`) to map to your new animation automatically:

Open `subsystems/player/player_animation_controller.gd` (and `subsystems/colonists/colonist_animation_controller.gd`) and update `_resolve_action_animation_name`:

```gdscript
## Auxiliary: Maps incoming generic action or weapon animation names to valid ActionSelect transition names
func _resolve_action_animation_name(action_name: StringName) -> StringName:
	var name_str := String(action_name).to_lower()
	if name_str in ["attackoverhead", "swing", "attack", "strike", "melee"]:
		return &"AttackOverhead"
	if name_str in ["interact", "fire", "shoot", "use"]:
		return &"Interact"
	if name_str in ["digging", "dig"]:
		return &"Digging"
	return action_name
```
