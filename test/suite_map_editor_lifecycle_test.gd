extends GdUnitTestSuite
## Map lifecycle: scan/load/unload, exit and delete confirmation dialogs, map
## id validation, mouse capture, the config schema, and the editor's own
## viewport/camera plumbing (split from suite_map_editor_test.gd, R12D).

const MapEditorClass = preload("res://tools/map_editor/map_editor.gd")
const Sandbox = preload("res://test/helpers/map_editor_sandbox.gd")


## Sweeps crash leftovers once per suite run so a prior aborted run's throwaway
## maps never collide with this suite's own sandbox ids.
func before() -> void:
	Sandbox.sweep_stale()


## Several tests in this suite drive UiGate-style cursor capture/release paths
## and assign Input.mouse_mode directly with no guaranteed restore. Snapshotting
## it here (rather than a blanket reset to MOUSE_MODE_VISIBLE) stops a leftover
## captured cursor from leaking into the next test in this suite or into a
## later suite in a batch run.
var _saved_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE


func before_test() -> void:
	_saved_mouse_mode = Input.mouse_mode


func after_test() -> void:
	Input.mouse_mode = _saved_mouse_mode


## Throwaway map id for creation tests; removed before AND after each test so a
## crashed run never leaves committed-looking content behind.
var TEST_HEIGHTMAP_MAP := Sandbox.map_id("heightmap_map")


func test_map_editor_scan_maps() -> void:
	var maps := MapRepository.scan_maps()

	assert_bool(maps.is_empty()).is_false()
	for m in maps:
		assert_object(m).is_not_null()
		assert_str(m.id).is_not_empty()


func test_map_editor_attach_streams() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	var root := Node3D.new()
	# Sandbox id only: _attach_streams never touches disk, so no map needs creating here.
	var id := Sandbox.map_id("attach_streams")

	var blocky := Node.new()
	blocky.name = "BlockyGrid"
	var blocky_terrain := VoxelTerrain.new()
	blocky_terrain.name = "VoxelTerrain"
	blocky.add_child(blocky_terrain)
	root.add_child(blocky)

	var smooth := Node.new()
	smooth.name = "SmoothGrid"
	var smooth_terrain := VoxelTerrain.new()
	smooth_terrain.name = "VoxelTerrain"
	smooth.add_child(smooth_terrain)
	root.add_child(smooth)

	editor._attach_streams(root, id)

	assert_bool(blocky_terrain.stream is VoxelStreamSQLite).is_true()
	assert_str((blocky_terrain.stream as VoxelStreamSQLite).database_path).is_equal(Sandbox.map_dir(id) + "map.sqlite")

	assert_bool(smooth_terrain.stream is VoxelStreamSQLite).is_true()
	assert_str((smooth_terrain.stream as VoxelStreamSQLite).database_path).is_equal(Sandbox.map_dir(id) + "terrain.sqlite")
	root.free()


func test_map_editor_load_and_unload_lifecycle() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("load_unload_lifecycle")

	# Load a throwaway sandbox map
	await Sandbox.create_and_load(get_tree(), editor, id, false)
	assert_object(editor._map_root).is_not_null()
	assert_str(editor._map_def.id).is_equal(id)
	assert_bool(editor._launcher.visible).is_false()
	assert_bool(editor._hud.visible).is_true()

	# Unload
	editor.unload_map()
	assert_object(editor._map_root).is_null()
	assert_object(editor._map_def).is_null()
	assert_bool(editor._launcher.visible).is_true()
	assert_bool(editor._hud.visible).is_false()
	await Sandbox.dispose(get_tree(), editor, id)


func test_map_editor_mouse_look() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("mouse_look")
	await Sandbox.create_and_load(get_tree(), editor, id, false)

	var initial_yaw: float = editor._cam_yaw
	var initial_pitch: float = editor._cam_pitch

	# Simulate mouse look update
	var motion_relative := Vector2(10.0, 5.0)
	editor._cam_yaw -= motion_relative.x * MapEditorClass.MOUSE_SENSITIVITY
	editor._cam_pitch -= motion_relative.y * MapEditorClass.MOUSE_SENSITIVITY
	editor._apply_camera_rotation()

	assert_float(editor._cam_yaw).is_less(initial_yaw)
	assert_float(editor._cam_pitch).is_less(initial_pitch)
	assert_float(editor._camera.rotation_degrees.x).is_equal_approx(editor._cam_pitch, 0.001)
	assert_float(editor._camera.rotation_degrees.y).is_equal_approx(editor._cam_yaw, 0.001)
	await Sandbox.dispose(get_tree(), editor, id)


