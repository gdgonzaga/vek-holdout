extends JobDef
class_name HaulingJobDef
## Hauling labor (GDD §6.10, ARCH "Subsystem: Colonists"): carry materials from
## storage crates to a MaterialSink (material_sink.gd — blueprints and crafting
## stations) OR carry WorldItems on the ground into colony storage crates.
##
## Multi-colonist (max_assignees=3 for sinks): haulers share the sink's deposit
## counter, and live crate stock serializes concurrent runs so two can't double-spend.
## For WorldItems, hauler picks up ground items and deposits them into the nearest
## storage crate with available capacity.
##
## Expressed as repeated cycles through the universal work tree — no dedicated
## leg tree. Each cycle: ClaimJob re-claims, work_site() picks the walk target
## from carry state, NavigateTo walks it, then PerformWork fires complete()
## which does the transfer (FETCH or DELIVER).

const TOOL_TAG := "tool"


func work_site(actor: Node, job: Variant) -> Variant:
	var sink := _sink_of(job)
	if sink != null:
		if _carries_needed_material(actor, sink):
			var loc: Vector3 = job.location if "location" in job else Vector3.ZERO
			return loc
		var crate := Colony.storage_registry.find_source(
				sink.needed_item_ids(), (actor as Node3D).global_position if actor is Node3D else Vector3.ZERO)
		if crate == null:
			return null
		return crate.global_position

	var world_item := _world_item_of(job)
	if world_item != null:
		var actor_3d := actor as Node3D
		var actor_pos := actor_3d.global_position if actor_3d != null else Vector3.ZERO
		if _carries_item(actor, world_item.item_id):
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
	var sink := _sink_of(job)
	if sink != null and is_instance_valid(actor):
		if _carries_needed_material(actor, sink):
			sink.deposit_from(actor)
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
		if _carries_item(actor, world_item.item_id):
			var crate := Colony.storage_registry.find_storage_for(world_item.item_id, actor_pos)
			if crate == null:
				crate = Colony.storage_registry.nearest_crate(actor_pos)
			var crate_inv := Colony.storage_registry.inventory_of(crate) if crate != null else null
			var pocket: Inventory = actor.inventory if "inventory" in actor and actor.inventory != null else null
			if crate_inv != null and pocket != null:
				var count := pocket.get_item_count(world_item.item_id)
				if count > 0:
					pocket.transfer_to(crate_inv, world_item.item_id, count)
			if world_item.count <= 0:
				world_item.queue_free()
			else:
				world_item.unreserve(actor)
			return
		else:
			world_item.reserve(actor)
			var pickup := PickupAction.new()
			pickup.execute(actor, world_item)
			if is_instance_valid(world_item):
				if world_item.count <= 0:
					world_item.hide_item()
			return


func is_available(job: Variant) -> bool:
	var sink := _sink_of(job)
	if sink != null:
		if sink.has_complete_materials():
			return false
		return Colony.storage_registry.has_source_for(sink.needed_item_ids())

	var world_item := _world_item_of(job)
	if world_item != null:
		if world_item.is_forbidden():
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
	var sink := _sink_of(job)
	if sink != null:
		return sink.has_complete_materials()

	var world_item := _world_item_of(job)
	if world_item != null:
		if world_item.is_forbidden():
			return true
		if world_item.count <= 0 and not world_item.visible:
			return true
		return false

	return true


func job_complete(job: Variant) -> bool:
	var sink := _sink_of(job)
	if sink != null:
		return sink.has_complete_materials()

	var world_item := _world_item_of(job)
	if world_item != null:
		return world_item.count <= 0 and not world_item.visible

	return false


func on_abort(actor: Node, job: Variant, _elapsed: float = 0.0) -> void:
	var world_item := _world_item_of(job)
	if world_item != null and is_instance_valid(world_item):
		world_item.unreserve(actor)
		if world_item.count <= 0 and not world_item.visible:
			world_item.show_item()


func _return_surplus_to_crate(actor: Node) -> void:
	var pocket: Inventory = actor.inventory if "inventory" in actor and actor.inventory != null else null
	if pocket == null or not actor is Node3D:
		return
	var crate_inv := Colony.storage_registry.inventory_of(
			Colony.storage_registry.nearest_crate((actor as Node3D).global_position))
	if crate_inv == null:
		return
	for item_id in pocket.items.keys():
		if _is_tool(str(item_id)):
			continue
		var count: int = pocket.get_item_count(str(item_id))
		if count > 0:
			pocket.transfer_to(crate_inv, str(item_id), count)


func _is_tool(item_id: String) -> bool:
	var def := ItemDB.get_def(item_id)
	return def != null and def.tags.has(TOOL_TAG)


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
