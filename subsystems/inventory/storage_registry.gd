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
		var inv := _inventory_of(crate)
		if inv == null or not _has_any(inv, item_ids):
			continue
		var d: float = crate.global_position.distance_squared_to(near)
		if best == null or d < best_dist_sq:
			best = crate
			best_dist_sq = d
	return best


## True if any crate holds at least one of `item_ids`. Used by the producer
## (Colony._on_blueprint_placed) to decide haul-vs-construct, and by hauling's
## is_available gate so a no-source haul job is never claimable (and thus pruned).
func has_source_for(item_ids: Array[String]) -> bool:
	for crate in _crates():
		var inv := _inventory_of(crate)
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


## All live crate Furniture in the current map (Furniture nodes with a
## "StorageInventory" child). Computed each call so it never holds stale refs.
func _crates() -> Array[Furniture]:
	var out: Array[Furniture] = []
	if _container == null:
		return out
	for c in _container.get_children():
		if is_instance_valid(c) and c is Furniture and c.has_node("StorageInventory"):
			out.append(c)
	return out


func _inventory_of(crate: Furniture) -> StorageInventory:
	if crate == null or not is_instance_valid(crate):
		return null
	return crate.get_node_or_null("StorageInventory") as StorageInventory


func _has_any(inv: StorageInventory, item_ids: Array[String]) -> bool:
	for id in item_ids:
		if inv.get_item_count(id) > 0:
			return true
	return false
