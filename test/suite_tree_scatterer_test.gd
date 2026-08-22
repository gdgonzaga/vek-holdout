class_name SuiteTreeScattererTest
extends GdUnitTestSuite

const MapClass = preload("res://subsystems/voxel/map.gd")
const FurnitureAuthoringClass = preload("res://addons/voxel_paint/furniture_authoring.gd")
const TreeScattererClass = preload("res://subsystems/map_authoring/tree_scatterer.gd")
const EditorLauncherClass = preload("res://tools/map_editor/editor_launcher.gd")
const TEMPLATE_PATH: String = "res://subsystems/maps/map_template.tscn"


func _create_test_map() -> Map:
	var packed := load(TEMPLATE_PATH) as PackedScene
	var map: Map = packed.instantiate() as Map
	return map


func test_tree_scatterer_places_trees_on_terrain() -> void:
	var map: Map = auto_free(_create_test_map())
	add_child(map)

	var auth: FurnitureAuthoring = auto_free(FurnitureAuthoringClass.new())
	var bound: bool = auth.bind(map)
	assert_bool(bound).is_true()

	var placed: int = TreeScattererClass.scatter_trees(
		map,
		auth,
		[{"id": "tree1", "weight": 1.0}],
		{
			"target_count": 15,
			"min_distance": 3.0,
			"radius": 32.0,
			"cluster_threshold": -1.0,
			"seed": 12345,
		}
	)

	assert_int(placed).is_greater(0)

	var spawn_points: Node3D = map.get_node("SpawnPoints") as Node3D
	var tree_markers: Array[Node] = []
	for child in spawn_points.get_children():
		if child is Marker3D and child.name.begins_with("Furniture_tree1_"):
			tree_markers.append(child)

	assert_int(tree_markers.size()).is_equal(placed)


func test_tree_scatterer_respects_player_spawn_clearance() -> void:
	var map: Map = auto_free(_create_test_map())
	add_child(map)

	var pmarker: Marker3D = map.get_node("SpawnPoints/PlayerSpawn") as Marker3D
	pmarker.global_position = Vector3(0, 0, 0)

	var auth: FurnitureAuthoring = auto_free(FurnitureAuthoringClass.new())
	auth.bind(map)

	var exclusion_radius: float = 12.0
	var placed: int = TreeScattererClass.scatter_trees(
		map,
		auth,
		[{"id": "tree1", "weight": 1.0}],
		{
			"target_count": 20,
			"min_distance": 2.0,
			"radius": 32.0,
			"player_exclusion_radius": exclusion_radius,
			"cluster_threshold": -1.0,
			"seed": 42,
		}
	)

	assert_int(placed).is_greater(0)

	var spawn_points: Node3D = map.get_node("SpawnPoints") as Node3D
	for child in spawn_points.get_children():
		if child is Marker3D and child.name.begins_with("Furniture_tree1_"):
			var mpos: Vector3 = (child as Marker3D).global_position
			var dist_xz: float = Vector2(mpos.x, mpos.z).length()
			assert_float(dist_xz).is_greater_equal(exclusion_radius - 1.5)


func test_tree_scatterer_enforces_min_distance() -> void:
	var map: Map = auto_free(_create_test_map())
	add_child(map)

	var auth: FurnitureAuthoring = auto_free(FurnitureAuthoringClass.new())
	auth.bind(map)

	var min_dist: float = 6.0
	var placed: int = TreeScattererClass.scatter_trees(
		map,
		auth,
		[{"id": "tree1", "weight": 1.0}],
		{
			"target_count": 15,
			"min_distance": min_dist,
			"radius": 40.0,
			"cluster_threshold": -1.0,
			"seed": 999,
		}
	)

	assert_int(placed).is_greater(0)

	var spawn_points: Node3D = map.get_node("SpawnPoints") as Node3D
	var positions: Array[Vector2] = []
	for child in spawn_points.get_children():
		if child is Marker3D and child.name.begins_with("Furniture_tree1_"):
			var mpos: Vector3 = (child as Marker3D).global_position
			positions.append(Vector2(mpos.x, mpos.z))

	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			var d: float = positions[i].distance_to(positions[j])
			assert_float(d).is_greater_equal(min_dist - 1.5)


func test_tree_scatterer_clear_trees_removes_all_markers() -> void:
	var map: Map = auto_free(_create_test_map())
	add_child(map)

	var auth: FurnitureAuthoring = auto_free(FurnitureAuthoringClass.new())
	auth.bind(map)

	var placed: int = TreeScattererClass.scatter_trees(
		map,
		auth,
		[{"id": "tree1", "weight": 1.0}],
		{
			"target_count": 10,
			"min_distance": 3.0,
			"radius": 30.0,
			"cluster_threshold": -1.0,
			"seed": 777,
		}
	)

	assert_int(placed).is_greater(0)

	var removed: int = TreeScattererClass.clear_trees(auth, ["tree1"])
	assert_int(removed).is_equal(placed)

	var spawn_points: Node3D = map.get_node("SpawnPoints") as Node3D
	var remaining: int = 0
	for child in spawn_points.get_children():
		if child is Marker3D and child.name.begins_with("Furniture_tree1_") and not child.is_queued_for_deletion():
			remaining += 1

	assert_int(remaining).is_equal(0)


func test_editor_launcher_payload_includes_tree_scatter_options() -> void:
	var launcher: EditorLauncher = auto_free(EditorLauncherClass.new())
	add_child(launcher)

	var received: Array = []
	launcher.new_map_requested.connect(func(payload: Dictionary) -> void:
		received.append(payload)
	)

	launcher._new_name_input.text = "test_tree_map"
	launcher._terrain_mode_select.selected = EditorLauncherClass.TerrainMode.NOISE
	launcher._scatter_trees_check.button_pressed = true
	launcher._tree_density_select.selected = 2

	launcher._on_create_pressed()

	assert_int(received.size()).is_equal(1)
	var payload: Dictionary = received[0]
	assert_bool(payload.get("scatter_trees", false)).is_true()
	assert_int(payload.get("tree_density", 0)).is_equal(2)
