# How To: Transfer models from the animpic / Polygon-Mega bundle

> End-to-end guide for taking a 3D model from the `tmp/Polygon-Mega Survival
> Construction/` asset bundle and making it render correctly (with textures) as
> furniture in the game. Covers why models come out white, the atlas model the
> bundle uses, and the per-furniture fix.
>
> **Prerequisites:** a `FurnitureDef` resource under `res://data/furniture/`
> referencing the model's extracted `.mesh` (see `data/furniture/workbench.tres`
> as the canonical example).

---

## Why models render white

The bundle was originally a Unity asset converted to glTF by `FBX2glTF`. The
conversion left each model's `.gltf` pointing at per-model image files
(`NewPallet_v1.png`, or GUID-named `.jpg`s) that **were never shipped** — the
URIs are dangling leftovers from the FBX's embedded textures.

Godot imports each `.gltf` with `materials/extract=0`, so the converted
material is embedded as a sub-resource inside the extracted `.mesh`. But that
material's `albedo_texture` resolves to the missing image → null → the surface
renders with Godot's default flat-white material.

**Changing the glTF import settings will not fix this** — the image is missing
upstream, not mis-extracted. `materials/extract=1` would emit textureless
`.material` files for the same reason.

## The atlas model (the actual fix)

The bundle is authored around **one shared texture atlas**: `MainTexture.png`.
Every model's UVs are laid out into that atlas. The bundle's own
`Prefab/*.prefab.scn` files confirm the intended assembly: extracted `.mesh` +
`MainMaterial.material` applied as a material override. So the "texture" for
any model from this bundle is the same file: `MainTexture.png`.

The project already has the atlas imported:
- `res://assets/animpic-mega-survival-construction/MainTexture.png` (uid
  `uid://cvn2otun3im08`)
- `res://assets/animpic-mega-survival-construction/MainMaterial.material` (a
  ready-made `StandardMaterial3D` pointing at the atlas — optional; see below)

The runtime (`subsystems/build/furniture_layer.gd`) and the editor preview
(`addons/voxel_paint/furniture_authoring.gd`) both build a
`StandardMaterial3D` inline from `def.texture` and apply it as
`material_override`. So **the fix is one line in the furniture `.tres`**: set
`texture` to the atlas.

## How to fix a furniture def (the repeatable step)

Open the furniture's `.tres` (e.g. `data/furniture/workbench.tres`) and add the
atlas as an `ext_resource`, then assign it to `texture`:

```
[gd_resource type="Resource" script_class="FurnitureDef" format=3 ...]

[ext_resource type="ArrayMesh" ... path="res://assets/animpic-mega-survival-construction/<model>/<model>.mesh" id="1_mesh"]
[ext_resource type="Script" ... path="res://data/furniture/furniture_def.gd" id="1_script"]
[ext_resource type="Texture2D" uid="uid://cvn2otun3im08" path="res://assets/animpic-mega-survival-construction/MainTexture.png" id="2_tex"]

[resource]
script = ExtResource("1_script")
...
mesh = ExtResource("1_mesh")
texture = ExtResource("2_tex")        # <-- this is the fix
...
```

That's it. No re-import needed — the runtime rebuilds the material at load.

**For non-atlas textures** (e.g. `storage_crate.tres` deliberately uses
`TerrainTextures/Sand.png` instead of the atlas), point `texture` at whichever
PNG is appropriate — the workflow is identical, just a different path.

## When to use `MainMaterial.material` instead

The atlas is enough for albedo. Use the ready-made `MainMaterial.material`
instead of the bare PNG **only** if you need its specific PBR params
(metallic ≈ 0.4, roughness ≈ 0.27). The furniture system does not read a
`material` field today (`BuildableDef` only has `texture`), so using the
material would require either:

- extending `BuildableDef` with a `material: Material` export and teaching
  `furniture_layer.gd` / `furniture_authoring.gd` to prefer it, or
- copying the params into a `StandardMaterial3D` you build inline.

For furniture, the bare atlas texture is almost always enough. Skip the
material unless you can see a visual difference.

## Transferring a brand-new model from the bundle

If a model isn't already copied into `assets/`:

1. **Pick the extracted mesh.** Under
   `tmp/Polygon-Mega Survival Construction/Models/<category>/extracted/`,
   choose `<Model>.<Model>.mesh`. (The `Props/`, `Other/`, etc. categories
   mirror the bundle's folder layout.)
2. **Copy it into the project** under
   `res://assets/animpic-mega-survival-construction/<model_name>/`. Godot will
   generate the `.uid` and `.import` on first open.
3. **Create a `FurnitureDef` `.tres`** under `res://data/furniture/` (see
   step 4 below for the easy Inspector-driven way).
4. **Author it into a map** via the Voxel Paint plugin's Furniture mode. It
   will appear textured in both the editor preview and at runtime.

### Setting `mesh` and `texture` via the Inspector (no text editing)

`mesh` and `texture` are both `@export` fields on `BuildableDef` (see
`data/buildables/buildable_def.gd`), so the Inspector can set them with zero
hand-editing of the `.tres`. This is the recommended way — Godot manages the
`ext_resource` declarations and UIDs for you.

1. **Create the `.tres`** in the FileSystem dock:
   right-click `res://data/furniture/` → **New → Resource** → search
   `FurnitureDef` → save as `<id>.tres`.
2. **Open it** (double-click) — the Inspector shows the `FurnitureDef` fields.
3. **Set the mesh** — drag the extracted `.mesh` from the FileSystem dock onto
   the **Mesh** property, or click the property's `<empty>` → **Quick Load** →
   pick the `.mesh`.
4. **Set the texture** — same drag-drop onto **Texture**, or click → **Quick
   Load** → pick
   `res://assets/animpic-mega-survival-construction/MainTexture.png`. (For
   non-atlas models like `storage_crate`, drop the specific PNG instead.)
5. **Fill the rest** — `id`, `display name`, `hp`, `dimensions`,
   `material_cost`, etc. Set `unlocked_by_default = true` if it should be
   available without earning an unlock.
6. **Save** (`Ctrl+S`). Done — the `.tres` now references the mesh and atlas
   by UID, managed entirely by Godot.

To fix an **existing** white-textured def, skip to step 3: open the `.tres`,
drop `MainTexture.png` onto the **Texture** slot, save.

### Setting `mesh` and `texture` by editing the `.tres` (alternative)

If you prefer editing the text (e.g. for bulk changes or copy-paste from
another def), add an `ext_resource` for the atlas and assign it to `texture`:

```
[ext_resource type="Texture2D" uid="uid://cvn2otun3im08" path="res://assets/animpic-mega-survival-construction/MainTexture.png" id="2_tex"]

[resource]
...
mesh = ExtResource("1_mesh")
texture = ExtResource("2_tex")        # <-- this is the fix
```

The uid `cvn2otun3im08` is stable for `MainTexture.png` as long as the
`.import` file isn't deleted; Godot will keep it in sync on re-import.

## What to ignore in the bundle

- **The `.gltf` files' material/texture references** — dangling, unusable.
- **`materials/extract` and `gltf/embedded_image_handling` import settings** —
  cannot recover a texture that isn't in the bundle.
- **`*.unitypackage.failed_import`** — dead Unity SRP/HDRP/URP packages.
- **The `.prefab.scn` files** — Godot `PackedScene`s with `res://Assets/...`
  (capital A) paths that don't resolve in this project. Useful only as a
  reference for how each model is meant to be assembled (mesh + MainMaterial +
  collider). Not worth re-pathing for one-off furniture.

## Reference: where things live

| What | Path |
|---|---|
| Atlas texture (the fix) | `res://assets/animpic-mega-survival-construction/MainTexture.png` |
| Ready-made material (optional) | `res://assets/animpic-mega-survival-construction/MainMaterial.material` |
| Example furniture def (canonical) | `res://data/furniture/workbench.tres` |
| Example furniture def (non-atlas texture) | `res://data/furniture/storage_crate.tres` |
| Runtime material builder | `subsystems/build/furniture_layer.gd` (`_create_furniture_node`) |
| Editor preview material builder | `addons/voxel_paint/furniture_authoring.gd` (`place`) |
| Bundle source (reference only) | `tmp/Polygon-Mega Survival Construction/` |
