# HOWTO: Integrate MakeHuman (MPFB) and Mixamo Characters

Complete pipeline for producing a character with the **MakeHuman Plugin for Blender (MPFB)**, auto-rigging it on **Mixamo**, assembling it in **Blender**, and wiring model + animations into Godot 4.7 so they actually play.

The single most important rule: **the model glb AND every animation FBX must be retargeted with the same `SkeletonProfileHumanoid` bone map in Godot.** Retargeting only the model leaves the animations addressing `mixamorig_*` bones that no longer exist — that is the classic T-pose failure.

```
 [ Blender (MPFB) ]  create human, rig, assets, T-pose rest, reduced doll
        |
   [ Mixamo ]  auto-rig reduced doll -> T-Pose FBX (armature source) + skinless animation FBXs
        |
 [ Blender assembly ]  reparent meshes to the Mixamo armature -> export .glb
        |
 [ Godot import ]  model glb + every animation FBX: BoneMap = SkeletonProfileHumanoid
        |
 [ Library ]  extract .tres, add to assets/mixamo/mixamo.res under canonical keys
```

---

## Phase 1: Author the character in Blender (MPFB)

MakeHuman base characters contain hidden helper geometry (face rigs, tongue/teeth, body proxies) that breaks skinning if exported raw. The Reduced Doll solves this.

1. **Create human** in the MPFB panel.
2. **Add the standard rig** and **rig helpers**.
3. **Add assets** (clothes, hair, eyes, eyebrows).
4. **Save the preset** (so the character can be regenerated later).
5. Enter **Pose Mode** (`Ctrl + Tab`) and rotate the upper arms until they are parallel to the ground with palms facing down (T-pose).
6. MPFB sidebar (`N`) -> **Operations -> Poses -> Apply as rest pose** (synchronizes the armature rest state and attached meshes).
7. **Operations -> Animation -> Reduced Doll** to generate the clean, watertight body mesh used for Mixamo rigging. No export is needed at this point.

## Phase 2: Auto-rig on Mixamo

