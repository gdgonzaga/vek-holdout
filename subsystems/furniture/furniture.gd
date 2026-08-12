class_name Furniture
extends Node3D
## Runtime instance of one placed furniture item (GDD §7.2). Holds a back-ref
## to its definition for static data (mesh, display_name, hp_max, etc.); only
## per-instance state lands here as subsystems are built. Placement bookkeeping
## (anchor → node maps, cell ownership) stays in FurnitureLayer.
##
## Capabilities deferred: HP/damage (§7.7), Functional Rooms counting (§7.8),
## crafting/storage/door/bed component slots (§7.9–§7.11) — none exist yet.

## Canonical def id (e.g. "workbench"). Replaces the old node.name parsing in
## FurnitureLayer.remove_at; also the save/load key once persistence lands.
@export var def_id: String = ""

## Back-ref to the definition (runtime only — not serialized). Read static
## data through this (def.hp, def.dimensions) so .tres balance changes
## propagate to already-placed instances without respawning.
var def: BuildableDef = null

## Human-readable label for menus/HUD. Computed from the def via getter so the
## UI never references def directly.
@export var label: String :
	get:
		return def.display_name if def != null else ""


# --- SaveSystem contract -----------------------------------------------------
# FurnitureLayer aggregates one record per item (def_id + anchor + yaw, see
# FurnitureLayer.serialize). `storage` captures the per-instance contents of a
# storage-capable piece (crate/shelf) via its StorageInventory child.

## Snapshot the canonical def id plus, when present, the StorageInventory
## child's item stacks. Non-storage furniture returns storage = null.
func serialize() -> Dictionary:
	var storage = get_node_or_null("StorageInventory") as StorageInventory
	return {
		"def_id": def_id,
		"storage": storage.serialize() if storage != null else null,
	}


## Restore def_id and, when a StorageInventory child exists and the data carries
## a storage block, its contents. Safe to call right after FurnitureLayer.spawn
## (which creates the StorageInventory child) as well as standalone.
func deserialize(data: Dictionary) -> void:
	def_id = data.get("def_id", def_id)
	var storage_data: Variant = data.get("storage", null)
	if storage_data == null:
		return
	var storage = get_node_or_null("StorageInventory") as StorageInventory
	if storage != null:
		storage.deserialize(storage_data)
