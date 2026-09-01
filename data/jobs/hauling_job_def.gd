extends JobDef
class_name HaulingJobDef
## Hauling labor (GDD §6.10, ARCH "Subsystem: Colonists"): carry materials from
## storage crates to a MaterialSink (material_sink.gd — blueprints and crafting
## stations) OR carry WorldItems on the ground into colony storage crates.
##
## Multi-colonist (max_assignees=3 for sinks): haulers share the sink's deposit
## counter, and live crate stock serializes concurrent runs so two can't double-spend.
## For WorldItems, hauler gathers ground items (including nearby reachable items
## of the same type up to carry capacity) and deposits them into storage crates.
##
## Expressed as repeated cycles through the universal work tree — no dedicated
## leg tree. Each cycle: ClaimJob re-claims, work_site() picks the walk target
## from carry state, NavigateTo walks it, then PerformWork fires complete()
## which does the transfer (FETCH or DELIVER).

const TOOL_TAG := "tool"
const GATHER_SEARCH_RADIUS := 12.0


func work_site(actor: Node, job: Variant) -> Variant:
	var actor_3d := actor as Node3D
	var actor_pos := actor_3d.global_position if actor_3d != null else Vector3.ZERO

	var direct_crate := _storage_crate_of(job)
	if direct_crate != null:
		# Re-query a crate with capacity at walk time so newly-placed shelves
		# are picked up naturally and full crates don't stay baked-in as targets.
		var pocket: Inventory = actor.inventory if "inventory" in actor and actor.inventory != null else null
		if pocket != null:
			for item_id in pocket.items.keys():
				if _is_tool(str(item_id)):
					continue
				var count: int = pocket.get_item_count(str(item_id))
				if count <= 0:
					continue
				var capable_crate := Colony.storage_registry.find_storage_for(str(item_id), actor_pos, count)
				if capable_crate != null:
					return capable_crate.global_position
		var best_crate := Colony.storage_registry.nearest_crate(actor_pos)
		if best_crate != null:
			return best_crate.global_position
		return direct_crate.global_position

	var sink := _sink_of(job)
	if sink != null:
		if _carries_needed_material(actor, sink):
			if "target_position" in job and job.target_position != Vector3.ZERO:
				return job.target_position
			if "world_position" in job and job.world_position != Vector3.ZERO:
				return job.world_position
			if "location" in job and job.location != Vector3.ZERO:
				return job.location
			if sink is Node3D:
				return (sink as Node3D).global_position
			return Vector3.ZERO

		# If we're carrying surplus material and sink is already full, route to crate
		if sink.has_complete_materials() or not Colony.storage_registry.has_source_for(sink.needed_item_ids()):
			var pocket: Inventory = actor.inventory if "inventory" in actor and actor.inventory != null else null
			if pocket != null and not pocket.items.is_empty():
				var crate := Colony.storage_registry.nearest_crate(actor_pos)
				if crate != null:
					return crate.global_position

		var crate := Colony.storage_registry.find_source(
				sink.needed_item_ids(), actor_pos)
		if crate == null:
			return null
		return crate.global_position

	var world_item := _world_item_of(job)
	if world_item != null:
		if _carries_item(actor, world_item.item_id):
			# If capacity remains, check for next nearby reachable matching item
			var next_item := _find_next_reachable_ground_item(actor, world_item.item_id, GATHER_SEARCH_RADIUS)
			if next_item != null:
				return next_item.global_position

			var crate := Colony.storage_registry.find_storage_for(world_item.item_id, actor_pos)
			if crate == null:
				crate = Colony.storage_registry.nearest_crate(actor_pos)
			if crate == null:
				return null
			return crate.global_position
		else:
			return world_item.global_position

	return null


