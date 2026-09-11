extends Node
class_name StorageRegistry
## Live index of the colony's storage containers (crates, shelves), so haul jobs
## can find "nearest crate that has the materials this blueprint still needs"
## without each call site re-scanning. Owned by the Colony autoload as a child
## Node; given the current map's FurnitureContainer by MapWiring (mirroring how
## colonists are wired on each map load).
##
## No registration: find_source / has_source_for / nearest_crate scan the
## container's live children each call. Crates are few and these queries run at
## most once per haul FETCH leg, so the live scan is cheap and always correct —
## freed crates simply leave the container's child list, with no stale refs to
## clean up and no unregister hook on FurnitureLayer.

## The current map's furniture container (where crate Furniture nodes live), set
## by MapWiring on each map load. null until the first map wires.
var _container: Node3D = null


## Called by MapWiring (same site as Colony.on_map_wired) on every map load, so
## base<->POI swaps rebind the registry to the new map's crates.
func on_map_wired(container: Node3D) -> void:
	_container = container


## Nearest crate to `near` whose StorageInventory holds at least one of
## `item_ids` (the materials a blueprint still needs). Returns null if none.
## Straight-line distance; reachability is verified later by the pathfinder when
## the FETCH leg is pathed (an unreachable crate yields an empty path → abort).
func find_source(item_ids: Array[String], near: Vector3) -> Furniture:
	var best: Furniture = null
	var best_dist_sq: float = 0.0
	for crate in _crates():
		var inv := inventory_of(crate)
		if inv == null or not _has_any(inv, item_ids):
			continue
		var d: float = crate.global_position.distance_squared_to(near)
		if best == null or d < best_dist_sq:
			best = crate
			best_dist_sq = d
	return best


## Best crate to `near` that can accept `count` of `item_id` (has space under its weight capacity).
## Evaluates crate StorageInventory priority (1 to 5, highest first), breaking ties with shortest distance.
## Returns null if no storage crate has capacity for the item.
func find_storage_for(item_id: String, near: Vector3, count: int = 1) -> Furniture:
	var best: Furniture = null
	var best_priority: int = -1
	var best_dist_sq: float = INF
	for crate in _crates():
		var inv := inventory_of(crate)
		if inv == null:
			continue
		if not inv.can_add(item_id, count):
			continue
		var p: int = inv.priority
		var d: float = crate.global_position.distance_squared_to(near)
		if p > best_priority or (p == best_priority and d < best_dist_sq):
			best = crate
			best_priority = p
			best_dist_sq = d
	return best


## Finds the closest item ID in storage matching item_id or any tag in tags.
## Returns "" if no matching item is available in storage.
func find_closest_item_matching(item_id: String, tags: Array[StringName], near: Vector3) -> String:
	# 1. Candidate Evaluation: Search all crates for items matching item_id or tags.
	return _find_matching_item_in_crates(item_id, tags, near)


## True if any crate holds at least one of `item_ids`. Used by the producer
## (Colony._on_blueprint_placed) to decide haul-vs-construct, and by hauling's
## is_available gate so a no-source haul job is never claimable (and thus pruned).
func has_source_for(item_ids: Array[String]) -> bool:
	for crate in _crates():
		var inv := inventory_of(crate)
		if inv != null and _has_any(inv, item_ids):
			return true
	return false


## Nearest crate to `near` regardless of contents — for returning surplus
## carried items to storage on haul abort/finish. Returns null if no crate exists.
func nearest_crate(near: Vector3) -> Furniture:
	var best: Furniture = null
	var best_dist_sq: float = 0.0
	for crate in _crates():
		var d: float = crate.global_position.distance_squared_to(near)
		if best == null or d < best_dist_sq:
			best = crate
			best_dist_sq = d
	return best


const DEFAULT_STOCK_RADIUS := 50.0

