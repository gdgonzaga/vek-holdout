class_name GhostPreview
extends MeshInstance3D
## Translucent cube shown where a block would be placed (ARCH "Build", line 450).
## Carries no logic about *where* to be — BuildController positions it each frame.
## Tinted green (valid) / red (invalid) via material_override.
##
## Default BoxMesh is centered at (0,0,0), so BuildController positions block preview
## ghosts at the cell center: Vector3(cell) + Vector3(0.5, 0.5, 0.5).

const _COLOR_VALID_ABOVE := Color(0.2, 0.9, 0.3, 0.5)
const _COLOR_VALID_UNDERGROUND := Color(1.0, 0.65, 0.15, 0.5)

const _COLOR_INVALID_ABOVE := Color(0.9, 0.2, 0.2, 0.5)
const _COLOR_INVALID_UNDERGROUND := Color(0.35, 0.05, 0.05, 0.15)

var _material: StandardMaterial3D
var _wire_material: StandardMaterial3D
var _wire_instance: MeshInstance3D
var _default_mesh: Mesh
var _sphere_mesh: SphereMesh


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.no_depth_test = false
	_material.albedo_color = _COLOR_VALID_ABOVE
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.render_priority = 10
	material_override = _material

	_wire_material = StandardMaterial3D.new()
	_wire_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wire_material.no_depth_test = false
	_wire_material.albedo_color = Color(1.0, 0.65, 0.15, 0.4)
	_wire_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_wire_material.render_priority = 9

	_wire_instance = MeshInstance3D.new()
	_wire_instance.material_override = _wire_material
	add_child(_wire_instance)

	if mesh != null:
		_default_mesh = mesh
	else:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		_default_mesh = box
	_sphere_mesh = SphereMesh.new()
	_sphere_mesh.radius = 1.0
	_sphere_mesh.height = 2.0
	_sphere_mesh.radial_segments = 24
	_sphere_mesh.rings = 12
	hide_()


## Show the ghost at a world-space origin. Tints by validity. Callers resolve
## the position: blocks pass the cell corner (Vector3(cell)); furniture passes
## the footprint center (FurnitureLayer.world_origin(...)).
func show_at(world_pos: Vector3, valid: bool) -> void:
	if _wire_instance != null:
		_wire_instance.hide()
	if mesh == null:
		mesh = _default_mesh
	global_position = world_pos
	scale = Vector3.ONE
	set_valid(valid)
	show()


func show_remove_at(world_pos: Vector3) -> void:
	if _wire_instance != null:
		_wire_instance.hide()
	mesh = _default_mesh
	global_position = world_pos + Vector3(0.5, 0.5, 0.5)
	scale = Vector3.ONE
	rotation_degrees.y = 0.0
	set_valid(false)
	show()


func show_remove_mesh_at(world_pos: Vector3, mesh_: Mesh, yaw_degrees: float) -> void:
	if _wire_instance != null:
		_wire_instance.hide()
	self.mesh = mesh_
	global_position = world_pos
	scale = Vector3.ONE
	rotation_degrees.y = yaw_degrees
	set_valid(false)
	show()


func show_sphere_at(world_pos: Vector3, radius: float, valid: bool) -> void:
	if _wire_instance != null:
		_wire_instance.hide()
	mesh = _sphere_mesh
	global_position = world_pos
	scale = Vector3.ONE * maxf(radius, 0.001)
	rotation_degrees.y = 0.0
	set_valid(valid)
	show()


func show_box_at(world_pos: Vector3, size: Vector3, valid: bool) -> void:
	if _wire_instance != null:
		_wire_instance.hide()
	mesh = _default_mesh
	global_position = world_pos
	scale = Vector3(maxf(size.x, 0.001), maxf(size.y, 0.001), maxf(size.z, 0.001))
	rotation_degrees.y = 0.0
	set_valid(valid)
	show()


func show_mesh_at(world_pos: Vector3, custom_mesh: Mesh, valid: bool) -> void:
	if _wire_instance != null:
		_wire_instance.hide()
	mesh = custom_mesh
	global_position = world_pos
	scale = Vector3.ONE
	rotation_degrees.y = 0.0
	set_valid(valid)
	show()


## Displays solid parts on self.mesh and air wireframes on _wire_instance simultaneously.
func show_split_at(world_pos: Vector3, solid_mesh: Mesh, wire_mesh: Mesh, valid: bool) -> void:
	global_position = world_pos
	scale = Vector3.ONE
	rotation_degrees.y = 0.0
	set_valid(valid)
	
	if solid_mesh != null:
		mesh = solid_mesh
		visible = true
	else:
		mesh = null
		visible = true
	
	if _wire_instance != null:
		if wire_mesh != null:
			_wire_instance.mesh = wire_mesh
			_wire_instance.show()
		else:
			_wire_instance.mesh = null
			_wire_instance.hide()
	
	show()


func hide_() -> void:
	if _wire_instance != null:
		_wire_instance.hide()
	hide()


func set_valid(ok: bool) -> void:
	if ok:
		_material.albedo_color = Color(1.0, 0.65, 0.15, 0.5)
	else:
		_material.albedo_color = _COLOR_INVALID_ABOVE