func complete(actor: Node, job: Variant) -> void:
	var direct_crate := _storage_crate_of(job)
	if direct_crate != null:
		_return_surplus_to_crate(actor)
		_finish(actor, job)
		return

	var sink := _sink_of(job)
	if sink != null and is_instance_valid(actor):
		if _carries_needed_material(actor, sink):
			sink.deposit_from(actor)
			if sink.has_complete_materials():
				_return_surplus_to_crate(actor)
			return
		if sink.has_complete_materials():
			_return_surplus_to_crate(actor)
			return
		var crate := Colony.storage_registry.find_source(
				sink.needed_item_ids(), (actor as Node3D).global_position if actor is Node3D else Vector3.ZERO)
		var crate_inv := Colony.storage_registry.inventory_of(crate) if crate != null else null
		if crate_inv == null:
			return
		var pocket: Inventory = actor.inventory if "inventory" in actor and actor.inventory != null else null
		if pocket == null:
			return
		for id in sink.needed_item_ids():
			var remaining: int = sink.remaining_need(id)
			if remaining <= 0:
				continue
			crate_inv.transfer_to(pocket, id, remaining)
		return

	var world_item := _world_item_of(job)
	if world_item != null and is_instance_valid(actor):
		var actor_3d := actor as Node3D
		var actor_pos := actor_3d.global_position if actor_3d != null else Vector3.ZERO

		# 1. If at/near a ground item (primary or gathered candidate), pick it up
		var target_item: WorldItem = null
		if is_instance_valid(world_item) and world_item.is_inside_tree() and actor_pos.distance_to(world_item.global_position) <= 2.2 and world_item.count > 0:
			target_item = world_item
		else:
			target_item = _find_ground_item_at(actor, world_item.item_id, actor_pos, 2.2)

		if target_item != null:
			target_item.reserve(actor)
			var pickup := PickupAction.new()
			pickup.execute(actor, target_item)
			if is_instance_valid(target_item):
				if target_item.count <= 0:
					target_item.hide_item()
					_unregister_item_from_colony(target_item)
			return

		# 2. If delivering to crate
		if _carries_item(actor, world_item.item_id):
			var crate := Colony.storage_registry.find_storage_for(world_item.item_id, actor_pos)
			if crate == null:
				crate = Colony.storage_registry.nearest_crate(actor_pos)
			var crate_inv := Colony.storage_registry.inventory_of(crate) if crate != null else null
			var pocket: Inventory = actor.inventory if "inventory" in actor and actor.inventory != null else null
			if pocket != null:
				var count := pocket.get_item_count(world_item.item_id)
				if count > 0:
					if crate_inv != null and crate_inv.can_add(world_item.item_id, 1):
						pocket.transfer_to(crate_inv, world_item.item_id, count)
					elif actor.is_inside_tree():
						pocket.remove(world_item.item_id, count)
						WorldItem.spawn_at(actor, world_item.item_id, count, actor_pos + Vector3(0, 0.5, 0))
			_return_surplus_to_crate(actor)
			_free_collected_hidden_items(actor, world_item.item_id)
			if is_instance_valid(world_item):
				if world_item.count <= 0:
					world_item.queue_free()
				else:
					world_item.unreserve(actor)
			return
		else:
			_free_collected_hidden_items(actor, world_item.item_id)
			if is_instance_valid(world_item):
				world_item.unreserve(actor)
				if world_item.count <= 0 and not world_item.visible:
					world_item.queue_free()
			return


func meets_requirements_any(actor: Node, job: Variant) -> bool:
	var world_item := _world_item_of(job)
	if world_item != null:
		if world_item.is_forbidden():
			return false
		if world_item.is_reserved() and not world_item.is_reserved_by(actor):
			return false
		if world_item.count <= 0 and not _carries_item(actor, world_item.item_id):
			return false
		if not _actor_has_remaining_capacity(actor) and not _carries_item(actor, world_item.item_id):
			return false
	return super.meets_requirements_any(actor, job)


func is_available(job: Variant) -> bool:
	if _storage_crate_of(job) != null:
		# Only available when there's at least one crate that can accept something.
		return Colony.storage_registry.nearest_crate(Vector3.ZERO) != null

	var sink := _sink_of(job)
	if sink != null:
		if sink.has_complete_materials():
			return false
		return Colony.storage_registry.has_source_for(sink.needed_item_ids())

	var world_item := _world_item_of(job)
	if world_item != null:
		if world_item.is_forbidden():
			return false
		if not is_instance_valid(world_item) or world_item.is_queued_for_deletion():
			return false
		if world_item.is_reserved():
			if job is Job:
				var assigned: Array = job._assigned_colonists if "_assigned_colonists" in job else []
				var claimer = world_item.get_claimer()
				var claimer_str := str(claimer) if claimer != null else ""
				if not assigned.has(claimer_str):
					return false
		return Colony.storage_registry.get_all_crates().size() > 0

	return false


