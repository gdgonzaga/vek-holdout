class_name Harvestable
extends Node
## Capability component for harvestable furniture (GDD §6.10, ARCH "Harvesting").
## Attached under a Furniture by FurnitureLayer when its def declares harvest_params
## — the CraftingStation/StorageInventory pattern.
##
## Tracks work_done toward completion and is_marked_for_harvest (for colonist job
## dispatch). When complete() is invoked, grants yields to the harvesting actor
## and removes the furniture node via FurnitureLayer.

const STATE_KEY := "harvest"

var _furniture: Furniture:
	get: return get_parent() as Furniture


## Back-ref to the definition's HarvestParams.
func params() -> HarvestParams:
	if _furniture == null or _furniture.def == null:
		return null
	var fdef := _furniture.def as FurnitureDef
	return fdef.harvest_params if fdef != null else null


## This furniture's anchor cell (the footprint corner; Colony's job dedupe key).
func anchor_cell() -> Vector3i:
	if _furniture == null:
		return Vector3i.ZERO
	var cells := _furniture.get_footprint_cells()
	return cells[0] if not cells.is_empty() else Vector3i.ZERO


## Whether this resource is marked for colonist harvest.
func is_marked_for_harvest() -> bool:
	return _harvest_state().get("is_marked", false)


## Set or clear the harvest mark. Emits EventBus.harvest_mark_toggled so Colony
## can add/remove the job from JobBoard.
func set_marked(marked: bool) -> void:
	var state := _harvest_state()
	if state.get("is_marked", false) == marked:
		return
	state["is_marked"] = marked
	if _furniture != null:
		_furniture.state[STATE_KEY] = state
		if marked:
			GameLog.info("Marked %s for harvest" % _furniture.label)
		else:
			GameLog.info("Unmarked %s from harvest" % _furniture.label)
	EventBus.harvest_mark_toggled.emit(_furniture, anchor_cell(), marked)


## Toggle marking on/off.
func toggle_mark() -> void:
	set_marked(not is_marked_for_harvest())


## Accumulated work on this node in seconds.
func work_done() -> float:
	return _harvest_state().get("work_done", 0.0)


## Update accumulated work.
func set_work_done(amount: float) -> void:
	var state := _harvest_state()
	state["work_done"] = amount
	if _furniture != null:
		_furniture.state[STATE_KEY] = state


## Resolve the harvest: grant yields to actor's inventory and remove the node.
## Returns true if successfully harvested.
func complete(actor: Node) -> bool:
	var p := params()
	if p == null:
		return false
	var pocket := _pocket_of(actor)
	for entry in p.yields:
		if entry == null or entry.item_def == null:
			continue
		var id := entry.item_def.id
		if pocket != null:
			pocket.add(id, entry.count)
	if _furniture != null:
		GameLog.info("Harvested %s" % _furniture.label)
	var anchor := anchor_cell()
	var fl := _find_furniture_layer()
	if fl != null:
		fl.remove_at(anchor)
	else:
		var def_id := _furniture.def_id if _furniture != null else ""
		if _furniture != null and is_instance_valid(_furniture):
			_furniture.queue_free()
		EventBus.furniture_removed.emit(def_id, anchor)
	return true


func _pocket_of(actor: Node) -> Inventory:
	var colonist := actor as Colonist
	if colonist != null and colonist.inventory != null:
		return colonist.inventory
	var player := actor as Player
	if player != null and player.inventory != null:
		return player.inventory
	return null


func _find_furniture_layer() -> FurnitureLayer:
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.current_scene
	if root != null:
		var ctrl := root.find_child("BuildController", true, false) as BuildController
		if ctrl != null and ctrl.furniture_layer != null:
			return ctrl.furniture_layer
	return null


func _harvest_state() -> Dictionary:
	if _furniture == null:
		return {}
	if not _furniture.state.has(STATE_KEY):
		_furniture.state[STATE_KEY] = {"is_marked": false, "work_done": 0.0}
	return _furniture.state[STATE_KEY]
