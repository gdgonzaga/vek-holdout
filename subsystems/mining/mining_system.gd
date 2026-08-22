class_name MiningSystem
extends Node

## Map-local manager for mining execution and designation markers.
##
## Listens to EventBus.dig_box_designated to instantiate persistent visual
## markers under a DesignationContainer, and listens to EventBus.dig_job_completed
## to free the corresponding marker and carve out the terrain.
## Automatically cleans up visual markers when terrain is mined/carved to air.

const _SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled;

uniform vec4 color_above : source_color;
uniform vec4 color_under : source_color;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

void fragment() {
    float depth = texture(depth_texture, SCREEN_UV).x;
    vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;
    float linear_depth = -view.z;
    float frag_depth = -VERTEX.z;
    
    if (frag_depth > linear_depth + 0.0001) {
        ALBEDO = color_under.rgb;
        ALPHA = color_under.a;
    } else {
        ALBEDO = color_above.rgb;
        ALPHA = color_above.a;
    }
}
"""

var grid_adapter: VoxelGridAdapter


func _ready() -> void:
	EventBus.dig_box_designated.connect(_on_dig_box_designated)
	EventBus.dig_job_completed.connect(_on_dig_job_completed)
	if grid_adapter != null:
		_bind_grid_signals()


func set_grid_adapter(adapter: VoxelGridAdapter) -> void:
	grid_adapter = adapter
	if is_inside_tree() and grid_adapter != null:
		_bind_grid_signals()


func _bind_grid_signals() -> void:
	if grid_adapter == null:
		return
	var smooth: SmoothGrid = grid_adapter.get_smooth_grid()
	if smooth != null and not smooth.material_carved.is_connected(_on_material_carved):
		smooth.material_carved.connect(_on_material_carved)


func _on_material_carved(_pos: Vector3) -> void:
	clean_air_markers()


## Scans active designation markers and removes any whose voxel location is now air.
func clean_air_markers() -> void:
	if grid_adapter == null:
		return
	var container := _get_or_create_marker_container()
	if container == null:
		return
	
	for child in container.get_children():
		var marker := child as Node3D
		if marker == null or marker.is_queued_for_deletion():
			continue
		var cell: Vector3i = marker.get_meta("cell", Vector3i.MAX)
		if cell == Vector3i.MAX:
			var parts := marker.name.split("_")
			if parts.size() == 4:
				cell = Vector3i(int(parts[1]), int(parts[2]), int(parts[3]))
		if cell != Vector3i.MAX and not grid_adapter.is_terrain_at(cell):
			marker.queue_free()


func _on_dig_box_designated(cells: Array) -> void:
	var typed_cells: Array[Vector3i] = []
	for c in cells:
		if c is Vector3i:
			typed_cells.append(c)
	_spawn_designation_markers(typed_cells)


func _spawn_designation_markers(cells: Array[Vector3i]) -> void:
	var container := _get_or_create_marker_container()
	if container == null:
		return
	
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(1.1, 1.1, 1.1)
	
	var shader := Shader.new()
	shader.code = _SHADER_CODE
	var marker_mat := ShaderMaterial.new()
	marker_mat.shader = shader
	marker_mat.render_priority = 10
	marker_mat.set_shader_parameter("color_above", Color(1.0, 0.65, 0.15, 0.5))
	marker_mat.set_shader_parameter("color_under", Color(0.35, 0.18, 0.04, 0.15))
	
	for cell in cells:
		var cell_name := "Marker_%d_%d_%d" % [cell.x, cell.y, cell.z]
		if container.has_node(cell_name):
			continue
		
		var marker := MeshInstance3D.new()
		marker.name = cell_name
		marker.set_meta("cell", cell)
		marker.mesh = box_mesh
		marker.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
		marker.material_override = marker_mat
		container.add_child(marker)


func _get_or_create_marker_container() -> Node3D:
	var root: Node = get_parent()
	if root == null:
		root = self
	var container := root.get_node_or_null("DesignationContainer") as Node3D
	if container == null:
		container = Node3D.new()
		container.name = "DesignationContainer"
		root.add_child(container)
	return container


## Called when a colonist completes a dig job at a cell: removes visual marker and carves terrain.
func _on_dig_job_completed(cell: Vector3i) -> void:
	var container := _get_or_create_marker_container()
	if container != null:
		var cell_name := "Marker_%d_%d_%d" % [cell.x, cell.y, cell.z]
		var marker := container.get_node_or_null(cell_name)
		if marker != null:
			marker.queue_free()

	if grid_adapter != null:
		grid_adapter.remove_block_at(cell)
		var smooth: SmoothGrid = grid_adapter.get_smooth_grid()
		if smooth != null:
			smooth.carve_box(Vector3(cell), Vector3(cell) + Vector3.ONE)
	
	clean_air_markers()