## Colony-wide stock of `item_id`:
## 1. All storage crates in the colony.
## 2. Unforbidden WorldItems (filtered within `radius` of `near_pos` when `near_pos` is a Vector3).
## 3. Items carried by colonists and the player.
func colony_stock(item_id: String, near_pos: Variant = null, radius: float = DEFAULT_STOCK_RADIUS, include_reserved: bool = false) -> int:
	var total := 0
	# 1. Storage crates
	for crate in _crates():
		var inv := inventory_of(crate)
		if inv != null:
			total += inv.get_item_count(item_id)

	var tree := _get_tree_context()
	if tree == null:
		return total

	# 2. WorldItems (unforbidden, distance-filtered when near_pos is Vector3)
	var radius_sq := radius * radius if radius > 0.0 else INF
	var check_dist := (near_pos is Vector3) and radius > 0.0
	for node in tree.get_nodes_in_group("world_items"):
		var item := node as WorldItem
		if item == null or not is_instance_valid(item) or not item.is_inside_tree():
			continue
		if item.is_forbidden() or item.item_id != item_id:
			continue
		if not include_reserved and item.is_reserved():
			continue
		if check_dist and item.global_position.distance_squared_to(near_pos as Vector3) > radius_sq:
			continue
		total += item.count

	# 3. Carried items on Colonists
	for node in tree.get_nodes_in_group("colonists"):
		var colonist := node as Colonist
		if colonist != null and is_instance_valid(colonist) and colonist.inventory != null:
			total += colonist.inventory.get_item_count(item_id)

	# 4. Carried items on Player
	for node in tree.get_nodes_in_group("player"):
		var player := node as Player
		if player != null and is_instance_valid(player) and player.inventory != null:
			total += player.inventory.get_item_count(item_id)

	return total


func _get_tree_context() -> SceneTree:
	if is_inside_tree():
		return get_tree()
	if is_instance_valid(_container) and _container.is_inside_tree():
		return _container.get_tree()
	return Engine.get_main_loop() as SceneTree


## All live crate Furniture in the current map (Furniture nodes with a
## "StorageInventory" child). Computed each call so it never holds stale refs.
func get_all_crates() -> Array[Furniture]:
	return _crates()


func _crates() -> Array[Furniture]:
	var out: Array[Furniture] = []
	if not is_instance_valid(_container):
		return out
	for c in _container.get_children():
		if is_instance_valid(c) and c is Furniture and c.has_node("StorageInventory"):
			out.append(c)
	return out


## The crate's StorageInventory, or null if `crate` is null/freed or has no
## StorageInventory child. Public so haul legs (and any future caller) share one
## resolution path instead of each re-fetching the "StorageInventory" child.
func inventory_of(crate: Furniture) -> StorageInventory:
	if crate == null or not is_instance_valid(crate):
		return null
	return crate.get_node_or_null("StorageInventory") as StorageInventory


func _has_any(inv: StorageInventory, item_ids: Array[String]) -> bool:
	for id in item_ids:
		if inv.get_item_count(id) > 0:
			return true
	return false


func _find_matching_item_in_crates(item_id: String, tags: Array[StringName], near: Vector3) -> String:
	## Auxiliary: Searches crates for nearest item matching item_id or any tag in tags.
	var best_item_id: String = ""
	var best_dist_sq: float = INF
	for crate: Furniture in _crates():
		var inv: StorageInventory = inventory_of(crate)
		if inv == null:
			continue
		var matched_id: String = _find_matching_item_in_inventory(inv, item_id, tags)
		if matched_id != "":
			var d_sq: float = crate.global_position.distance_squared_to(near)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best_item_id = matched_id
	return best_item_id


func _find_matching_item_in_inventory(inv: StorageInventory, item_id: String, tags: Array[StringName]) -> String:
	## Auxiliary: Returns first matching item_id in the given inventory with positive count.
	if inv.items == null or not (inv.items is Dictionary):
		return ""
	if item_id != "" and inv.get_item_count(item_id) > 0:
		return item_id
	if not tags.is_empty():
		for key: Variant in inv.items.keys():
			var cid: String = str(key)
			if inv.get_item_count(cid) <= 0:
				continue
			if _item_def_matches_tags(cid, tags):
				return cid
	return ""


func _item_def_matches_tags(cid: String, tags: Array[StringName]) -> bool:
	## Auxiliary: Checks if the ItemDef for cid carries at least one of the tags.
	if ItemDB == null:
		return false
	var def: ItemDef = ItemDB.get_def(cid)
	if def == null:
		return false
	for tag: StringName in tags:
		if tag != &"" and def.has_tag(String(tag)):
			return true
	return false


## Finds the nearest available food source (crate or world item) not in blacklisted_sources.
## Returns { "source_node": Node, "source_type": String, "item_id": String } or {} if none found.
func find_best_food_source(near: Vector3, blacklisted_sources: Array = []) -> Dictionary:
	var best_result: Dictionary = {}
	var best_dist_sq: float = INF

	# 1. Crate Inspection: Search all non-blacklisted crates for valid food items.
	var crate_candidate: Dictionary = _find_nearest_food_in_crates(near, blacklisted_sources)
	if not crate_candidate.is_empty():
		best_dist_sq = float(crate_candidate.get("dist_sq", INF))
		best_result = crate_candidate

	# 2. Ground Item Inspection: Search unforbidden world items on the ground.
	var ground_candidate: Dictionary = _find_nearest_food_on_ground(near, blacklisted_sources)
	if not ground_candidate.is_empty():
		var ground_dist_sq: float = float(ground_candidate.get("dist_sq", INF))
		if ground_dist_sq < best_dist_sq:
			best_result = ground_candidate

	return best_result


