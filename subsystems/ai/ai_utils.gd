class_name AIUtils
extends RefCounted
## Shared scene-tree query helpers for behavior tree tasks and ColonistBrain.


# =================
# Primary Functions
# =================

## Returns the closest valid Node3D in group_name to origin, or null if none
## qualify. exclude skips a specific node (e.g. the searching agent itself);
## max_dist_sq bounds the search (INF for unbounded); skip_dead filters out
## nodes exposing a truthy is_dead/_is_dead property.
static func find_nearest_in_group(
		tree: SceneTree,
		group_name: StringName,
		origin: Vector3,
		exclude: Node = null,
		max_dist_sq: float = INF,
		skip_dead: bool = false
) -> Node3D:
	# 1. Unfiltered Delegation: An always-true predicate keeps this the plain
	# nearest-node search every existing caller expects.
	return find_nearest_in_group_where(
		tree,
		group_name,
		origin,
		func(_node: Node3D) -> bool: return true,
		exclude,
		max_dist_sq,
		skip_dead
	)


## Same search as find_nearest_in_group, but only considers nodes for which
## predicate.call(node) returns true. Used by ColonistBrain to skip smart objects
## that are already fully claimed, so colonists stop converging on one bed or one
## single-user recreation object.
static func find_nearest_in_group_where(
		tree: SceneTree,
		group_name: StringName,
		origin: Vector3,
		predicate: Callable,
		exclude: Node = null,
		max_dist_sq: float = INF,
		skip_dead: bool = false
) -> Node3D:
	if tree == null:
		return null

	var nearest: Node3D = null
	var nearest_dist_sq: float = max_dist_sq
	for node in tree.get_nodes_in_group(group_name):
		# 1. Candidate Validation: Filters freed/queued/excluded/dead nodes before distance checks.
		if not _is_valid_candidate(node, exclude, skip_dead):
			continue
		# 2. Caller Filter: Applies the availability rule before the distance
		# comparison so an unusable near node never shadows a usable far one.
		if predicate.is_valid() and not bool(predicate.call(node as Node3D)):
			continue
		var dist_sq: float = origin.distance_squared_to((node as Node3D).global_position)
		if dist_sq <= nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = node as Node3D

	return nearest


## Unwraps a WorkerClaim to its JobInstance, then returns whichever def field
## the job-like object exposes: legacy Job uses `def`, fractional JobInstance
## uses `job_def`. Returns null if job_candidate is null/freed or has neither.
static func resolve_job_def(job_candidate: Variant) -> Resource:
	if job_candidate == null or not is_instance_valid(job_candidate):
		return null
	var job: Variant = job_candidate.job if job_candidate is WorkerClaim else job_candidate
	if job == null or not is_instance_valid(job):
		return null
	if "def" in job and job.def != null:
		return job.def
	if "job_def" in job and job.job_def != null:
		return job.job_def
	return null


## Drops every non-tool item in colonist's carry inventory to the floor as a
## WorldItem, skipping any item_id present in keep_ids (items still needed by
## whatever job the colonist is about to keep working).
static func drop_unneeded_items(colonist: Colonist, keep_ids: Array[String] = []) -> void:
	if colonist == null or colonist.inventory == null:
		return
	for item_id in colonist.inventory.items.keys().duplicate():
		var id_str := str(item_id)
		var item_def := ItemDB.get_def(id_str) if ItemDB != null else null
		if item_def != null and item_def.tags.has("tool"):
			continue
		if keep_ids.has(id_str):
			continue
		var count: int = colonist.inventory.get_item_count(id_str)
		if count > 0:
			colonist.inventory.remove(id_str, count)
			if colonist.is_inside_tree():
				WorldItem.spawn_at(colonist, id_str, count, colonist.global_position + Vector3(0, 0.5, 0))


## True when item_id's ItemDef marks it as food (FoodParams or the "food" tag).
static func is_edible_item(item_id: String) -> bool:
	if ItemDB == null:
		return false
	var def: ItemDef = ItemDB.get_def(item_id)
	return def != null and (def.is_food() or def.has_tag("food"))


## Returns actor's CharacterInventory via its duck-typed `.inventory` property
## first; when allow_node_fallback is true (the default), falls back to a
## direct "Inventory" child node lookup if the property is absent/wrong type.
static func resolve_character_inventory(actor: Node, allow_node_fallback: bool = true) -> CharacterInventory:
	if actor == null:
		return null
	if "inventory" in actor and actor.inventory is CharacterInventory:
		return actor.inventory
	if allow_node_fallback:
		return actor.get_node_or_null("Inventory") as CharacterInventory
	return null


## Returns current_controller if still valid, otherwise looks up agent's
## ColonistAnimationController child (direct name lookup, then a deep find_child
## fallback for controllers nested under a model/rig subtree).
static func resolve_anim_controller(current_controller: Node, agent: Node) -> Node:
	if current_controller != null and is_instance_valid(current_controller):
		return current_controller
	if agent == null:
		return null
	var found: Node = agent.get_node_or_null("ColonistAnimationController")
	if found == null:
		found = agent.find_child("ColonistAnimationController", true, false)
	return found


## Reads a required tool item id and tag list off a job def Resource (or any
## duck-typed object exposing the same fields), in the same {item_id, tags}
## shape every BT tool task uses to sync/check equipment requirements.
static func extract_tool_requirements(def_obj: Variant) -> Dictionary:
	var req_id: String = ""
	var req_tags: Array[StringName] = []
	if def_obj == null:
		return {"item_id": req_id, "tags": req_tags}

	if "required_equipped" in def_obj and str(def_obj.required_equipped) != "":
		req_id = str(def_obj.required_equipped)
	if def_obj.has_method("get_effective_required_tags"):
		req_tags = def_obj.get_effective_required_tags()
	elif "required_equipped_tags" in def_obj and def_obj.required_equipped_tags is Array:
		for t: Variant in def_obj.required_equipped_tags:
			if t is StringName or t is String:
				req_tags.append(StringName(str(t)))

	return {"item_id": req_id, "tags": req_tags}


# ===================
# Auxiliary Functions
# ===================

static func _is_valid_candidate(node: Node, exclude: Node, skip_dead: bool) -> bool:
	## Auxiliary: True when node is a live, non-excluded Node3D eligible for a distance check.
	if node == exclude or not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	if not (node is Node3D):
		return false
	if skip_dead:
		if "is_dead" in node and bool(node.is_dead):
			return false
		if "_is_dead" in node and bool(node._is_dead):
			return false
	return true
