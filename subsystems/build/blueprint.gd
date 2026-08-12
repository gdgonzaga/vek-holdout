class_name Blueprint
extends Furniture
## Non-physical "plan" of a buildable (GDD §7.4 Blueprint mode). Represented as
## an interactable furniture-like node so it reuses the Furniture +
## InteractionComponent + GameAction machinery: the player aims at it and
## presses E to run the Build action.
##
## Incremental step toward blueprint-then-build (GDD §7.1/§7.4): completion is
## instant for now, but it funnels through one entry point (complete()) so a
## future colonist work-tick / JobBoard can drive the same path with no
## architecture change — see BlueprintLayer.complete_blueprint.

## The def this blueprint materializes into when built.
@export var target_def_id: String = ""

## Saved placement yaw (RotationState.step) of the target, so the materialized
## block/furniture keeps the player's intended rotation.
@export var target_rotation_step: int = 0

## The anchor cell this blueprint was placed at (set by BlueprintLayer at spawn;
## used by complete() to tell the layer where to materialize the target).
var anchor_cell: Vector3i = Vector3i.ZERO

# Back-ref to the owning layer (untyped to avoid a Blueprint <-> BlueprintLayer
# class_name cycle). Set at spawn; complete() forwards through it.
var layer = null

## Materials contributed toward the target's material_cost so far:
## { ItemDef.id (String): count (int) }. Empty until something is deposited, so
## has_complete_materials() is vacuously true for a costless blueprint.
var _given: Dictionary = {}

## The Build ActionOption to swap in once materials are complete. Assigned by
## BlueprintLayer at spawn ONLY when the target has a material_cost; a costless
## blueprint starts on Build and never swaps.
var _build_option: ActionOption = null


func _ready() -> void:
	# Seed the initial "0/N" status line so the first targeting shows progress
	# before any deposit. Costless blueprints leave info_text blank.
	_refresh_info_text()


## Build the target into the world and remove this blueprint. `builder` is the
## player now; it is passed through so the colonist labor loop can attribute
## skill/stamina later. Returns true on success.
func complete(builder: Node = null) -> bool:
	if layer == null:
		return false
	return layer.complete_blueprint(self, builder)


## True when every entry of the target's material_cost has been fully
## contributed. Vacuously true when material_cost is empty (free builds).
func has_complete_materials() -> bool:
	var def := _target_def()
	if def == null:
		return true
	for entry in def.material_cost:
		if _given.get(entry.item_def.id, 0) < entry.count:
			return false
	return true


func given_count(item_id: String) -> int:
	return _given.get(item_id, 0)


## Move as much as `actor` carries toward the still-unsatisfied entries of the
## target's material_cost. Partial fulfillment is allowed. Returns the total
## count deposited. When this call crosses the completion threshold, the
## blueprint's interaction swaps from "Add materials" to "Build".
func deposit_from(actor: Node) -> int:
	var def := _target_def()
	if def == null:
		return 0
	var total := 0
	for entry in def.material_cost:
		var id := entry.item_def.id
		var need: int = entry.count - int(_given.get(id, 0))
		if need <= 0:
			continue
		# remove_item returns the shortfall and clamps to what's held, so this
		# takes "everything available" when the actor can't cover `need`.
		var shortfall: int = actor.remove_item(id, need)
		var deposited: int = need - shortfall
		if deposited > 0:
			_given[id] = _given.get(id, 0) + deposited
			total += deposited
			GameLog.log("Deposited %d %s (%d/%d)" % [deposited, id, _given[id], entry.count])
	if total > 0:
		_refresh_info_text()
		if has_complete_materials():
			_swap_to_build_option()
	return total


func _swap_to_build_option() -> void:
	if _build_option == null:
		return
	var ic := get_node_or_null("InteractionComponent") as InteractionComponent
	if ic != null:
		var opts: Array[ActionOption] = [_build_option]
		ic.action_options = opts


## Rebuild the InteractionComponent's info_text from current contributions, e.g.
## "Plank 3/15". InteractLabel re-reads it on the next interactable_changed
## re-emit (Player.execute_default_action emits one after every E-tap).
func _refresh_info_text() -> void:
	var ic := get_node_or_null("InteractionComponent") as InteractionComponent
	if ic == null:
		return
	var def := _target_def()
	if def == null or def.material_cost.is_empty():
		ic.info_text = ""
		return
	var parts := PackedStringArray()
	for entry in def.material_cost:
		var id := entry.item_def.id
		var item_name := entry.item_def.resource_name
		if item_name == "":
			item_name = id
		parts.append("%s %d/%d" % [item_name, int(_given.get(id, 0)), entry.count])
	ic.info_text = "  ".join(parts)


## Resolve the target BuildableDef via the canonical materialization key, rather
## than the inherited `def`, to avoid the def/target_def_id duplication and any
## FurnitureDef-typing ambiguity on the inherited field.
func _target_def() -> BuildableDef:
	return BuildLibrary.get_def(target_def_id)


# --- SaveSystem contract -----------------------------------------------------
# BlueprintLayer aggregates one record per blueprint (see BlueprintLayer.serialize).
# `given` is the material-progress state (phase-2 runtime state, included so a
# restored in-progress blueprint keeps its deposited materials).

## Snapshot placement + material progress: target_def_id, anchor cell, yaw step,
## and the {item_id: count} contributed so far.
func serialize() -> Dictionary:
	return {
		"target_def_id": target_def_id,
		"anchor": [anchor_cell.x, anchor_cell.y, anchor_cell.z],
		"yaw": target_rotation_step,
		"given": _given.duplicate(true),
	}


## Restore placement + material progress from a serialize() dict, then refresh
## the interaction UI (info text + swap to Build if materials are now complete).
## Idempotent on the spawn-set fields, so it is safe to call right after
## BlueprintLayer.spawn_blueprint as well as standalone.
func deserialize(data: Dictionary) -> void:
	target_def_id = data.get("target_def_id", target_def_id)
	target_rotation_step = int(data.get("yaw", target_rotation_step))
	var a: Array = data.get("anchor", [anchor_cell.x, anchor_cell.y, anchor_cell.z])
	anchor_cell = Vector3i(int(a[0]), int(a[1]), int(a[2]))
	_given.clear()
	var saved_given: Dictionary = data.get("given", {})
	for item_id in saved_given:
		_given[item_id] = int(saved_given[item_id])
	_refresh_info_text()
	if not _given.is_empty() and has_complete_materials():
		_swap_to_build_option()
