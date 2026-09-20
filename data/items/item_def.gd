class_name ItemDef
extends Resource

@export var id: String = ""
@export var weight: float = 0.0
@export var icon: Texture2D = null
## PackedScene (e.g. .glb) rendered when this item exists as a WorldItem in the world.
## Takes precedence over mesh.
@export var scene: PackedScene = null
## 3D visual mesh rendered when this item exists as a WorldItem in the world.
## If null and scene is null, WorldItem falls back to a default prototype box.
@export var mesh: Mesh = null
## Optional material override applied to the world item mesh.
@export var material: Material = null
## Scale factor applied to the world item visual mesh/scene and collision box.
@export var visual_scale: Vector3 = Vector3.ONE
## Loose categorization tags (e.g. ["tool", "axe"]). Read via
## Inventory.has_item_tag; the "tool" tag marks carried tools that job cleanup
## (HaulingJobDef.on_end's surplus dump) must leave with the colonist. Author
## tools with a small weight so one doesn't clog the carry capacity.
@export var tags: Array[String] = []

## Nullable equippable capability. If set, this item can be held/equipped by
## players or colonists.
@export var equippable: EquippableParams = null

## Nullable food capability. If set, this item can be consumed to restore hunger.
@export var food: FoodParams = null

## Nullable wearable capability. If set, this item can be worn as visual gear
## (armor, clothing, headwear, footwear) via rigid parts or skinned meshes.
@export var wearable: WearableParams = null


## Player-facing name: the authored resource_name, else the id. The one place this
## rule lives, so every list, tooltip and message names an item the same way.
func get_display_name() -> String:
	return resource_name if resource_name != "" else id


func is_equippable() -> bool:
	return equippable != null


func is_food() -> bool:
	return food != null


func is_wearable() -> bool:
	return wearable != null


## Returns true if this item carries the given tag. Used by Equipment to
## validate slot eligibility without exposing the tags array directly.
func has_tag(tag: String) -> bool:
	return tags.has(tag)