func test_map_editor_escape_shows_confirmation_when_mouse_free() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("escape_shows_confirmation_when_mouse_free")
	await Sandbox.create_and_load(get_tree(), editor, id, false)

	# First ESC when captured releases mouse
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var esc_event := InputEventKey.new()
	esc_event.pressed = true
	esc_event.keycode = KEY_ESCAPE

	editor._input(esc_event)
	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_VISIBLE)
	assert_bool(editor._exit_dialog.visible).is_false()
	assert_object(editor._map_root).is_not_null()

	# Second ESC when mouse free shows confirmation prompt
	editor._input(esc_event)
	assert_bool(editor._exit_dialog.visible).is_true()
	assert_object(editor._map_root).is_not_null()
	await Sandbox.dispose(get_tree(), editor, id)


func test_map_editor_exit_confirmation_cancel_keeps_map_loaded() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("exit_confirmation_cancel_keeps_map_loaded")
	await Sandbox.create_and_load(get_tree(), editor, id, false)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	editor._request_exit()
	assert_bool(editor._exit_dialog.visible).is_true()

	editor._exit_dialog.hide()
	assert_object(editor._map_root).is_not_null()
	await Sandbox.dispose(get_tree(), editor, id)


func test_map_editor_exit_confirmation_confirm_unloads_map() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("exit_confirmation_confirm_unloads_map")
	await Sandbox.create_and_load(get_tree(), editor, id, false)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	editor._request_exit()
	assert_bool(editor._exit_dialog.visible).is_true()

	editor._exit_dialog.confirmed.emit()
	assert_object(editor._map_root).is_null()
	assert_bool(editor._launcher.visible).is_true()
	await Sandbox.dispose(get_tree(), editor, id)


func test_map_editor_mouse_lmb_input_recaptures_when_visible() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("mouse_lmb_input_recaptures_when_visible")
	await Sandbox.create_and_load(get_tree(), editor, id, false)

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_VISIBLE)

	var lmb := InputEventMouseButton.new()
	lmb.pressed = true
	lmb.button_index = MOUSE_BUTTON_LEFT
	editor._input(lmb)

	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_CAPTURED)
	await Sandbox.dispose(get_tree(), editor, id)


## _delete_map removes the map directory and all its files from disk.
func test_map_editor_delete_map_removes_directory() -> void:
	Sandbox.remove_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(TEST_HEIGHTMAP_MAP))

	var dir_path := Sandbox.map_dir(TEST_HEIGHTMAP_MAP)
	assert_bool(DirAccess.dir_exists_absolute(dir_path)).is_true()

	var ok := MapRepository.delete_map(TEST_HEIGHTMAP_MAP)
	assert_bool(ok).is_true()
	assert_bool(DirAccess.dir_exists_absolute(dir_path)).is_false()


## Canceling the delete confirmation dialog leaves the map on disk.
func test_map_editor_delete_confirmation_cancel_keeps_map() -> void:
	Sandbox.remove_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(TEST_HEIGHTMAP_MAP))

	editor._request_delete_map(TEST_HEIGHTMAP_MAP)
	assert_str(editor._pending_delete_map_id).is_equal(TEST_HEIGHTMAP_MAP)
	assert_bool(editor._delete_dialog.visible).is_true()

	editor._delete_dialog.hide()
	assert_bool(DirAccess.dir_exists_absolute(Sandbox.map_dir(TEST_HEIGHTMAP_MAP))).is_true()

	editor._pending_delete_map_id = ""
	await Sandbox.dispose(get_tree(), editor, TEST_HEIGHTMAP_MAP)


## Confirming the delete dialog removes the map and refreshes the launcher
## list (the deleted map no longer appears).
func test_map_editor_delete_confirmation_confirm_removes_map() -> void:
	Sandbox.remove_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(TEST_HEIGHTMAP_MAP))

	editor._request_delete_map(TEST_HEIGHTMAP_MAP)
	editor._delete_dialog.confirmed.emit()

	assert_bool(DirAccess.dir_exists_absolute(Sandbox.map_dir(TEST_HEIGHTMAP_MAP))).is_false()
	assert_str(editor._pending_delete_map_id).is_empty()

	var maps: Array[MapDef] = MapRepository.scan_maps()
	var found := false
	for m in maps:
		if m.id == TEST_HEIGHTMAP_MAP:
			found = true
	assert_bool(found).is_false()

	# No need to dispose — map already deleted
	editor.unload_map()


