# How To: Author Furniture with Pluggable Capabilities

> Complete guide for authoring furniture definitions, configuring existing capability parameters (storage, crafting, turrets, lights, beds, farm plots), and adding new pluggable capability types in *Vek: Holdout*.
>
> **Prerequisites:** Familiarity with Godot `.tres` text resources, `docs/architecture/build.md`, and `docs/architecture/data-schemas.md`.

---

## 1. Core Architecture Overview

In *Vek: Holdout*, free-standing structures that occupy space in the world are defined as **`FurnitureDef`** resources. Rather than creating subclasses for every distinct furniture archetype (e.g., `BedDef`, `StorageDef`, `TurretDef`), the game uses a **pluggable composition architecture**:

```
FurnitureDef (e.g. data/furniture/colonist_bed.tres)
├── id: "colonist_bed"
├── dimensions: Vector3i(1, 1, 2)
├── mesh / scene / texture / hp / material_cost
├── tags: ["bed"]
└── Capability Parameters (extends FurnitureCapability)
    ├── bed_params: BedParams                <-- Attached
    ├── storage_params: null                 <-- Inactive
    ├── crafting_params: null                <-- Inactive
    └── ...
```

### How the Runtime Instantiates Furniture

When `FurnitureLayer.spawn(def, anchor, rotation)` creates a furniture instance:
1. **Root Creation**: Spawns a root `Furniture` node with physical collision (Layer 1 World trimesh) and build selection collision (Layer 5 Build box shape).
2. **Interaction Option Pass**: Calls `collect_action_options()` on all active capabilities and merges them with `fdef.action_options` into a single `InteractionComponent`.
3. **Capability Component Pass**: Introspects `fdef.get_property_list()` for non-null `FurnitureCapability` sub-resources. For each active capability, `FurnitureLayer` executes the factory registered in its static capability registry (e.g., spawning `BedComponent`, `StorageInventory`, or `CraftingStation`).
4. **Tag Registration**: Adds the node to scene groups matching `def.tags` (e.g., group `&"bed"` for colonist AI queries).
5. **State Protocol**: Stateful components implement `ICapabilityComponent` (`serialize_state` / `deserialize_state`), which `Furniture.serialize()` and `Furniture.deserialize()` invoke automatically.

---

## 2. Available Built-In Capabilities

| Capability Resource | Runtime Component | Purpose / Behavior |
|---|---|---|
| **`BedParams`** | `BedComponent` | Rest destination for colonists (GDD §6.8). Manages transient reservations and occupancy. |
| **`StorageParams`** | `StorageInventory` | Item container with weight capacity, priority, and item/tag filters. |
| **`CraftingParams`** | `CraftingStation` | Crafting station offering a recipe list with order queuing. |
| **`TurretParams`** | `TurretComponent` | Automated defense targeting enemies, aiming barrels, and firing projectiles. |
| **`LightParams`** | `LightSourceComponent` | Emits dynamic light with configurable color, range, energy, and shadows. |
| **`FarmPlotParams`** | `Growable` + `Harvestable` | Crop growing plot supporting hydration, tending, visual stages, and dynamic harvesting. |
| **`HarvestParams`** | `Harvestable` | Static resource node felled by player/colonists (e.g. resource pillars). |
| **`ItemDispenserParams`** | Direct data query | Gives predefined items upon interaction (via `GiveItemAction`). |

---

## 3. Step-by-Step: Authoring Furniture with Existing Capabilities

### Example A: Authoring a Colonist Bed (`colonist_bed.tres`)

1. Create a new `.tres` in `res://data/furniture/colonist_bed.tres`.
2. Set `script = ExtResource("res://data/furniture/furniture_def.gd")`.
3. Configure dimensions, mesh, and tags:
   - `id`: `"colonist_bed"`
   - `display_name`: `"Colonist Bed"`
   - `dimensions`: `Vector3i(1, 1, 2)` (1 wide, 1 tall, 2 deep)
   - `tags`: `["bed"]` *(Critical: allows `ColonistBrain` to find this node for the sleep need)*
4. Attach an inline `BedParams` sub-resource:
   - `sleep_offset`: `Vector3(0, 0, 0)` (offset from center where the colonist lies)
   - `rest_rate_per_second`: `0.15` (recovers 15% of rest need per real second)
5. Configure `material_cost` and `build_time`.

```ini
[gd_resource type="Resource" script_class="FurnitureDef" format=3]

[ext_resource type="ArrayMesh" path="res://assets/animpic-mega-survival-construction/bed1/SM_Bed_01.SM_Bed_01.mesh" id="1_mesh"]
[ext_resource type="Script" path="res://data/furniture/furniture_def.gd" id="2_fdef"]
[ext_resource type="Texture2D" path="res://assets/animpic-mega-survival-construction/MainTexture.png" id="3_tex"]
[ext_resource type="Script" path="res://data/capability_params/bed_params.gd" id="4_bparams"]

[sub_resource type="Resource" id="Resource_bed"]
script = ExtResource("4_bparams")
sleep_offset = Vector3(0, 0, 0)
rest_rate_per_second = 0.15

[resource]
script = ExtResource("2_fdef")
id = "colonist_bed"
display_name = "Colonist Bed"
hp = 80
dimensions = Vector3i(1, 1, 2)
mesh = ExtResource("1_mesh")
texture = ExtResource("3_tex")
tags = Array[String](["bed"])
bed_params = SubResource("Resource_bed")
unlocked_by_default = true
build_time = 6.0
```