func should_close(job: Variant) -> bool:
	if _storage_crate_of(job) != null:
		# Close once the target_node crate is freed/invalid (job was used as
		# a one-shot deposit and the def.complete() already called _finish).
		var crate := _storage_crate_of(job)
		return not is_instance_valid(crate) or crate.is_queued_for_deletion()

	var sink := _sink_of(job)
	if sink != null:
		return sink.has_complete_materials()

	var world_item := _world_item_of(job)
	if world_item != null:
		if world_item.is_forbidden():
			return true
		if not is_instance_valid(world_item) or world_item.is_queued_for_deletion():
			return true
		return false

	return true


func job_complete(job: Variant) -> bool:
	var sink := _sink_of(job)
	if sink != null:
		return sink.has_complete_materials()

	var world_item := _world_item_of(job)
	if world_item != null:
		return world_item.count <= 0 and not world_item.visible and not world_item.is_reserved()

	return false


func on_abort(actor: Node, job: Variant, _elapsed: float = 0.0) -> void:
	var world_item := _world_item_of(job)
	if world_item != null and is_instance_valid(world_item):
		world_item.unreserve(actor)
		if world_item.count <= 0 and not world_item.visible:
			world_item.show_item()
	var tree := (actor as Node).get_tree() if actor != null else null
	if tree != null and tree.root != null:
		_unreserve_actor_items_recursive(tree.root, actor)


func _unreserve_actor_items_recursive(node: Node, actor: Node) -> void:
	if node == null:
		return
	if node is WorldItem:
		var item := node as WorldItem
		if item.is_reserved_by(actor):
			item.unreserve(actor)
			if item.count <= 0 and not item.visible:
				item.show_item()
	for child in node.get_children():
		_unreserve_actor_items_recursive(child, actor)


func _find_next_reachable_ground_item(actor: Node, item_id: String, max_radius: float = GATHER_SEARCH_RADIUS) -> WorldItem:
	if actor == null or not is_instance_valid(actor) or not (actor is Node3D):
		return null
	if not _actor_has_remaining_capacity(actor):
		return null

	var tree := (actor as Node).get_tree()
	if tree == null:
		return null

	var actor_pos: Vector3 = (actor as Node3D).global_position
	var candidates: Array[WorldItem] = WorldItem.get_nearby_unreserved(tree, actor_pos, item_id, max_radius)
	if candidates.is_empty():
		return null

	candidates.sort_custom(func(a: WorldItem, b: WorldItem) -> bool:
		return actor_pos.distance_squared_to(a.global_position) < actor_pos.distance_squared_to(b.global_position)
	)

	var pathfinder = actor.get("pathfinder") if "pathfinder" in actor else null
	for cand in candidates:
		if pathfinder != null and pathfinder.has_method("find_path_world"):
			var can_check := true
			if "_is_walkable" in pathfinder:
				can_check = pathfinder._is_walkable.is_valid()
			if can_check:
				var path: Array[Vector3] = pathfinder.find_path_world(actor_pos, cand.global_position)
				if path.is_empty() and actor_pos.distance_to(cand.global_position) > 1.5:
					continue
		return cand

	return null


func _find_ground_item_at(actor: Node, item_id: String, pos: Vector3, radius: float = 2.2) -> WorldItem:
	var tree := (actor as Node).get_tree() if actor != null else null
	if tree == null:
		return null
	var radius_sq := radius * radius
	for node in tree.get_nodes_in_group("world_items"):
		var item := node as WorldItem
		if item != null and is_instance_valid(item) and item.is_inside_tree() and not item.is_queued_for_deletion():
			if not item.is_forbidden() and item.count > 0 and item.visible:
				if item.item_id == item_id and item.global_position.distance_squared_to(pos) <= radius_sq:
					if not item.is_reserved() or item.is_reserved_by(actor):
						return item
	return null


