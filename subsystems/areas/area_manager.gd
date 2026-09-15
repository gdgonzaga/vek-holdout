class_name AreaManager
extends Node
## Manages player-designated rectangular regions in the world (ARCH "Areas").
##
## Provides CRUD, membership tracking, spatial queries, and save/load persistence.
## Owned by Colony autoload alongside JobBoard and StorageRegistry.

var _areas: Dictionary = {} # String (area_id) -> Area
var _area_counter: int = 0


# =================
# Primary Functions
# =================

func create_area(min_cell: Vector3i, max_cell: Vector3i, display_name: String = "") -> Area:
	var area := Area.new()
	# 1. Identity Generation: Generates a unique UUID for the area entity.
	area.id = _generate_unique_id()
	# 2. Box Addition: Adds initial bounding box to the area's box collection.
	area.add_box(min_cell, max_cell)
	# 3. Name Resolution: Sets custom name or auto-generates sequential default.
	area.display_name = _resolve_display_name(display_name)
	_areas[area.id] = area
	return area


func paint_area(area_id: String, min_cell: Vector3i, max_cell: Vector3i) -> Area:
	var area: Area = get_area(area_id)
	if area != null:
		# 1. Box Addition: Appends the painted box to the existing area.
		area.add_box(min_cell, max_cell)
		return area
	return null


func erase_area(area_id: String, min_cell: Vector3i, max_cell: Vector3i) -> Area:
	var area: Area = get_area(area_id)
	if area != null:
		# 1. Box Subtraction: Subtracts volume from all existing boxes.
		area.erase_box(min_cell, max_cell)
		if area.is_empty_area():
			# 2. Area Cleanup: Deletes area entity when its last box has been erased.
			delete_area(area_id)
			return null
		return area
	return null


func rename_area(area_id: String, new_name: String) -> void:
	# 1. Existence Check: Finds the designated area by ID to apply the new name.
	var area: Area = get_area(area_id)
	if area != null and not new_name.strip_edges().is_empty():
		area.display_name = new_name.strip_edges()


func delete_area(area_id: String) -> void:
	# 1. Removal: Erases the designated area record from the registry.
	_areas.erase(area_id)


func get_area(area_id: String) -> Area:
	# 1. Lookup: Fetches area by ID or returns null if not registered.
	return _areas.get(area_id, null) as Area


func get_all_areas() -> Array[Area]:
	# 1. Collection: Gathers all registered areas in deterministic array format.
	return _collect_all_areas()


func get_areas_at(cell: Vector3i) -> Array[Area]:
	# 1. Spatial Filtering: Finds all areas whose inclusive bounding box contains cell.
	return _find_areas_containing(cell)


func is_point_in_any_area(cell: Vector3i) -> bool:
	# 1. Spatial Check: Tests whether any designated area contains cell.
	return not get_areas_at(cell).is_empty()


func add_member(area_id: String, colonist_id: String) -> void:
	var area: Area = get_area(area_id)
	if area != null and not area.member_colonist_ids.has(colonist_id):
		# 1. List Mutation: Appends the colonist ID to the area's member roster.
		area.member_colonist_ids.append(colonist_id)


func remove_member(area_id: String, colonist_id: String) -> void:
	var area: Area = get_area(area_id)
	if area != null:
		# 1. List Mutation: Erases the colonist ID from the area's member roster.
		area.member_colonist_ids.erase(colonist_id)


func remove_member_from_all_areas(colonist_id: String) -> void:
	# 1. Membership Hygiene: Removes the colonist from every registered area on death/departure.
	_scrub_colonist_from_all_areas(colonist_id)


func get_members(area_id: String) -> Array[String]:
	var area: Area = get_area(area_id)
	if area != null:
		# 1. Copy Creation: Returns a duplicate of member IDs to prevent external mutations.
		return area.member_colonist_ids.duplicate()
	return []


func serialize() -> Dictionary:
	# 1. Record Serialization: Maps all Area entities to JSON-serializable dictionaries.
	var records: Array[Dictionary] = _serialize_areas()
	return {
		"areas": records,
		"counter": _area_counter,
	}


func deserialize(data: Dictionary) -> void:
	# 1. State Reset: Clears existing areas before repopulating from save data.
	reset_for_new_game()
	_area_counter = int(data.get("counter", 0))
	var raw_areas: Array = data.get("areas", [])
	# 2. Record Restoration: Deserializes area objects into the internal dictionary.
	_populate_from_records(raw_areas)


func reset_for_new_game() -> void:
	# 1. State Clear: Wipes registered areas and resets default counter.
	_areas.clear()
	_area_counter = 0


# ===================
# Auxiliary Functions
# ===================

func _generate_unique_id() -> String:
	## Auxiliary: Obtains a new UUID from Tools autoload or fallback ResourceUID.
	if ClassDB.class_exists(&"Tools") and Tools.has_method("generate_uuid"):
		return Tools.generate_uuid()
	return str(ResourceUID.create_id())



func _resolve_display_name(candidate_name: String) -> String:
	## Auxiliary: Resolves display name, generating sequential Area N if empty.
	if not candidate_name.strip_edges().is_empty():
		return candidate_name.strip_edges()
	_area_counter += 1
	return "Area %d" % _area_counter


func _collect_all_areas() -> Array[Area]:
	## Auxiliary: Gathers all registered Area values into a typed array.
	var list: Array[Area] = []
	for a in _areas.values():
		if a is Area:
			list.append(a as Area)
	return list


func _find_areas_containing(cell: Vector3i) -> Array[Area]:
	## Auxiliary: Checks all registered areas for containment of the specified voxel cell.
	var matching: Array[Area] = []
	for a in _areas.values():
		var area := a as Area
		if area != null and area.contains_cell(cell):
			matching.append(area)
	return matching


func _scrub_colonist_from_all_areas(colonist_id: String) -> void:
	## Auxiliary: Removes a colonist ID from every area's membership array.
	for a in _areas.values():
		var area := a as Area
		if area != null:
			area.member_colonist_ids.erase(colonist_id)


func _serialize_areas() -> Array[Dictionary]:
	## Auxiliary: Serializes all managed Area instances into an array of dictionaries.
	var result: Array[Dictionary] = []
	for a in _areas.values():
		var area := a as Area
		if area != null:
			result.append(area.serialize())
	return result


func _populate_from_records(records: Array) -> void:
	## Auxiliary: Restores Area instances from an array of serialized dictionaries.
	for item in records:
		if item is Dictionary:
			var area := Area.from_dict(item as Dictionary)
			if not area.id.is_empty():
				_areas[area.id] = area
