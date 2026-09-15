class_name Area
extends RefCounted
## Plain data object representing a player-designated world region (ARCH "Areas").
##
## Defines a collection of axis-aligned 3D bounding boxes [min_cell, max_cell] inclusive,
## with a display name, unique identifier, and colonist member assignments.

var id: String = ""
var display_name: String = ""
var boxes: Array[Dictionary] = [] # Array of {"min": Vector3i, "max": Vector3i}
var member_colonist_ids: Array[String] = []


# =================
# Primary Functions
# =================

func add_box(b_min: Vector3i, b_max: Vector3i) -> void:
	# 1. Bounds Normalization: Derives component-wise min and max corners.
	var normalized: Dictionary = _normalize_box(b_min, b_max)
	boxes.append(normalized)


func erase_box(b_min: Vector3i, b_max: Vector3i) -> bool:
	# 1. Bounds Normalization: Normalizes the subtraction volume corners.
	var norm_erase: Dictionary = _normalize_box(b_min, b_max)
	# 2. Box Partitioning: Subtracts the volume from all constituent boxes.
	return _apply_box_subtraction(norm_erase["min"], norm_erase["max"])


func is_empty_area() -> bool:
	return boxes.is_empty()


func contains_cell(cell: Vector3i) -> bool:
	for b in boxes:
		var b_min: Vector3i = b["min"]
		var b_max: Vector3i = b["max"]
		# 1. Containment Check: Evaluates whether cell falls inside this box.
		if _is_within_bounds(cell, b_min, b_max):
			return true
	return false


func get_outer_bounds() -> Dictionary:
	if boxes.is_empty():
		return {"min": Vector3i.ZERO, "max": Vector3i.ZERO}
	# 1. Extents Calculation: Gathers minimum and maximum corners across all boxes.
	return _calculate_outer_bounds()


func serialize() -> Dictionary:
	# 1. Format Conversion: Serializes area properties into standard SaveSystem JSON primitives.
	return _to_serializable_dict()


static func from_dict(data: Dictionary) -> Area:
	var area := Area.new()
	area.id = str(data.get("id", ""))
	area.display_name = str(data.get("display_name", ""))
	# 1. Box Unpacking: Reconstructs boxes from serialized coordinate lists.
	area.boxes = _parse_boxes(data.get("boxes", []))
	# 2. Member List Population: Extracts member colonist IDs.
	area.member_colonist_ids = _parse_member_ids(data.get("member_colonist_ids", []))
	return area


# ===================
# Auxiliary Functions
# ===================

func _normalize_box(c1: Vector3i, c2: Vector3i) -> Dictionary:
	## Auxiliary: Derives component-wise min and max corners for a bounding box.
	return {
		"min": Vector3i(mini(c1.x, c2.x), mini(c1.y, c2.y), mini(c1.z, c2.z)),
		"max": Vector3i(maxi(c1.x, c2.x), maxi(c1.y, c2.y), maxi(c1.z, c2.z)),
	}


func _apply_box_subtraction(erase_min: Vector3i, erase_max: Vector3i) -> bool:
	## Auxiliary: Subtracts a 3D bounding box from all existing boxes in the area.
	var new_boxes: Array[Dictionary] = []
	var modified := false

	for box in boxes:
		var surviving: Array[Dictionary] = _subtract_box_from_box(box, erase_min, erase_max)
		if surviving.size() != 1 or surviving[0]["min"] != box["min"] or surviving[0]["max"] != box["max"]:
			modified = true
		for s in surviving:
			new_boxes.append(s)

	boxes = new_boxes
	return modified


