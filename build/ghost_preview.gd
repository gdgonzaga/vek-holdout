class_name GhostPreview
extends MeshInstance3D
## Translucent cube shown where a block would be placed (ARCH "Build", line 450).
## Carries no logic about *where* to be — BuildController positions it each frame.
## Tinted green (valid) / red (invalid) via material_override.
##
## Mesh occupies the (0,0,0)->(1,1,1) voxel cell convention: the MeshInstance3D is
## offset +0.5 on every axis so the BoxMesh (centered on origin) fills the cell
## whose integer corner is its transform.origin. BuildController sets origin to
## the voxel index; this node offsets internally.

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
	# Offset so a BoxMesh centered on origin fills the cell at the integer origin.
	position = Vector3(0.5, 0.5, 0.5)
	hide()


## Show the ghost at a voxel cell (integer origin). Tints by validity.
func show_at(cell: Vector3i, valid: bool) -> void:
	global_position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	set_valid(valid)
	show()


func hide_() -> void:
	hide()


func set_valid(ok: bool) -> void:
	_material.albedo_color = _COLOR_VALID if ok else _COLOR_INVALID
