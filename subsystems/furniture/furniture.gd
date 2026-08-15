class_name Furniture
extends Node3D
## Runtime instance of one placed furniture item (GDD §7.2). Holds a back-ref
## to its definition for static data (mesh, display_name, hp_max, etc.); only
## per-instance state lands here as subsystems are built. Placement bookkeeping
## (anchor → node maps, cell ownership) stays in FurnitureLayer.
##
## Capabilities deferred: HP/damage (§7.7), Functional Rooms counting (§7.8),
## storage/door/bed component slots (§7.10–§7.11). Crafting (§7.9) ships as the
## CraftingStation child component (see subsystems/crafting/).

## Canonical def id (e.g. "workbench"). Replaces the old node.name parsing in
## FurnitureLayer.remove_at; also the save/load key once persistence lands.
@export var def_id: String = ""

## Back-ref to the definition (runtime only — not serialized). Read static
## data through this (def.hp, def.dimensions) so .tres balance changes
## propagate to already-placed instances without respawning.
var def: BuildableDef = null

## Per-instance capability state bag: { component-owned key: saved value }.
## Capability components (CraftingStation's order under "craft_order"; the
## planned Growable) read/write their keys here so Furniture.serialize never
## grows a branch per component. Empty for plain furniture; round-trips below.
var state: Dictionary = {}

## Human-readable label for menus/HUD. Computed from the def via getter so the
## UI never references def directly.
@export var label: String:
	get:
		return def.display_name if def != null else ""


## All voxel cells this furniture occupies. Derived from global_position and
## def.dimensions so ColonistAI can query the full footprint without reaching
## into FurnitureLayer's internal maps.
func get_footprint_cells() -> Array[Vector3i]:
	if def == null:
		return []
	var yaw := int(round(rotation_degrees.y / 90.0)) % 4
	var w: int = def.dimensions.x
	var d: int = def.dimensions.z
	if yaw % 2 != 0:
		var t := w; w = d; d = t
	# Reverse of world_origin: anchor is footprint corner, pos is footprint center
	var ax := int(floor(global_position.x - float(w) * 0.5))
	var ay := int(floor(global_position.y))
	var az := int(floor(global_position.z - float(d) * 0.5))
	var cells: Array[Vector3i] = []
	for dx in range(w):
		for dz in range(d):
			cells.append(Vector3i(ax + dx, ay, az + dz))
	return cells


# --- SaveSystem contract -----------------------------------------------------
# FurnitureLayer aggregates one record per item (def_id + anchor + yaw, see
# FurnitureLayer.serialize). `storage` captures the per-instance contents of a
# storage-capable piece (crate/shelf) via its StorageInventory child.

## Snapshot the canonical def id, the capability state bag, plus, when present,
## the StorageInventory child's item stacks. Non-storage furniture returns
## storage = null.
func serialize() -> Dictionary:
	var storage = get_node_or_null("StorageInventory") as StorageInventory
	return {
		"def_id": def_id,
		"storage": storage.serialize() if storage != null else null,
		"state": state.duplicate(true),
	}


## Restore def_id, the capability state bag, and, when a StorageInventory child
## exists and the data carries a storage block, its contents. Safe to call
## right after FurnitureLayer.spawn (which creates the StorageInventory child)
## as well as standalone.
func deserialize(data: Dictionary) -> void:
	def_id = data.get("def_id", def_id)
	var saved_state: Dictionary = data.get("state", {})
	state = saved_state.duplicate(true)
	var storage_data: Variant = data.get("storage", null)
	if storage_data == null:
		return
	var storage = get_node_or_null("StorageInventory") as StorageInventory
	if storage != null:
		storage.deserialize(storage_data)