1. Export the **Reduced Doll mesh only** as OBJ (`File -> Export -> Wavefront (.obj)`, **Selected Only**).
2. On [Mixamo](https://www.mixamo.com/), **Upload Character**, place the chin/wrist/elbow/knee/groin markers, auto-rig.
3. Download the **T-Pose character, FBX Binary, With Skin, 30 FPS, Keyframe Reduction None**. This FBX is the **armature source**: it carries the `mixamorig:*` bone rig used in Phase 3. The rig is fitted to *this* character's proportions — do not reuse a previous character's T-Pose FBX.
4. Download each animation (**Walk**, **Idle**, **Sprint**, **Jump**, **Interact**, **Digging**, ...) as **Without Skin**, FBX Binary, 30 FPS, Keyframe Reduction None.

## Phase 3: Assemble in Blender

1. Import the Mixamo **T-Pose FBX** into the character's `.blend` — its purpose is to bring in the Mixamo armature.
2. Scale the imported `Armature` to human height (Z about 1.8m).
3. Keep the **Reduced Doll flesh mesh** and the textured asset meshes. Delete the raw MPFB human/flesh meshes and the old `Human.rig` armature.
4. Clear old parents (`Alt + P` -> Clear and Keep Transformation) and **delete all vertex groups** on the asset meshes.
5. **Hair, eyes, eyebrows:** assign 100% weight to `mixamorig:Head` (or parent to the Head bone AND weight it). Plain object parenting to a bone does not survive glTF export.
6. **Body and clothing meshes:** Shift-select meshes then the `Armature` -> `Ctrl + P` -> **With Automatic Weights**.
7. Select all -> `Ctrl + A` -> **All Transforms**; in Pose Mode clear pose (`Alt + R`, `Alt + G`, `Alt + S`).
8. Export **glTF 2.0 (.glb)**: select the `Armature` **and all character meshes**; **Include -> Selected Objects**; armature must be **visible** (the Visible Objects filter drops hidden objects); Skinning on; **Animation off** (animations come from the separate Mixamo FBXs). Export into `res://assets/makehuman/<id>/`.

## Phase 4: Import the model in Godot (BoneMap retarget)

1. Double-click the `.glb` in the FileSystem dock -> **Advanced Import Settings**.
2. Select the `Skeleton3D` node in the dialog's scene tree -> **Retarget -> Bone Map** -> **New SkeletonProfileHumanoid** (the mapping to `mixamorig_*` bones auto-fills).
3. **Reimport**.
4. **Expected outcome — this is the contract the gameplay code relies on:** the skeleton node is renamed to `GeneralSkeleton` with *Access as Unique Name* enabled, and bones are renamed to profile names (`Hips`, `Spine`, `LeftUpperLeg`, ...). Unmapped extras (e.g. `mixamorig_HeadTop_End`) keep their names — harmless. Do not "fix" the rename.
5. Instance the glb under `Visuals/` in `player.tscn` / `colonist.tscn`. No code changes are needed: the animation controllers re-home `GeneralSkeleton`'s unique name at runtime so `%GeneralSkeleton:<bone>` tracks bind.

## Phase 5: Import animations in Godot (the half that causes T-pose when skipped)

Per animation `.fbx` in `assets/mixamo/`:

1. Import dock on the file: **FBX Importer = ufbx**. (FBX2glTF requires an external converter binary; if it is missing you get `FBX conversion to glTF failed with error: 127`.)
2. **Advanced Import Settings -> Skeleton3D -> Retarget -> Bone Map = New SkeletonProfileHumanoid** — the **same profile** as the model. This renames the animation's bones to match the model and rewrites track paths to `%GeneralSkeleton:<BoneName>`.
3. In the dialog's animation list: **Save to File -> Enabled**, path `res://assets/mixamo/<Name>.tres`.
4. **Reimport**. The extracted `.tres` now contains `%GeneralSkeleton:Hips`-style tracks.

## Phase 6: Register in the shared library

1. Open `player.tscn`, select the `AnimationPlayer`, and edit the `mixamo` library (Animation panel).
2. Add the extracted animation under its **canonical key — case-sensitive**: `Idle`, `Walk`, `Sprint`, `Jump`, `Interact`, `Digging`.
3. Save `mixamo.res` (same file). If its uid changes, let the editor update `player.tscn`/`colonist.tscn` references and re-save them.
4. Missing keys degrade gracefully at runtime: `Sprint` falls back to `Walk`, anything else falls back to `Idle`, with a one-time warning per name.

JobDefs pick work animations via `work_animation` on the JobDef `.tres` (default on `data/jobs/job_def.gd` is `&"Interact"`); the key must match the library exactly, including capitalization.

---

## Verification

Run a scene with the character visible. **No `couldn't resolve track` warnings in the console means the whole pipeline is healthy.** That warning is the T-pose signature: the library's tracks do not match the scene's skeleton.

## Troubleshooting

- **Character frozen in T-pose:** an animation was imported *without* the BoneMap (tracks address `Skeleton3D:mixamorig_*`), so bones do not match the retargeted model. Redo Phase 5.
- **`FBX conversion to glTF failed with error: 127`:** the file's importer is FBX2glTF and the external binary is missing. Switch to ufbx (Phase 5 step 1).
- **One-time `missing from 'mixamo' library` warning:** the requested key is absent or miscapitalized (`interact` vs `Interact`). Check Phase 6 key naming.
- **Invisible skinned mesh after import:** meshes lost their skeleton binding — usually caused by renaming/moving the skeleton after import, or by applying a BoneMap to the model with mismatched weights. Re-import and let the importer do the renaming.
- **Hair stretching to feet:** hair/eyelashes weighted across the whole armature. Give them 100% weight on `mixamorig:Head` (Phase 3 step 5).
- **Magenta textures:** texture not plugged into Principled BSDF Base Color before glTF export.