## Map editor creation configures flora parameters and begins with 0 authored trees.
func test_map_editor_new_map_with_flora_parameters() -> void:
	var TEST_FLORA_MAP := Sandbox.map_id("flora_params_map")
	Sandbox.remove_map(TEST_FLORA_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	var payload := Sandbox.heightmap_payload(TEST_FLORA_MAP)
	payload["flora_spawns_per_day"] = 4
	payload["flora_spawn_cap"] = 50
	payload["flora_max_spawn_attempts"] = 20
	editor.create_new_map(payload)

	# Verify flora parameters persisted into MapDef
	assert_int(editor._map_def.flora_spawns_per_day).is_equal(4)
	assert_int(editor._map_def.flora_spawn_cap).is_equal(50)
	assert_int(editor._map_def.flora_max_spawn_attempts).is_equal(20)

	# Verify new maps begin with 0 pre-generated tree markers
	var spawn_points: Node3D = editor._map_root.get_node("SpawnPoints") as Node3D
	var tree_count := 0
	for child in spawn_points.get_children():
		if child is Marker3D and child.name.begins_with("Furniture_tree1_"):
			tree_count += 1

	assert_int(tree_count).is_equal(0)

	# Original _dispose_test_editor() always disposed TEST_HEIGHTMAP_MAP (a
	# different id than the map this test actually creates); preserved as-is
	# so behavior is unchanged by the split. The explicit remove_map below is
	# what actually cleans up this test's own TEST_FLORA_MAP folder.
	await Sandbox.dispose(get_tree(), editor, TEST_HEIGHTMAP_MAP)
	Sandbox.remove_map(TEST_FLORA_MAP)


func test_map_id_rules_accept_snake_case_only() -> void:
	assert_str(MapIdRules.validate("outpost_alpha2")).is_empty()
	for bad in ["", "Has Space", "UPPER", "9lives", "../evil", "a/b", "dash-name", "trailing.dot"]:
		assert_str(MapIdRules.validate(bad)).is_not_empty()


func test_create_new_map_rejects_path_traversal_and_writes_nothing() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var payload := Sandbox.blocky_only_payload("../zz_sandbox_escape")

	assert_str(editor.create_new_map(payload)).is_empty()
	assert_bool(DirAccess.dir_exists_absolute("res://data/zz_sandbox_escape")).is_false()


func test_blocky_only_map_has_no_smooth_grid_and_shows_the_terrain_warning() -> void:
	var id := Sandbox.map_id("no_terrain")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.blocky_only_payload(id))

	assert_object(editor._smooth_grid).is_null()
	assert_bool(editor._hud._terrain_warning_label.visible).is_true()
	await Sandbox.dispose(get_tree(), editor, id)


func test_wheel_belongs_to_the_view_only_when_captured_or_over_no_gui() -> void:
	assert_bool(MapEditorClass.wheel_belongs_to_view(true, true)).is_true()
	assert_bool(MapEditorClass.wheel_belongs_to_view(false, false)).is_true()
	assert_bool(MapEditorClass.wheel_belongs_to_view(false, true)).is_false()


func test_new_map_takes_terrain_and_flora_defaults_from_the_config() -> void:
	var id := Sandbox.map_id("config")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var config := MapEditorConfig.new()
	config.default_noise_def = Sandbox.save_noise_def("user://sandbox_config_noise.tres", 4321, 0.02)
	var flora := BuildableDef.new()
	flora.id = "zz_flora"
	config.default_flora_palette = [flora] as Array[BuildableDef]
	editor._config = config

	editor.create_new_map({"map_id": id, "map_type": MapDef.MapType.POI})

	assert_int(editor._map_def.terrain_gen.noise_seed).is_equal(4321)
	assert_str(editor._map_def.flora_palette[0].id).is_equal("zz_flora")
	DirAccess.remove_absolute("user://sandbox_config_noise.tres")
	await Sandbox.dispose(get_tree(), editor, id)


func test_editor_config_resource_loads_as_the_schema_type() -> void:
	assert_bool(load(MapEditorClass.CONFIG_PATH) is MapEditorConfig).is_true()


func test_camera_ray_center_uses_visible_rect_size() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	assert_vector(editor._camera_ray_center()).is_equal(Vector2.ZERO)
	add_child(editor)
	var expected_center := editor.get_viewport().get_visible_rect().size / 2.0
	assert_vector(editor._camera_ray_center()).is_equal(expected_center)
