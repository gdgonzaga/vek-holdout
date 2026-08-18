class_name EditorGridOverlay
extends RefCounted
## Helper for generating a flat wireframe reference grid for the MapEditor.
##
## Builds an ImmediateMesh grid at y=0 (slightly offset to avoid z-fighting)
## with configurable world-space extent and line spacing.

const DEFAULT_SIZE: float = 100.0
const DEFAULT_SPACING: float = 1.0
const DEFAULT_COLOR: Color = Color(0.5, 0.7, 1.0, 0.3)


## Creates and returns a MeshInstance3D with a wireframe line grid at y=0.
static func create(size: float = DEFAULT_SIZE, spacing: float = DEFAULT_SPACING, color: Color = DEFAULT_COLOR) -> MeshInstance3D:
	var mesh := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.no_depth_test = false

	mesh.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var half: float = size * 0.5
	var count := int(size / spacing)
	for i in range(count + 1):
		var pos: float = -half + float(i) * spacing
		# X line (along Z axis)
		mesh.surface_add_vertex(Vector3(pos, 0.01, -half))
		mesh.surface_add_vertex(Vector3(pos, 0.01, half))
		# Z line (along X axis)
		mesh.surface_add_vertex(Vector3(-half, 0.01, pos))
		mesh.surface_add_vertex(Vector3(half, 0.01, pos))
	mesh.surface_end()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "GridOverlay"
	mesh_instance.mesh = mesh
	return mesh_instance
