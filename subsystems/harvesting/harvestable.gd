class_name Harvestable
extends Node
## Capability component for harvestable furniture (GDD §6.10, ARCH "Harvesting", ARCH "Farming").
## Attached under a Furniture by FurnitureLayer when its def declares harvest_params
## or farm_plot_params — the CraftingStation/StorageInventory pattern.
##
## Tracks work_done toward completion and is_marked_for_harvest (for colonist job
## dispatch). When complete() is invoked, grants yields to the harvesting actor
## and either removes the furniture node (trees/rocks) or resets the farm plot (crops).

const STATE_KEY := "harvest"

var _furniture: Furniture:
	get: return get_parent() as Furniture


## Back-ref to the definition's HarvestParams.
func params() -> HarvestParams:
	return Furniture.get_capability(_furniture, HarvestParams) as HarvestParams


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


## Whether this Harvestable is currently claimable by HarvestJobDef: marked,
## and — for wild flora — still at a chop-eligible growth stage. A stage
## change after marking (can_chop flipping false) self-closes the job here
## instead of a claim silently no-oping at completion.
func is_claimable() -> bool:
	if not is_marked_for_harvest():
		return false
	var flora := _furniture as WildFlora
	return flora.can_be_felled() if flora != null else true


## Accumulated work on this node in seconds.
func work_done() -> float:
	return _harvest_state().get("work_done", 0.0)


## Update accumulated work.
func set_work_done(amount: float) -> void:
	var state := _harvest_state()
	state["work_done"] = amount
	if _furniture != null:
		_furniture.state[STATE_KEY] = state


## Seconds of WORK this node demands before the skill multiplier. A farm plot's
## Growable overrides the furniture's HarvestParams.work_time with its crop's
## base_harvest_time — the crop decides the effort, not the plot. Resolution
## lives here (Harvestable already cooperates with Growable on completion) so
## job defs and player actions need no crop knowledge.
func effective_work_time() -> float:
	var growable := _furniture.get_node_or_null("Growable") as Growable if _furniture != null else null
	if growable != null:
		var cdef := growable.get_crop_def()
		# 3.0 matches FarmManualAction's fallback for the same degenerate
		# marked-but-cropless-plot case.
		return cdef.base_harvest_time if cdef != null else 3.0
	var flora := _furniture as WildFlora
	if flora != null:
		var flora_def := flora.def as WildFloraDef
		return flora_def.chop_work_time if flora_def != null else 0.0
	var p := params()
	return p.work_time if p != null else 0.0


## Resolve the harvest: grant yields to actor's inventory and either reset the plot
## or remove the furniture node. Returns true if successfully harvested.
func complete(actor: Node) -> bool:
	var growable := _furniture.get_node_or_null("Growable") as Growable if _furniture != null else null

	if growable != null:
		var yields := growable.get_harvest_yields()
		# 1. Harvest Yield Spawning: Spawn crop yields directed towards actor or away from plot center.
		_spawn_harvest_entries(yields, actor)
		
		if _furniture != null:
			GameLog.info("Harvested %s" % _furniture.label)
		growable.on_harvested(actor)
		EventBus.harvest_mark_toggled.emit(_furniture, anchor_cell(), false)
		return true

	# 1b. Wild Flora Chop/Removal: job-driven felling deals a direct lethal
	# hit to the HealthComponent, bypassing take_damage's weapon-tag damage
	# scaling (a real-time combat concern) since the job's own work_time and
	# required_tool_tag already model effort and equipment. Reuses the
	# existing entity_died -> _on_felled yields+destroy pipeline unchanged.
	var flora := _furniture as WildFlora
	if flora != null:
		return _fell_wild_flora(flora, actor)

	var p := params()
	if p == null:
		return false
	
	# 2. Resource Harvest Spawning: Spawn felled furniture/resource yields.
	_spawn_harvest_entries(p.yields, actor)
	
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


## Implements the IStatProvider contract's stat methods
## (subsystems/core/i_stat_provider.gd) for &"work_progress" only. Composed
## into WildFlora.get_stat_ratio rather than queried directly — MoodletDef
## always evaluates the entity node, never a child capability component.
func get_stat_ratio(stat_name: StringName) -> float:
	if stat_name != &"work_progress":
		return -1.0
	var total := effective_work_time()
	if total <= 0.0:
		return 0.0
	return clampf(work_done() / total, 0.0, 1.0)


func get_stat_value(stat_name: StringName) -> float:
	return work_done() if stat_name == &"work_progress" else -1.0


func _spawn_harvest_entries(amounts: Array[ItemAmount], actor: Node) -> void:
	## Auxiliary: Spawns item amounts with positions and impulses calculated relative to harvester.
	var total_entries := amounts.size()
	for i in range(total_entries):
		var entry := amounts[i]
		if entry == null or entry.item_def == null or entry.count <= 0:
			continue
		
		# 1. Drop Transform Calculation: Compute clear spawn position and outward impulse.
		var drop_info: Dictionary = _calculate_harvest_drop_transform(actor, i, total_entries)
		
		# 2. World Item Spawn: Instantiate physical item drop.
		_spawn_drop(entry.item_def.id, entry.count, drop_info.get("pos", Vector3.ZERO), drop_info.get("impulse", Vector3.UP))


func _calculate_harvest_drop_transform(actor: Node, index: int, total: int) -> Dictionary:
	## Auxiliary: Computes drop spawn position and impulse vector clear of furniture footprint.
	var center := _furniture.global_position if _furniture != null and _furniture.is_inside_tree() else Vector3.ZERO
	if center == Vector3.ZERO and actor is Node3D and (actor as Node3D).is_inside_tree():
		center = (actor as Node3D).global_position
	
	var actor_3d := actor as Node3D
	var has_actor := actor_3d != null and actor_3d.is_inside_tree()
	var to_actor: Vector3 = (actor_3d.global_position - center) if has_actor else Vector3.ZERO
	to_actor.y = 0.0
	
	var base_dir: Vector3 = to_actor.normalized() if to_actor.length_squared() > 0.01 else Vector3.FORWARD
	var spread_angle := (float(index) - float(total - 1) * 0.5) * 0.3 if has_actor else (float(index) * TAU / float(maxi(1, total)))
	var dir := base_dir.rotated(Vector3.UP, spread_angle)
	
	return {
		"pos": center + dir * 0.75 + Vector3(0.0, 0.5, 0.0),
		"impulse": (dir + Vector3(0.0, 0.85, 0.0)).normalized()
	}


func _spawn_drop(item_id: String, count: int, pos: Vector3, impulse_dir: Vector3 = Vector3.UP) -> void:
	## Auxiliary: Spawns a WorldItem instance in the active scene tree.
	if count <= 0 or item_id == "":
		return
	var tree := get_tree()
	if tree != null:
		WorldItem.spawn_at(tree, item_id, count, pos, impulse_dir, 2.0)
	elif _furniture != null and _furniture.get_parent() != null:
		WorldItem.spawn_at(_furniture.get_parent(), item_id, count, pos, impulse_dir, 2.0)


func _fell_wild_flora(flora: WildFlora, actor: Node) -> bool:
	## Auxiliary: Kills the flora's HealthComponent directly so its existing
	## entity_died -> _on_felled pipeline handles yields and removal.
	if not flora.can_be_felled():
		return false
	var hc := flora.health_component
	if hc == null or hc.is_dead:
		return false
	hc.take_damage(hc.current_hp, actor)
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
