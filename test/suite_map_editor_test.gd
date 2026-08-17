extends GdUnitTestSuite

## Test suite for MapEditor Phase 1 foundation components:
## - EditorHUD
## - EditorLauncher
## - MapEditor loading, scanning, terrain injection, and mouse-look

const MapEditorClass = preload("res://tools/map_editor/map_editor.gd")
const EditorHUDClass = preload("res://tools/map_editor/editor_hud.gd")
const EditorLauncherClass = preload("res://tools/map_editor/editor_launcher.gd")

func test_editor_hud_modes_and_info() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	# Initial mode
	hud.set_mode(MapEditorClass.Mode.NAVIGATE)
	assert_str(hud._mode_label.text).contains("NAVIGATE")
	assert_str(hud._hotkey_label.text).contains("Fly")

	# Block mode
	hud.set_mode(MapEditorClass.Mode.BLOCK)
	assert_str(hud._mode_label.text).contains("BLOCK")
	assert_str(hud._hotkey_label.text).contains("Paint")

	# Terrain mode
	hud.set_mode(MapEditorClass.Mode.TERRAIN)
	assert_str(hud._mode_label.text).contains("TERRAIN")
	assert_str(hud._hotkey_label.text).contains("Carve")

	# Map info dirty indicator
	hud.set_map_info("base", false)
	assert_str(hud._map_info_label.text).is_equal("Map: base")

	hud.set_map_info("base", true)
	assert_str(hud._map_info_label.text).is_equal("Map: base *")

	# Crosshair color update
	hud.set_crosshair_color(Color.RED)
	for child in hud._crosshair.get_children():
		if child is ColorRect:
			assert_object(child.color).is_equal(Color.RED)


func test_editor_launcher_population_and_signals() -> void:
	var launcher: EditorLauncher = auto_free(EditorLauncherClass.new())

	var dummy_def := MapDef.new()
	dummy_def.id = "test_map"
	dummy_def.display_name = "Test Map"
	dummy_def.map_type = MapDef.MapType.POI

	launcher.setup([dummy_def])

	var signal_map_spy := monitor_signals(launcher)
	launcher._on_map_selected("test_map")
	await assert_signal(launcher).is_emitted("map_selected", ["test_map"])

	launcher._new_name_input.text = "new_test_poi"
	launcher._new_type_select.selected = MapDef.MapType.POI
	launcher._on_create_pressed()
	await assert_signal(launcher).is_emitted("new_map_requested", ["new_test_poi", MapDef.MapType.POI])


func test_map_editor_scan_maps() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	var maps: Array[MapDef] = editor._scan_maps()
	assert_int(maps.size()).is_greater_equal(1)

	var has_base := false
	for def in maps:
		if def.id == "base":
			has_base = true
			assert_str(def.scene_path).is_equal("res://data/maps/base/map.tscn")
			assert_object(def.terrain_gen).is_not_null()
	assert_bool(has_base).is_true()


func test_map_editor_terrain_gen_injection() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())

	# Create a dummy node structure with SmoothGrid
	var root := Node3D.new()
	auto_free(root)

	var smooth := SmoothGrid.new()
	smooth.name = "SmoothGrid"
	root.add_child(smooth)

	var def := MapDef.new()
	def.terrain_gen = TerrainGenDef.new()

	editor._inject_terrain_gen(root, def)
	assert_object(smooth.terrain_gen).is_equal(def.terrain_gen)


func test_map_editor_attach_streams() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())

	var root := Node3D.new()
	auto_free(root)

	var blocky_grid := BlockyGrid.new()
	blocky_grid.name = "BlockyGrid"
	root.add_child(blocky_grid)

	var blocky_terrain := VoxelTerrain.new()
	blocky_terrain.name = "VoxelTerrain"
	blocky_grid.add_child(blocky_terrain)

	var smooth_grid := SmoothGrid.new()
	smooth_grid.name = "SmoothGrid"
	root.add_child(smooth_grid)

	var smooth_terrain := VoxelTerrain.new()
	smooth_terrain.name = "VoxelTerrain"
	smooth_grid.add_child(smooth_terrain)

	editor._attach_streams(root, "base")

	assert_bool(blocky_terrain.stream is VoxelStreamSQLite).is_true()
	assert_str((blocky_terrain.stream as VoxelStreamSQLite).database_path).is_equal("res://data/maps/base/map.sqlite")

	assert_bool(smooth_terrain.stream is VoxelStreamSQLite).is_true()
	assert_str((smooth_terrain.stream as VoxelStreamSQLite).database_path).is_equal("res://data/maps/base/terrain.sqlite")


func test_map_editor_load_and_unload_lifecycle() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	# Load base map
	editor.load_map("base")
	assert_object(editor._map_root).is_not_null()
	assert_str(editor._map_def.id).is_equal("base")
	assert_bool(editor._launcher.visible).is_false()
	assert_bool(editor._hud.visible).is_true()

	# Unload
	editor.unload_map()
	assert_object(editor._map_root).is_null()
	assert_object(editor._map_def).is_null()
	assert_bool(editor._launcher.visible).is_true()
	assert_bool(editor._hud.visible).is_false()


func test_map_editor_mouse_look() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")

	var initial_yaw: float = editor._cam_yaw
	var initial_pitch: float = editor._cam_pitch

	# Simulate mouse motion event
	var motion_event := InputEventMouseMotion.new()
	motion_event.relative = Vector2(10.0, 5.0)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	editor._input(motion_event)

	assert_float(editor._cam_yaw).is_less(initial_yaw)
	assert_float(editor._cam_pitch).is_less(initial_pitch)
	assert_float(editor._camera.rotation_degrees.x).is_equal_approx(editor._cam_pitch, 0.001)
	assert_float(editor._camera.rotation_degrees.y).is_equal_approx(editor._cam_yaw, 0.001)


func test_editor_hud_block_info() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	hud.set_mode(MapEditorClass.Mode.BLOCK)
	assert_bool(hud._block_info_panel.visible).is_true()

	hud.set_block_info("Planks", 3.5)
	assert_str(hud._block_label.text).contains("Planks")
	assert_str(hud._radius_label.text).contains("3.5")

	hud.set_mode(MapEditorClass.Mode.NAVIGATE)
	assert_bool(hud._block_info_panel.visible).is_false()


func test_map_editor_block_editing_init() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	
	assert_object(editor._block_library).is_not_null()
	assert_int(editor._selected_block_index).is_equal(6)
	assert_float(editor._brush_radius).is_equal_approx(1.0, 0.001)
	assert_object(editor._ghost).is_not_null()
	assert_bool(editor._ghost.visible).is_false()


func test_map_editor_cycle_block() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	
	var initial_idx := editor._selected_block_index
	editor._cycle_block(1)
	assert_int(editor._selected_block_index).is_not_equal(initial_idx)