func _actor_has_remaining_capacity(actor: Node) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	if actor.has_method("remaining_capacity"):
		return float(actor.remaining_capacity()) > 0.0
	if "inventory" in actor and actor.inventory != null:
		var inv: Inventory = actor.inventory
		if inv.has_method("remaining_capacity"):
			return float(inv.remaining_capacity()) > 0.0
		if "capacity" in inv:
			return inv.current_weight() < inv.capacity
	return false


func _unregister_item_from_colony(item: WorldItem) -> void:
	var colony: Node = item.get_node_or_null("/root/Colony") if item.is_inside_tree() else null
	if colony != null and colony.has_method("unregister_world_item"):
		colony.call("unregister_world_item", item)


func _free_collected_hidden_items(actor: Node, item_id: String) -> void:
	var tree := (actor as Node).get_tree() if actor != null else null
	if tree == null or tree.root == null:
		return
	_free_hidden_recursive(tree.root, actor, item_id)


func _free_hidden_recursive(node: Node, actor: Node, item_id: String) -> void:
	if node == null:
		return
	if node is WorldItem:
		var item := node as WorldItem
		if not item.visible and item.count <= 0 and item.item_id == item_id and item.is_reserved_by(actor):
			item.queue_free()
	for child in node.get_children():
		_free_hidden_recursive(child, actor, item_id)


func _return_surplus_to_crate(actor: Node) -> void:
	var pocket: Inventory = actor.inventory if "inventory" in actor and actor.inventory != null else null
	if pocket == null or not actor is Node3D:
		return
	var actor_pos: Vector3 = (actor as Node3D).global_position
	## Use find_storage_for per item so full crates are skipped and newly-placed
	## shelves are picked up; fall back to spawning a WorldItem on the floor.
	for item_id in pocket.items.keys().duplicate():
		if _is_tool(str(item_id)):
			continue
		var count: int = pocket.get_item_count(str(item_id))
		if count <= 0:
			continue
		var crate := Colony.storage_registry.find_storage_for(str(item_id), actor_pos, count)
		if crate == null:
			crate = Colony.storage_registry.nearest_crate(actor_pos)
		var crate_inv := Colony.storage_registry.inventory_of(crate)
		if crate_inv != null and crate_inv.can_add(str(item_id), 1):
			pocket.transfer_to(crate_inv, str(item_id), count)
		elif actor.is_inside_tree():
			pocket.remove(str(item_id), count)
			WorldItem.spawn_at(actor, str(item_id), count, actor_pos + Vector3(0, 0.5, 0))


func _is_tool(item_id: String) -> bool:
	var def := ItemDB.get_def(item_id)
	return def != null and def.tags.has(TOOL_TAG)


func _storage_crate_of(job: Variant) -> Furniture:
	if job == null or not "target_node" in job:
		return null
	var t: Variant = job.target_node
	if t == null or not is_instance_valid(t) or (t as Node).is_queued_for_deletion():
		return null
	if t is Furniture and (t as Furniture).has_node("StorageInventory"):
		return t as Furniture
	return null


func _sink_of(job: Variant) -> Node:
	if job == null or not "target_node" in job:
		return null
	var t: Variant = job.target_node
	if t == null or not is_instance_valid(t) or (t as Node).is_queued_for_deletion():
		return null
	var n := t as Node
	if n == null or not MaterialSink.is_material_sink(n):
		return null
	return n


func _world_item_of(job: Variant) -> WorldItem:
	if job == null or not "target_node" in job:
		return null
	var t: Variant = job.target_node
	if t == null or not is_instance_valid(t) or (t as Node).is_queued_for_deletion():
		return null
	return t as WorldItem


func _carries_item(actor: Node, item_id: String) -> bool:
	if actor == null or not "inventory" in actor or actor.inventory == null:
		return false
	return actor.inventory.get_item_count(item_id) > 0


func _carries_needed_material(actor: Node, sink: Node) -> bool:
	if actor == null or not "inventory" in actor or actor.inventory == null:
		return false
	for id in sink.needed_item_ids():
		if actor.inventory.get_item_count(id) > 0:
			return true
	return false
