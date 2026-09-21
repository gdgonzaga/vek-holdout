class_name EditorGhost
extends Node3D
## Owns and renders ghost previews (blocks, terrain sculpt spheres, furniture, spawn capsules)
## and the 3D rotation axis indicator line for the Map Editor.

const COLOR_BLOCK_PAINT := Color(0.2, 0.8, 0.2, 0.5)
const COLOR_BLOCK_ERASE := Color(1.0, 0.2, 0.2, 0.5)
const COLOR_TERRAIN_PAINT := Color(0.2, 0.8, 0.4, 0.5)
const COLOR_TERRAIN_ERASE := Color(1.0, 0.2, 0.2, 0.5)
const COLOR_FURNITURE_PAINT := Color(0.4, 0.8, 1.0, 0.5)
const COLOR_FURNITURE_ERASE := Color(1.0, 0.2, 0.2, 0.5)

var mesh_instance: MeshInstance3D = null
var material: StandardMaterial3D = null
var axis_line: MeshInstance3D = null
var axis_line_mat: StandardMaterial3D = null
var box_mesh: BoxMesh = null

var _sphere_mesh: SphereMesh = null
var _capsule_mesh: CapsuleMesh = null
var _cylinder_mesh: CylinderMesh = null


# =================
# Primary Functions
# =================

## Builds child nodes, meshes, materials, and axis line visualizer.
func setup() -> void:
	# 1. Mesh Resources: Instantiate standard primitive meshes.
	_init_primitive_meshes()
	# 2. Ghost Node: Instantiate primary ghost MeshInstance3D and material.
	_init_ghost_mesh_node()
	# 3. Axis Visualizer: Instantiate axis line indicator and material.
	_init_axis_line_node()


## Hides both ghost preview mesh and rotation axis line.
func hide_all() -> void:
	if mesh_instance != null:
		mesh_instance.visible = false
	# 1. Axis Concealment: Ensure rotation axis line is hidden.
	hide_axis()


## Displays box ghost for block brush volume.
func show_box(center: Vector3, basis: Basis, erase: bool) -> void:
	if mesh_instance == null or material == null:
		return
	mesh_instance.mesh = box_mesh
	mesh_instance.global_position = center
	mesh_instance.transform.basis = basis
	material.albedo_color = COLOR_BLOCK_ERASE if erase else COLOR_BLOCK_PAINT
	mesh_instance.visible = true


## Displays custom mesh for single-voxel rotatable block definitions.
func show_custom_mesh(mesh: Mesh, world_pos: Vector3, basis: Basis, erase: bool) -> void:
	if mesh_instance == null or material == null:
		return
	mesh_instance.mesh = mesh
	mesh_instance.global_position = world_pos
	mesh_instance.transform.basis = basis
	material.albedo_color = COLOR_BLOCK_ERASE if erase else COLOR_BLOCK_PAINT
	mesh_instance.visible = true


## Displays spherical brush for smooth terrain sculpting.
func show_sphere(point: Vector3, radius: float, erase: bool) -> void:
	if mesh_instance == null or material == null:
		return
	mesh_instance.mesh = _sphere_mesh
	mesh_instance.global_position = point
	mesh_instance.scale = Vector3.ONE * radius
	mesh_instance.global_rotation = Vector3.ZERO
	material.albedo_color = COLOR_TERRAIN_ERASE if erase else COLOR_TERRAIN_PAINT
	mesh_instance.visible = true


## Displays furniture mesh at world origin with quarter-turn yaw.
func show_furniture(mesh: Mesh, world_pos: Vector3, yaw_quarters: int, erase: bool) -> void:
	if mesh_instance == null or material == null:
		return
	mesh_instance.mesh = mesh
	mesh_instance.scale = Vector3.ONE
	mesh_instance.global_position = world_pos
	mesh_instance.global_rotation = Vector3(0, deg_to_rad(yaw_quarters * 90), 0)
	material.albedo_color = COLOR_FURNITURE_ERASE if erase else COLOR_FURNITURE_PAINT
	mesh_instance.visible = true


## Displays capsule preview for spawn marker authoring.
func show_capsule(world_pos: Vector3, color: Color) -> void:
	if mesh_instance == null or material == null:
		return
	mesh_instance.mesh = _capsule_mesh
	mesh_instance.scale = Vector3.ONE
	mesh_instance.global_position = world_pos + Vector3(0, 0.9, 0)
	mesh_instance.global_rotation = Vector3.ZERO
	material.albedo_color = color
	mesh_instance.visible = true


## Displays rotation axis line oriented along specified axis (0=Y, 1=X, 2=Z).
func show_axis(world_pos: Vector3, axis: int) -> void:
	if axis_line == null or axis_line_mat == null:
		return
	axis_line.global_position = world_pos
	match axis:
		0: # Y (Yaw)
			axis_line.transform.basis = Basis.IDENTITY
			axis_line_mat.albedo_color = Color(0.2, 1.0, 0.2, 0.95)
		1: # X (Pitch)
			axis_line.transform.basis = Basis(Vector3.FORWARD, deg_to_rad(90))
			axis_line_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.95)
		2: # Z (Roll)
			axis_line.transform.basis = Basis(Vector3.RIGHT, deg_to_rad(90))
			axis_line_mat.albedo_color = Color(0.2, 0.6, 1.0, 0.95)
	axis_line.visible = true


## Hides the rotation axis indicator line.
func hide_axis() -> void:
	if axis_line != null:
		axis_line.visible = false


# ===================
# Auxiliary Functions
# ===================

func _init_primitive_meshes() -> void:
	## Auxiliary: Instantiates Box, Sphere, and Capsule mesh resources.
	box_mesh = BoxMesh.new()
	_sphere_mesh = SphereMesh.new()
	# Unit-radius sphere so scale matches the brush radius in metres.
	_sphere_mesh.radius = 1.0
	_sphere_mesh.height = 2.0
	_capsule_mesh = CapsuleMesh.new()
	_capsule_mesh.radius = 0.4
	_capsule_mesh.height = 1.8


func _init_ghost_mesh_node() -> void:
	## Auxiliary: Builds and configures ghost MeshInstance3D and unshaded material.
	material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 1.0, 1.0, 0.5)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "GhostMesh"
	mesh_instance.material_override = material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.visible = false
	add_child(mesh_instance)


func _init_axis_line_node() -> void:
	## Auxiliary: Builds and configures cylinder mesh and MeshInstance3D for rotation axis line.
	_cylinder_mesh = CylinderMesh.new()
	_cylinder_mesh.top_radius = 0.025
	_cylinder_mesh.bottom_radius = 0.025
	_cylinder_mesh.height = 1.8
	_cylinder_mesh.radial_segments = 12

	axis_line_mat = StandardMaterial3D.new()
	axis_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	axis_line_mat.no_depth_test = true
	axis_line_mat.albedo_color = Color(0.2, 1.0, 0.2, 0.95)

	axis_line = MeshInstance3D.new()
	axis_line.name = "AxisLineVisualizer"
	axis_line.mesh = _cylinder_mesh
	axis_line.material_override = axis_line_mat
	axis_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	axis_line.visible = false
	add_child(axis_line)