---

### Example B: Authoring a Storage Container (`shelf.tres`)

1. Create `res://data/furniture/shelf1.tres`.
2. Configure `action_options` with storage actions:
   - `open_storage_action_option.tres`
   - `configure_storage_action_option.tres`
3. Attach `StorageParams`:
   - `capacity`: `100.0` (weight limit in kg)
   - `priority`: `3` (hauling order priority 1–5)
   - `allowed_item_ids`: Optional whitelist of item IDs.
   - `allowed_tags`: Optional whitelist of item tags (e.g. `["food"]`).

---

### Example C: Authoring a Farm Plot (`growing_trough.tres`)

1. Create `res://data/furniture/growing_trough.tres`.
2. Attach `FarmPlotParams`:
   - `allowed_crops`: `[]` (empty = accept all crops from `CropLibrary`)
   - `crop_slots`: `1`
   - `growth_rate_multiplier`: `1.0` (set higher, e.g. `1.2`, for heated/fertilized troughs)
   - `hydration_mode`: `"manual"`
3. **Do not** add `HarvestParams` or `action_options` manually — `FarmPlotParams.collect_action_options()` automatically supplies `inspect_crop`, `select_crop`, and `toggle_harvest` options, while `Growable` handles yields dynamically via `CropDef`.

---

## 4. Step-by-Step: Adding a New Custom Capability

When adding a brand new gameplay capability (e.g. `MedicalParams` / `MedicalComponent` for clinic beds):

### Step 1: Define the Parameter Resource
Create `data/capability_params/medical_params.gd` extending `FurnitureCapability`:

```gdscript
class_name MedicalParams
extends FurnitureCapability
## Capability parameters for medical treatment furniture.

@export var healing_rate_per_second: float = 5.0
@export var sterile_tier: int = 1

## Optional: inject custom action options into InteractionComponent
func collect_action_options() -> Array[ActionOption]:
	return [preload("res://data/action_options/treat_patient_action_option.tres")]
```

---

### Step 2: Add the Export Variable to `FurnitureDef`
In `data/furniture/furniture_def.gd`:

```gdscript
## Medical treatment capability
@export var medical_params: MedicalParams
```

> [!NOTE]
> Because `FurnitureLayer` uses property introspection, adding the typed `@export` variable to `FurnitureDef` is all that is required for the resource schema. No changes to `BuildableDef` or existing `.tres` files are needed.

---

### Step 3: Create the Runtime Component
Create `subsystems/medical/medical_component.gd`:

```gdscript
class_name MedicalComponent
extends Node

var patient: Colonist = null

## Unified capability fetch helper
func params() -> MedicalParams:
	var furniture := get_parent() as Furniture
	return Furniture.get_capability(furniture, MedicalParams) as MedicalParams

# --- SaveSystem Protocol (ICapabilityComponent) ---

func serialize_state() -> Dictionary:
	return {
		"patient_id": patient.name if patient != null else ""
	}

func deserialize_state(data: Dictionary) -> void:
	var pid: String = data.get("patient_id", "")
	# Restore patient reference...
```

---

### Step 4: Register the Factory in `FurnitureLayer`
In `subsystems/build/furniture_layer.gd`, register the component factory inside `_ensure_capability_registry()`:

```gdscript
_register_capability_factory(MedicalParams, func(_params: MedicalParams, furniture: Furniture) -> void:
	var med := MedicalComponent.new()
	med.name = "MedicalComponent"
	furniture.add_child(med))
```

---

### Step 5: Query the Capability at Runtime
Use the static helper `Furniture.get_capability()`:

```gdscript
var med_params := Furniture.get_capability(furniture, MedicalParams) as MedicalParams
if med_params != null:
	print("Medical tier: %d" % med_params.sterile_tier)
```

---

## 5. Authoring Rules & Invariants

1. **Pure Data Resources**: `FurnitureCapability` sub-resources must remain pure data (no node spawning or scene references). All component instantiation belongs in `FurnitureLayer`'s static registry.
2. **Dynamic Options via `collect_action_options()`**: If a capability provides E-menu options, implement `collect_action_options() -> Array[ActionOption]` on the capability resource. Do not manually mutate `InteractionComponent` from components.
3. **No `HarvestParams` on Farm Plots**: Farm plot yields and work duration come dynamically from `CropDef` via `Growable`. Never author `HarvestParams` on a farm plot.
4. **Group Tags via `def.tags`**: Add entity query tags (e.g. `["bed"]`, `["storage"]`) directly in `FurnitureDef.tags`. `Furniture._register_tag_groups()` binds them to Godot groups automatically on spawn.
5. **Stateful Component Protocol**: Implement `serialize_state() -> Dictionary` and `deserialize_state(data: Dictionary) -> void` on any component requiring save persistence. `Furniture.serialize()` and `Furniture.deserialize()` manage child state automatically.
