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
# The unit-box mesh authored in build.tscn. Captured so show_remove_at() can
# restore it after _set_ghost_mesh() swapped in a def's mesh for placement.
var _default_mesh: Mesh
# Unit sphere (radius 1) for spherical smooth-terrain edits (dig carve, smooth
# material placement) — built in code, same as the material.
var _sphere_mesh: SphereMesh


func _ready() -> void:
	# Build the material in code so the .tscn only needs a plain MeshInstance3D.
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.no_depth_test = true
	_material.render_priority = 10
	_material.albedo_color = _COLOR_VALID
	material_override = _material
	_default_mesh = mesh
	_sphere_mesh = SphereMesh.new()
	_sphere_mesh.radius = 1.0
	_sphere_mesh.height = 2.0
	_sphere_mesh.radial_segments = 24
	_sphere_mesh.rings = 12
	hide()


## Show the ghost at a world-space origin. Tints by validity. Callers resolve
## the position: blocks pass the cell corner (Vector3(cell)); furniture passes
## the footprint center (FurnitureLayer.world_origin(...)).
func show_at(world_pos: Vector3, valid: bool) -> void:
	global_position = world_pos
	scale = Vector3.ONE
	set_valid(valid)
	show()


## Red unit-box preview on the cell a Deconstruct click would remove. Mirrors
## the erase ghost in addons/voxel_paint/. world_pos is the cell corner, same
## convention as show_at(); _default_mesh restores the unit box so a previously
## selected buildable's mesh doesn't bleed through. The unit BoxMesh is centered
## on its origin (unlike authored def meshes, which use the (0,0,0)->(1,1,1)
## corner convention), so offset by half a cell to align it with the cell.
func show_remove_at(world_pos: Vector3) -> void:
	mesh = _default_mesh
	global_position = world_pos + Vector3(0.5, 0.5, 0.5)
	scale = Vector3.ONE
	rotation_degrees.y = 0.0
	set_valid(false)
	show()


## Red preview of a specific mesh (e.g. the targeted furniture's def mesh) at a
## world position and yaw, overlaying the target a Deconstruct click would remove.
## The red material_override tints whatever mesh is supplied, so callers just pass
## the def mesh and the placed transform; matches the erase ghost in feel.
func show_remove_mesh_at(world_pos: Vector3, mesh: Mesh, yaw_degrees: float) -> void:
	self.mesh = mesh
	global_position = world_pos
	scale = Vector3.ONE
	rotation_degrees.y = yaw_degrees
	set_valid(false)
	show()


## Blob preview for spherical smooth-terrain edits (the dig carve volume, a
## smooth-material placement): a sphere scaled to `radius`, CENTERED on
## world_pos — unlike the box paths' corner convention, a sphere has no cell
## corner to sit on. What the preview shows is exactly what the edit changes.
func show_sphere_at(world_pos: Vector3, radius: float, valid: bool) -> void:
	mesh = _sphere_mesh
	global_position = world_pos
	scale = Vector3.ONE * maxf(radius, 0.001)
	rotation_degrees.y = 0.0
	set_valid(valid)
	show()


## Box preview for cuboid terrain edits (box dig carve): a box of dimensions
## `size`, CENTERED on world_pos.
func show_box_at(world_pos: Vector3, size: Vector3, valid: bool) -> void:
	mesh = _default_mesh
	global_position = world_pos
	scale = Vector3(maxf(size.x, 0.001), maxf(size.y, 0.001), maxf(size.z, 0.001))
	rotation_degrees.y = 0.0
	set_valid(valid)
	show()


func hide_() -> void:
	hide()


func set_valid(ok: bool) -> void:
	_material.albedo_color = _COLOR_VALID if ok else _COLOR_INVALID
