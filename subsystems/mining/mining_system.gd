class_name MiningSystem
extends Node

## Map-local manager for mining execution and designation markers.
##
## Listens to EventBus.dig_box_designated to instantiate persistent visual
## markers under a DesignationContainer, and listens to EventBus.dig_job_completed
## to free the corresponding marker and carve out the terrain.

var grid_adapter: VoxelGridAdapter


func _ready() -> void:
	EventBus.dig_box_designated.connect(_on_dig_box_designated)
	EventBus.dig_job_completed.connect(_on_dig_job_completed)


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
	box_mesh.size = Vector3.ONE
	
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.65, 0.15, 0.35) # Translucent Amber / Orange
	mat.render_priority = 5
	
	for cell in cells:
		var cell_name := "Marker_%d_%d_%d" % [cell.x, cell.y, cell.z]
		if container.has_node(cell_name):
			continue
		
		var marker := MeshInstance3D.new()
		marker.name = cell_name
		marker.mesh = box_mesh
		marker.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
		marker.material_override = mat
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
