class_name VoxData
extends RefCounted
## In-memory representation of parsed MagicaVoxel (.vox) structure data.
##
## Holds the 3D dimensions (in Godot coordinate space: X=width, Y=height, Z=depth),
## a dictionary mapping Vector3i coordinates to 1-based palette color indices (1..255),
## and a 256-entry Color palette.

## Total dimensions of the voxel model volume (Godot space: X=width, Y=height, Z=depth).
var dimensions: Vector3i = Vector3i.ZERO

## Voxel coordinate map: Vector3i (Godot cell coords) -> int (1-based palette color index 1..255).
var voxel_map: Dictionary = {}

## 256-color palette parsed from RGBA chunk or default palette fallback.
var palette: Array[Color] = []


## Look up the color index at the given coordinate. Returns 0 if empty/absent.
func get_voxel(pos: Vector3i) -> int:
	return voxel_map.get(pos, 0)


## Set or overwrite a voxel at the given coordinate. If color_index <= 0, erases the voxel.
func set_voxel(pos: Vector3i, color_index: int) -> void:
	if color_index <= 0:
		voxel_map.erase(pos)
	else:
		voxel_map[pos] = color_index


## Check if a voxel exists at the given coordinate.
func has_voxel(pos: Vector3i) -> bool:
	return voxel_map.has(pos)


## Number of non-empty voxels.
func get_voxel_count() -> int:
	return voxel_map.size()


## Look up the Color for a given 1-based palette index (1..255).
func get_color(color_index: int) -> Color:
	var idx := color_index - 1
	if idx >= 0 and idx < palette.size():
		return palette[idx]
	return Color.WHITE


## Look up the hex color string (e.g. "RRGGBB") for a given 1-based palette index.
func get_hex_color(color_index: int) -> String:
	var col := get_color(color_index)
	return col.to_html(false)


## Returns all unique 1-based color indices used by the voxels in ascending order.
func get_used_color_indices() -> Array[int]:
	var used_set: Dictionary = {}
	for idx: int in voxel_map.values():
		used_set[idx] = true
	var result: Array[int] = []
	for idx: int in used_set.keys():
		result.append(idx)
	result.sort()
	return result
