extends GdUnitTestSuite

const EditorLauncherClass = preload("res://tools/map_editor/editor_launcher.gd")
const EditorHUDClass = preload("res://tools/map_editor/editor_hud.gd")
const MapEditorClass = preload("res://tools/map_editor/map_editor.gd")


func test_editor_hud_modes_and_info() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	hud.set_mode(MapEditorClass.Mode.BLOCK)
	assert_str(hud._mode_label.text).is_equal("[ F2 ] BLOCK")

	hud.set_map_info("base", true)
	assert_str(hud._map_info_label.text).is_equal("Map: base *")

	hud.set_map_info("base", false)
	assert_str(hud._map_info_label.text).is_equal("Map: base")


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

	hud.set_block_info("Planks", 5)
	assert_str(hud._block_label.text).contains("Planks")
	assert_str(hud._brush_label.text).contains("5x5x5")

	hud.set_block_info("Wood", 1)
	assert_str(hud._brush_label.text).contains("1x1x1")

	hud.set_mode(MapEditorClass.Mode.NAVIGATE)
	assert_bool(hud._block_info_panel.visible).is_false()


func test_brush_box_matches_diameter() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	var cell := Vector3i(10, 10, 10)

	# Odd diameters center exactly on the cell; end is inclusive (do_box build).
	editor._brush_diameter = 1
	assert_vector(editor._brush_box(cell)[0]).is_equal(cell)
	assert_vector(editor._brush_box(cell)[1]).is_equal(cell)

	editor._brush_diameter = 5
	assert_vector(editor._brush_box(cell)[0]).is_equal(cell - Vector3i(2, 2, 2))
	assert_vector(editor._brush_box(cell)[1]).is_equal(cell + Vector3i(2, 2, 2))

	# Even diameters are biased one cell toward +x/+y/+z.
	editor._brush_diameter = 4
	assert_vector(editor._brush_box(cell)[0]).is_equal(cell - Vector3i(1, 1, 1))
	assert_vector(editor._brush_box(cell)[1]).is_equal(cell + Vector3i(2, 2, 2))


func test_target_cell_surfaces() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())

	var blocky_hit := {
		"hit": true, "surface": "blocky",
		"position": Vector3i(4, 2, 7), "normal": Vector3i(0, 1, 0),
	}
	assert_vector(editor._target_cell(blocky_hit, false)).is_equal(Vector3i(4, 3, 7))
	assert_vector(editor._target_cell(blocky_hit, true)).is_equal(Vector3i(4, 2, 7))

	var smooth_hit := {
		"hit": true, "surface": "smooth",
		"position": Vector3i(1, 5, 2), "normal": Vector3i.ZERO,
	}
	assert_vector(editor._target_cell(smooth_hit, false)).is_equal(Vector3i(1, 5, 2))
	assert_vector(editor._target_cell(smooth_hit, true)).is_equal(Vector3i.MIN)

	var miss := {"hit": false, "surface": "", "position": Vector3i.ZERO, "normal": Vector3i.ZERO}
	assert_vector(editor._target_cell(miss, false)).is_equal(Vector3i.MIN)


func test_ghost_previews_brush_footprint() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor._set_mode(MapEditorClass.Mode.BLOCK)

	var hit := {
		"hit": true,
		"surface": "blocky",
		"position": Vector3i(4, 2, 7),
		"normal": Vector3i(0, 1, 0),
	}
	# Placement cell = position + normal = (4, 3, 7).
	editor._brush_diameter = 5
	editor._update_ghost(hit)
	assert_bool(editor._ghost.visible).is_true()
	assert_vector(editor._ghost.scale).is_equal(Vector3(5, 5, 5))
	assert_vector(editor._ghost.global_position).is_equal(Vector3(4.5, 3.5, 7.5))

	editor._brush_diameter = 4
	editor._update_ghost(hit)
	assert_vector(editor._ghost.scale).is_equal(Vector3(4, 4, 4))
	assert_vector(editor._ghost.global_position).is_equal(Vector3(5.0, 4.0, 8.0))


func test_map_editor_block_editing_init() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	assert_object(editor._block_library).is_not_null()
	assert_int(editor._selected_block_index).is_equal(6)
	assert_int(editor._brush_diameter).is_equal(1)
	assert_object(editor._ghost).is_not_null()
	assert_bool(editor._ghost.visible).is_false()


func test_map_editor_cycle_block() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	var initial_idx := editor._selected_block_index
	editor._cycle_block(1)
	assert_int(editor._selected_block_index).is_not_equal(initial_idx)


func test_editor_hud_terrain_info() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	hud.set_mode(MapEditorClass.Mode.TERRAIN)
	assert_bool(hud._terrain_info_panel.visible).is_true()
	assert_bool(hud._block_info_panel.visible).is_false()

	hud.set_terrain_info("ground", 3.0)
	assert_str(hud._terrain_material_label.text).contains("Ground")
	assert_str(hud._terrain_radius_label.text).contains("3.0 m")

	hud.set_terrain_available(false)
	assert_bool(hud._terrain_warning_label.visible).is_true()

	hud.set_terrain_available(true)
	assert_bool(hud._terrain_warning_label.visible).is_false()

	hud.set_mode(MapEditorClass.Mode.NAVIGATE)
	assert_bool(hud._terrain_info_panel.visible).is_false()


func test_ghost_previews_terrain_sculpt_sphere() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor._launcher.hide_launcher()
	editor._set_mode(MapEditorClass.Mode.TERRAIN)

	# Mock smooth grid so ghost is not suppressed
	var smooth := SmoothGrid.new()
	smooth.name = "SmoothGrid"
	var smooth_vt := VoxelTerrain.new()
	smooth_vt.name = "VoxelTerrain"
	smooth.add_child(smooth_vt)
	editor.add_child(smooth)
	editor._smooth_grid = smooth

	var hit := {
		"hit": true,
		"point": Vector3(4.5, 2.0, 7.5),
		"normal": Vector3(0, 1, 0),
	}
	editor._sculpt_radius = 2.5
	editor._update_ghost(hit)
	assert_bool(editor._ghost.visible).is_true()
	assert_bool(editor._ghost.mesh is SphereMesh).is_true()
	assert_vector(editor._ghost.scale).is_equal(Vector3(2.5, 2.5, 2.5))
	assert_vector(editor._ghost.global_position).is_equal(Vector3(4.5, 2.0, 7.5))


func test_map_editor_terrain_state_on_load() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")

	assert_object(editor._smooth_grid).is_not_null()
	assert_object(editor._smooth_vt).is_not_null()
	assert_str(editor._terrain_material_id).is_equal("ground")


func test_map_editor_terrain_brush_hotkeys() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor._launcher.hide_launcher()
	editor._set_mode(MapEditorClass.Mode.TERRAIN)
	editor._sculpt_radius = 2.0

	# Press ']' to increase radius
	var key_event_up := InputEventKey.new()
	key_event_up.pressed = true
	key_event_up.keycode = KEY_BRACKETRIGHT
	editor._input(key_event_up)
	assert_float(editor._sculpt_radius).is_equal_approx(2.5, 0.001)

	# Press '[' to decrease radius
	var key_event_down := InputEventKey.new()
	key_event_down.pressed = true
	key_event_down.keycode = KEY_BRACKETLEFT
	editor._input(key_event_down)
	assert_float(editor._sculpt_radius).is_equal_approx(2.0, 0.001)