func _subtract_box_from_box(a: Dictionary, b_min: Vector3i, b_max: Vector3i) -> Array[Dictionary]:
	## Auxiliary: Partitions the volume A \ B into up to 6 non-overlapping sub-boxes.
	var a_min: Vector3i = a["min"]
	var a_max: Vector3i = a["max"]

	var inter_min := Vector3i(maxi(a_min.x, b_min.x), maxi(a_min.y, b_min.y), maxi(a_min.z, b_min.z))
	var inter_max := Vector3i(mini(a_max.x, b_max.x), mini(a_max.y, b_max.y), mini(a_max.z, b_max.z))

	if inter_min.x > inter_max.x or inter_min.y > inter_max.y or inter_min.z > inter_max.z:
		return [a]

	var pieces: Array[Dictionary] = []

	if a_min.x < inter_min.x:
		pieces.append({
			"min": Vector3i(a_min.x, a_min.y, a_min.z),
			"max": Vector3i(inter_min.x - 1, a_max.y, a_max.z)
		})

	if a_max.x > inter_max.x:
		pieces.append({
			"min": Vector3i(inter_max.x + 1, a_min.y, a_min.z),
			"max": Vector3i(a_max.x, a_max.y, a_max.z)
		})

	if a_min.y < inter_min.y:
		pieces.append({
			"min": Vector3i(inter_min.x, a_min.y, a_min.z),
			"max": Vector3i(inter_max.x, inter_min.y - 1, a_max.z)
		})

	if a_max.y > inter_max.y:
		pieces.append({
			"min": Vector3i(inter_min.x, inter_max.y + 1, a_min.z),
			"max": Vector3i(inter_max.x, a_max.y, a_max.z)
		})

	if a_min.z < inter_min.z:
		pieces.append({
			"min": Vector3i(inter_min.x, inter_min.y, a_min.z),
			"max": Vector3i(inter_max.x, inter_max.y, inter_min.z - 1)
		})

	if a_max.z > inter_max.z:
		pieces.append({
			"min": Vector3i(inter_min.x, inter_min.y, inter_max.z + 1),
			"max": Vector3i(inter_max.x, inter_max.y, a_max.z)
		})

	return pieces


func _is_within_bounds(cell: Vector3i, b_min: Vector3i, b_max: Vector3i) -> bool:
	## Auxiliary: Checks if an integer coordinate is contained within inclusive 3D bounds.
	return (
		cell.x >= b_min.x and cell.x <= b_max.x
		and cell.y >= b_min.y and cell.y <= b_max.y
		and cell.z >= b_min.z and cell.z <= b_max.z
	)


func _calculate_outer_bounds() -> Dictionary:
	## Auxiliary: Calculates global min and max across all constituent boxes.
	var outer_min := boxes[0]["min"] as Vector3i
	var outer_max := boxes[0]["max"] as Vector3i

	for i in range(1, boxes.size()):
		var b_min: Vector3i = boxes[i]["min"]
		var b_max: Vector3i = boxes[i]["max"]
		outer_min = Vector3i(mini(outer_min.x, b_min.x), mini(outer_min.y, b_min.y), mini(outer_min.z, b_min.z))
		outer_max = Vector3i(maxi(outer_max.x, b_max.x), maxi(outer_max.y, b_max.y), maxi(outer_max.z, b_max.z))

	return {"min": outer_min, "max": outer_max}


func _to_serializable_dict() -> Dictionary:
	## Auxiliary: Converts boxes and member lists to basic JSON-compatible collections.
	var serialized_boxes: Array = []
	for b in boxes:
		var b_min: Vector3i = b.get("min", Vector3i.ZERO)
		var b_max: Vector3i = b.get("max", Vector3i.ZERO)
		serialized_boxes.append([b_min.x, b_min.y, b_min.z, b_max.x, b_max.y, b_max.z])
	return {
		"id": id,
		"display_name": display_name,
		"boxes": serialized_boxes,
		"member_colonist_ids": member_colonist_ids.duplicate(),
	}


static func _parse_boxes(boxes_raw: Variant) -> Array[Dictionary]:
	## Auxiliary: Parses raw box arrays into typed {"min": Vector3i, "max": Vector3i} dictionaries.
	var result: Array[Dictionary] = []
	if boxes_raw is Array:
		for item in (boxes_raw as Array):
			if item is Array and (item as Array).size() >= 6:
				var a: Array = item as Array
				result.append({
					"min": Vector3i(int(a[0]), int(a[1]), int(a[2])),
					"max": Vector3i(int(a[3]), int(a[4]), int(a[5])),
				})
	return result


static func _parse_member_ids(members_raw: Variant) -> Array[String]:
	## Auxiliary: Casts a raw variant array into a typed Array[String].
	var result: Array[String] = []
	if members_raw is Array:
		for m in (members_raw as Array):
			result.append(str(m))
	return result
