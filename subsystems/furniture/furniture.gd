class_name Furniture
extends Node3D
## Runtime instance of one placed furniture item (GDD §7.2). Holds a back-ref
## to its definition for static data (mesh, display_name, hp_max, etc.); only
## per-instance state lands here as subsystems are built. Placement bookkeeping
## (anchor → node maps, cell ownership) stays in FurnitureLayer.
##
## Capabilities deferred: Functional Rooms counting (§7.8), storage/door/bed
## component slots (§7.10–§7.11). Crafting (§7.9) ships as the CraftingStation
## child component (see subsystems/crafting/). Combat HP (§7.7) ships as
## health_component, attached in _setup_health_component() when def.hp > 0.

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

## Combat HP (ARCH combat.md, GDD §7.2/§7.7) — null for buildables whose def.hp
## is 0 (purely decorative furniture carries no combat HP).
var health_component: HealthComponent = null


func _ready() -> void:
	if def_id != "":
		add_to_group(StringName(def_id))
	add_to_group(&"furniture")
	# 1. Tag Groups Registration: Registers node into groups based on definition tags.
	_register_tag_groups()
	# 2. HealthComponent Setup: Attaches combat HP sized from def.hp so weapons
	# can damage/destroy this buildable through the same take_damage() contract
	# player/colonist/enemy combat already uses.
	_setup_health_component()


## Returns whether this furniture instance carries the specified classification tag.
func has_tag(tag: String) -> bool:
	if def == null:
		return false
	return def.tags.has(tag)


## Returns all classification tags declared on this furniture's definition.
func get_tags() -> Array[String]:
	if def == null:
		return []
	return def.tags


func _register_tag_groups() -> void:
	## Auxiliary: Registers the node into string groups matching its definition tags.
	if def == null:
		return
	for tag: String in def.tags:
		if tag != "":
			add_to_group(StringName(tag))
			add_to_group(StringName("tag_%s" % tag))


func _setup_health_component() -> void:
	## Auxiliary: Attaches a HealthComponent sized from def.hp, skipped for
	## buildables with no combat HP (def.hp <= 0).
	if def == null or def.hp <= 0:
		return
	health_component = HealthComponent.new()
	health_component.name = "HealthComponent"
	add_child(health_component)
	health_component.setup(def.hp)
	health_component.entity_died.connect(_on_health_component_died)


func _on_health_component_died(_entity: Node) -> void:
	destroy()


## Forwards damage to health_component (a no-op for buildables with no combat HP).
func take_damage(amount: int, source: Node = null) -> void:
	if health_component != null:
		health_component.take_damage(amount, source)


## Removes this instance via its owning FurnitureLayer (queue_free + registry
## cleanup through the existing EventBus.furniture_removed consumers), or falls
## back to a direct queue_free + emit when no FurnitureLayer is reachable (e.g.
## bare unit-test construction). Mirrors WildFlora._destroy_flora().
func destroy() -> void:
	var cells := get_footprint_cells()
	var anchor: Vector3i = cells[0] if not cells.is_empty() else Vector3i(
		int(round(global_position.x)), int(round(global_position.y)), int(round(global_position.z)))
	var fl := _find_furniture_layer()
	if fl != null:
		fl.remove_at(anchor)
	else:
		queue_free()
		EventBus.furniture_removed.emit(def_id, anchor)


func _find_furniture_layer() -> FurnitureLayer:
	## Auxiliary: Resolves BuildController's FurnitureLayer reference.
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.current_scene
	if root != null:
		var ctrl := root.find_child("BuildController", true, false) as BuildController
		if ctrl != null and ctrl.furniture_layer != null:
			return ctrl.furniture_layer
	return null


## All voxel cells this furniture occupies. Derived from global_position and
## def.dimensions so ColonistAI can query the full footprint without reaching
## into FurnitureLayer's internal maps.
func get_footprint_cells() -> Array[Vector3i]:
	if def == null:
		return []
	# Non-FurnitureDef buildables (blocks) occupy a single cell and use the
	# voxel-corner convention — the node sits AT the cell corner (a block
	# blueprint is positioned at Vector3(anchor)), not at a footprint center,
	# so the center-based math below would land one cell off. Runs for
	# blueprints too (Blueprint extends Furniture and its def is the TARGET's
	# def) — that's how colonist job pathing reaches here with a BlockDef.
	if not (def is FurnitureDef or def is WildFloraDef):
		return [Vector3i(
			int(round(global_position.x)),
			int(round(global_position.y)),
			int(round(global_position.z)))]
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


## Returns the first capability of the given type from the furniture's def,
## or null if absent. Uses is_instance_of for inheritance-correct matching.
static func get_capability(furniture: Furniture, type: Script) -> FurnitureCapability:
	if furniture == null or not (furniture.def is FurnitureDef):
		return null
	var fdef := furniture.def as FurnitureDef
	for prop in fdef.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var val: Variant = fdef.get(prop.name)
		if val is FurnitureCapability and is_instance_of(val, type):
			return val as FurnitureCapability
	return null


# --- SaveSystem contract -----------------------------------------------------
# FurnitureLayer aggregates one record per item (def_id + anchor + yaw, see
# FurnitureLayer.serialize). `storage` captures the per-instance contents of a
# storage-capable piece (crate/shelf) via its StorageInventory child.
# `cap_state` captures generalized per-component state implementing ICapabilityComponent.

## Snapshot the canonical def id, the capability state bag, plus, when present,
## the StorageInventory child's item stacks and child capability component states.
func serialize() -> Dictionary:
	var storage = get_node_or_null("StorageInventory") as StorageInventory
	var cap_state: Dictionary = {}
	for child in get_children():
		if child.has_method("serialize_state"):
			cap_state[child.name] = child.serialize_state()
	return {
		"def_id": def_id,
		"storage": storage.serialize() if storage != null else null,
		"state": state.duplicate(true),
		"cap_state": cap_state,
	}


## Restore def_id, the capability state bag, and any component state.
## Restores storage contents with backward-compatibility for legacy "storage" key.
func deserialize(data: Dictionary) -> void:
	var old_def_id := def_id
	def_id = data.get("def_id", def_id)
	if old_def_id != def_id:
		if old_def_id != "" and is_in_group(StringName(old_def_id)):
			remove_from_group(StringName(old_def_id))
		if def_id != "":
			add_to_group(StringName(def_id))
	var saved_state: Dictionary = data.get("state", {})
	state = saved_state.duplicate(true)

	var cap_state: Dictionary = data.get("cap_state", {})
	# 1. Compatibility Fallback: Resolve legacy storage key if StorageInventory is not in cap_state.
	if not cap_state.has("StorageInventory") and data.get("storage") != null:
		cap_state["StorageInventory"] = data.get("storage")

	for child in get_children():
		if child.has_method("deserialize_state") and cap_state.has(child.name):
			child.deserialize_state(cap_state[child.name])
		elif child is StorageInventory and cap_state.has(child.name):
			(child as StorageInventory).deserialize(cap_state[child.name])
