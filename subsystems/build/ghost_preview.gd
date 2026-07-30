class_name GhostPreview
extends MeshInstance3D
## Translucent cube shown where a block would be placed (ARCH "Build", line 450).
## Carries no logic about *where* to be — BuildController positions it each frame.
## Tinted green (valid) / red (invalid) via material_override.
##
## Mesh follows the voxel corner convention: it spans (0,0,0)->(1,1,1) in local
## space, so the MeshInstance3D's origin is placed exactly at the integer voxel
## cell (no centering offset). BuildController sets global_position to Vector3(cell).

const _COLOR_VALID := Color(0.2, 0.9, 0.3, 0.4)
const _COLOR_INVALID := Color(0.9, 0.2, 0.2, 0.4)

var _material: StandardMaterial3D


func _ready() -> void:
	# Build the material in code so the .tscn only needs a plain MeshInstance3D.
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = _COLOR_VALID
	material_override = _material
	hide()


## Show the ghost at a world-space origin. Tints by validity. Callers resolve
## the position: blocks pass the cell corner (Vector3(cell)); furniture passes
## the footprint center (FurnitureLayer.world_origin(...)).
func show_at(world_pos: Vector3, valid: bool) -> void:
	global_position = world_pos
	set_valid(valid)
	show()


func hide_() -> void:
	hide()


func set_valid(ok: bool) -> void:
	_material.albedo_color = _COLOR_VALID if ok else _COLOR_INVALID