## Total colony-wide count of edible food items across crates, world items, and pockets.
func colony_food_count() -> int:
	var total := 0

	# 1. Storage crates
	for crate: Furniture in _crates():
		var inv: StorageInventory = inventory_of(crate)
		if inv != null and inv.items is Dictionary:
			for item_id_var in inv.items.keys():
				var iid := str(item_id_var)
				# 1. Food Evaluation: Validate whether item definition is edible.
				if _is_edible_item(iid):
					total += inv.get_item_count(iid)

	var tree := _get_tree_context()
	if tree == null:
		return total

	# 2. WorldItems (unforbidden and unreserved)
	for node in tree.get_nodes_in_group("world_items"):
		var item := node as WorldItem
		if item == null or not is_instance_valid(item) or not item.is_inside_tree():
			continue
		if item.is_forbidden() or item.is_reserved():
			continue
		# 2. Ground Item Validation: Check if item is edible.
		if _is_edible_item(item.item_id):
			total += item.count

	# 3. Colonist carried inventories
	for node in tree.get_nodes_in_group("colonists"):
		var colonist := node as Colonist
		if colonist != null and is_instance_valid(colonist) and colonist.inventory != null:
			if colonist.inventory.items is Dictionary:
				for iid_var in colonist.inventory.items.keys():
					var iid := str(iid_var)
					# 3. Colonist Pockets: Check if carried item is edible.
					if _is_edible_item(iid):
						total += colonist.inventory.get_item_count(iid)

	# 4. Player carried inventory
	for node in tree.get_nodes_in_group("player"):
		var player := node as Player
		if player != null and is_instance_valid(player) and player.inventory != null:
			if player.inventory.items is Dictionary:
				for iid_var in player.inventory.items.keys():
					var iid := str(iid_var)
					# 4. Player Pockets: Check if carried item is edible.
					if _is_edible_item(iid):
						total += player.inventory.get_item_count(iid)

	return total


func _find_nearest_food_in_crates(near: Vector3, blacklisted_sources: Array) -> Dictionary:
	## Auxiliary: Finds the nearest non-blacklisted crate that contains food.
	var best_candidate: Dictionary = {}
	var best_dist_sq: float = INF

	for crate: Furniture in _crates():
		if blacklisted_sources.has(crate):
			continue
		var inv: StorageInventory = inventory_of(crate)
		if inv == null or not (inv.items is Dictionary):
			continue

		for key in inv.items.keys():
			var item_id := str(key)
			if inv.get_item_count(item_id) <= 0:
				continue
			# 1. Edible Check: Verify item qualifies as food.
			if _is_edible_item(item_id):
				var d_sq := crate.global_position.distance_squared_to(near)
				if d_sq < best_dist_sq:
					best_dist_sq = d_sq
					best_candidate = {
						"source_node": crate,
						"source_type": "crate",
						"item_id": item_id,
						"dist_sq": d_sq
					}
				break

	return best_candidate


func _find_nearest_food_on_ground(near: Vector3, blacklisted_sources: Array) -> Dictionary:
	## Auxiliary: Finds the nearest unforbidden, unreserved ground item that is edible.
	var best_candidate: Dictionary = {}
	var best_dist_sq: float = INF
	var tree := _get_tree_context()
	if tree == null:
		return best_candidate

	for node in tree.get_nodes_in_group("world_items"):
		if blacklisted_sources.has(node):
			continue
		var item := node as WorldItem
		if item == null or not is_instance_valid(item) or not item.is_inside_tree():
			continue
		if item.is_forbidden() or item.is_reserved():
			continue
		# 1. Ground Item Edible Check: Validate item id.
		if _is_edible_item(item.item_id):
			var d_sq := item.global_position.distance_squared_to(near)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best_candidate = {
					"source_node": item,
					"source_type": "ground",
					"item_id": item.item_id,
					"dist_sq": d_sq
				}

	return best_candidate


func _is_edible_item(item_id: String) -> bool:
	## Auxiliary: Returns true if the ItemDef has FoodParams or has the "food" tag.
	if ItemDB == null or item_id == "":
		return false
	var def: ItemDef = ItemDB.get_def(item_id)
	if def == null:
		return false
	return def.is_food() or def.has_tag("food")
