class_name StrataBakeResult
extends RefCounted
## Encapsulates the output of a StrataBaker volumetric bake pass.
##
## Holds the baked ImageTexture3D, world-space origin/extents, palette mapping,
## and optional CPU Image slices for validation and querying.

var texture: ImageTexture3D = null
var origin: Vector3i = Vector3i.ZERO
var size: Vector3i = Vector3i.ZERO
var palette_by_id: Dictionary = {}
var id_by_palette: Dictionary = {}
var slices: Array[Image] = []


func get_palette_index(material_id: String) -> int:
	return palette_by_id.get(material_id, 0)


func get_material_id(palette_index: int) -> String:
	return id_by_palette.get(palette_index, "")


## Samples the palette index at world_pos from retained CPU slices.
## Returns 0 if slices are empty or if world_pos is outside bounds.
func sample_palette_index(world_pos: Vector3i) -> int:
	if slices.is_empty():
		return 0
	var lx := world_pos.x - origin.x
	var ly := world_pos.y - origin.y
	var lz := world_pos.z - origin.z
	if lx < 0 or lx >= size.x or ly < 0 or ly >= size.y or lz < 0 or lz >= size.z:
		return 0
	var img := slices[lz]
	if img == null:
		return 0
	var raw := img.get_data()
	return raw[ly * size.x + lx]


## Samples the material ID at world_pos from retained CPU slices.
func sample_material_id(world_pos: Vector3i) -> String:
	var idx := sample_palette_index(world_pos)
	return get_material_id(idx)
