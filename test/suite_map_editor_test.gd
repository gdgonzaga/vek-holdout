class_name SuiteMapEditorTest
extends GdUnitTestSuite

const MapEditorClass = preload("res://tools/map_editor/map_editor.gd")
const EditorHUDClass = preload("res://tools/map_editor/editor_hud.gd")
const EditorLauncherClass = preload("res://tools/map_editor/editor_launcher.gd")
const EditorGridOverlayClass = preload("res://tools/map_editor/editor_grid_overlay.gd")
const EditorPalettePanelClass = preload("res://tools/map_editor/editor_palette_panel.gd")


func test_editor_hud_modes_and_info() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	hud.set_mode(MapEditorClass.Mode.NAVIGATE)
	assert_str(hud._mode_label.text).contains("NAVIGATE")

	hud.set_mode(MapEditorClass.Mode.BLOCK)
	assert_str(hud._mode_label.text).contains("BLOCK")

	hud.set_mode(MapEditorClass.Mode.TERRAIN)
	assert_str(hud._mode_label.text).contains("TERRAIN")

	hud.set_mode(MapEditorClass.Mode.FURNITURE)
	assert_str(hud._mode_label.text).contains("FURNITURE")

	hud.set_mode(MapEditorClass.Mode.SPAWN)
	assert_str(hud._mode_label.text).contains("SPAWN")

	hud.set_map_info("test_map", false)
	assert_str(hud._map_info_label.text).is_equal("Map: test_map")

	hud.set_map_info("test_map", true)
	assert_str(hud._map_info_label.text).is_equal("Map: test_map *")


func test_editor_launcher_population_and_signals() -> void:
	var launcher: EditorLauncher = auto_free(EditorLauncherClass.new())
	add_child(launcher)

	var map_def := MapDef.new()
	map_def.id = "base"
	map_def.display_name = "Base Camp"
	map_def.description = "Starting outpost"
	map_def.map_type = MapDef.MapType.BASE
	map_def.scene_path = "res://data/maps/base/map.tscn"

	launcher.setup([map_def])
	assert_int(launcher._maps_container.get_child_count()).is_equal(1)
	var row: HBoxContainer = launcher._maps_container.get_child(0) as HBoxContainer
	var btn: Button = row.get_child(0) as Button
	assert_str(btn.text).contains("Base Camp")


func test_map_editor_scan_maps() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	var maps := editor._scan_maps()

	assert_bool(maps.is_empty()).is_false()
	var base_found := false
	for m in maps:
		if m.id == "base":
			base_found = true
			break
	assert_bool(base_found).is_true()


func test_map_editor_terrain_gen_injection() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	var map := Node3D.new()
	var smooth := SmoothGrid.new()
	smooth.name = "SmoothGrid"
	map.add_child(smooth)

	var def := MapDef.new()
	var terrain_gen := TerrainGenDef.new()
	def.terrain_gen = terrain_gen

	editor._inject_terrain_gen(map, def)
	assert_object(smooth.terrain_gen).is_equal(terrain_gen)
	map.free()


func test_map_editor_attach_streams() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	var root := Node3D.new()

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

	editor._attach_streams(root, "base")

	assert_bool(blocky_terrain.stream is VoxelStreamSQLite).is_true()
	assert_str((blocky_terrain.stream as VoxelStreamSQLite).database_path).is_equal("res://data/maps/base/map.sqlite")

	assert_bool(smooth_terrain.stream is VoxelStreamSQLite).is_true()
	assert_str((smooth_terrain.stream as VoxelStreamSQLite).database_path).is_equal("res://data/maps/base/terrain.sqlite")
	root.free()


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

	# Simulate mouse look update
	var motion_relative := Vector2(10.0, 5.0)
	editor._cam_yaw -= motion_relative.x * MapEditorClass.MOUSE_SENSITIVITY
	editor._cam_pitch -= motion_relative.y * MapEditorClass.MOUSE_SENSITIVITY
	editor._apply_camera_rotation()

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


func test_editor_hud_furniture_and_spawn_info() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	hud.set_mode(MapEditorClass.Mode.FURNITURE)
	assert_bool(hud._furniture_info_panel.visible).is_true()
	assert_bool(hud._spawn_info_panel.visible).is_false()
	assert_bool(hud._block_info_panel.visible).is_false()
	assert_bool(hud._terrain_info_panel.visible).is_false()

	hud.set_furniture_info("Shelf1", 1)
	assert_str(hud._furniture_label.text).contains("Shelf1")
	assert_str(hud._yaw_label.text).contains("90°")

	hud.set_furniture_info("Shelf1", 2)
	assert_str(hud._yaw_label.text).contains("180°")

	hud.set_mode(MapEditorClass.Mode.SPAWN)
	assert_bool(hud._spawn_info_panel.visible).is_true()
	assert_bool(hud._furniture_info_panel.visible).is_false()
	assert_str(hud._spawn_hint_label.text).contains("Player Spawn")

	hud.set_mode(MapEditorClass.Mode.NAVIGATE)
	assert_bool(hud._furniture_info_panel.visible).is_false()
	assert_bool(hud._spawn_info_panel.visible).is_false()


func test_editor_hud_furniture_palette_population_and_filter() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	var def1 := FurnitureDef.new()
	def1.id = "bench_wood"
	def1.display_name = "Wooden Bench"
	def1.dimensions = Vector3i(2, 1, 1)

	var def2 := FurnitureDef.new()
	def2.id = "shelf_metal"
	def2.display_name = "Metal Shelf"
	def2.dimensions = Vector3i(1, 2, 1)

	var def3 := FurnitureDef.new()
	def3.id = "storage_box"
	def3.display_name = "Storage Box"
	def3.dimensions = Vector3i(1, 1, 1)

	var defs: Array[FurnitureDef] = [def1, def2, def3]
	hud.populate_furniture_list(defs, 0)

	assert_int(hud._furniture_item_list.item_count).is_equal(3)
	assert_str(hud._furniture_count_label.text).is_equal("(3/3)")
	assert_int(hud._furniture_item_list.get_selected_items()[0]).is_equal(0)

	# Filter by "shelf"
	hud._on_furniture_search_changed("shelf")
	assert_int(hud._furniture_item_list.item_count).is_equal(1)
	assert_str(hud._furniture_count_label.text).is_equal("(1/3)")
	assert_str(hud._furniture_item_list.get_item_text(0)).contains("Metal Shelf")

	# Filter by ID "storage"
	hud._on_furniture_search_changed("storage")
	assert_int(hud._furniture_item_list.item_count).is_equal(1)
	assert_str(hud._furniture_item_list.get_item_text(0)).contains("Storage Box")

	# Clear filter
	hud._on_furniture_search_changed("")
	assert_int(hud._furniture_item_list.item_count).is_equal(3)


func test_editor_hud_furniture_palette_selection_and_signals() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	var def1 := FurnitureDef.new()
	def1.id = "item1"
	def1.display_name = "Item 1"

	var def2 := FurnitureDef.new()
	def2.id = "item2"
	def2.display_name = "Item 2"

	hud.populate_furniture_list([def1, def2], 0)

	var selected_indices: Array[int] = []
	hud.furniture_selected.connect(func(idx: int) -> void:
		selected_indices.append(idx)
	)

	# Select second item in list
	hud._on_furniture_item_selected(1)
	assert_int(selected_indices.size()).is_equal(1)
	assert_int(selected_indices[0]).is_equal(1)

	# Programmatic selection
	hud.select_furniture_by_index(0)
	assert_int(hud._selected_global_idx).is_equal(0)
	assert_int(hud._furniture_item_list.get_selected_items()[0]).is_equal(0)


func test_map_editor_furniture_defs_loaded() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	assert_bool(editor._furniture_defs.is_empty()).is_false()
	assert_int(editor._selected_furniture_idx).is_equal(0)
	assert_int(editor._yaw).is_equal(0)
	assert_object(editor._furniture_auth).is_not_null()


func test_map_editor_furniture_cycle_and_rotate() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor._launcher.hide_launcher()
	editor._set_mode(MapEditorClass.Mode.FURNITURE)

	var initial_idx := editor._selected_furniture_idx
	var count := editor._furniture_defs.size()

	# Tab cycles furniture
	var tab_event := InputEventKey.new()
	tab_event.pressed = true
	tab_event.keycode = KEY_TAB
	editor._input(tab_event)
	assert_int(editor._selected_furniture_idx).is_equal((initial_idx + 1) % count)

	# Shift+Tab cycles backward
	var shift_tab_event := InputEventKey.new()
	shift_tab_event.pressed = true
	shift_tab_event.shift_pressed = true
	shift_tab_event.keycode = KEY_TAB
	editor._input(shift_tab_event)
	assert_int(editor._selected_furniture_idx).is_equal(initial_idx)

	# R rotates furniture
	var r_event := InputEventKey.new()
	r_event.pressed = true
	r_event.keycode = KEY_R
	editor._input(r_event)
	assert_int(editor._yaw).is_equal(1)

	editor._input(r_event)
	assert_int(editor._yaw).is_equal(2)


func test_map_editor_furniture_cycle_filtered() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor._launcher.hide_launcher()
	editor._set_mode(MapEditorClass.Mode.FURNITURE)

	# Mock two specific defs
	var d1 := FurnitureDef.new()
	d1.id = "target_alpha"
	d1.display_name = "Target Alpha"
	var d2 := FurnitureDef.new()
	d2.id = "other_item"
	d2.display_name = "Other Item"
	var d3 := FurnitureDef.new()
	d3.id = "target_beta"
	d3.display_name = "Target Beta"

	editor._furniture_defs = [d1, d2, d3]
	editor._hud.populate_furniture_list(editor._furniture_defs, 0)

	# Filter by "target"
	editor._hud._on_furniture_search_changed("target")
	assert_int(editor._hud.get_filtered_furniture_indices().size()).is_equal(2)
	assert_int(editor._selected_furniture_idx).is_equal(0)

	# Tab cycles to next filtered item (index 2 = target_beta)
	editor._cycle_furniture(1)
	assert_int(editor._selected_furniture_idx).is_equal(2)

	# Tab cycles back to first filtered item (index 0 = target_alpha)
	editor._cycle_furniture(1)
	assert_int(editor._selected_furniture_idx).is_equal(0)


func test_map_editor_furniture_place_and_remove() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")
	editor._set_mode(MapEditorClass.Mode.FURNITURE)

	var hit := {
		"hit": true,
		"surface": "blocky",
		"position": Vector3i(10, 0, 10),
		"normal": Vector3i(0, 1, 0),
	}

	var spawns: Node3D = editor._map_root.find_child("SpawnPoints") as Node3D
	assert_object(spawns).is_not_null()
	var initial_count := spawns.get_child_count()

	# Place furniture
	editor._do_furniture_place(hit)
	assert_bool(editor._dirty).is_true()
	assert_int(spawns.get_child_count()).is_equal(initial_count + 1)

	var placed_marker: Marker3D = spawns.get_child(spawns.get_child_count() - 1) as Marker3D
	assert_object(placed_marker).is_not_null()
	assert_bool(placed_marker.name.begins_with("Furniture_")).is_true()

	# Remove furniture
	editor._do_furniture_remove(hit)
	var exists := is_instance_valid(placed_marker) and not placed_marker.is_queued_for_deletion()
	assert_bool(exists).is_false()


func test_map_editor_spawn_markers_cache_and_place() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")
	editor._set_mode(MapEditorClass.Mode.SPAWN)

	assert_object(editor._spawn_markers.get("player")).is_not_null()
	var player_marker: Marker3D = editor._spawn_markers["player"]
	assert_object(player_marker.get_node_or_null("SpawnVisualizer")).is_not_null()

	# Place new player spawn position
	var hit_player := {
		"hit": true,
		"surface": "smooth",
		"smooth_point": Vector3(15.0, 3.5, 12.0),
		"position": Vector3i(15, 3, 12),
		"normal": Vector3i.ZERO,
	}
	editor._do_spawn_place("player", hit_player)
	assert_vector(player_marker.global_position).is_equal(Vector3(15.0, 3.5, 12.0))
	assert_vector(editor._map_def.player_spawn).is_equal(Vector3(15.0, 3.5, 12.0))

	# Place colonist spawn
	var hit_colonist := {
		"hit": true,
		"surface": "blocky",
		"position": Vector3i(5, 1, 5),
		"normal": Vector3i(0, 1, 0),
	}
	var initial_colonists_count: int = editor._spawn_markers.get("colonists", []).size()
	editor._do_spawn_place("colonist", hit_colonist)
	var colonists: Array = editor._spawn_markers.get("colonists", [])
	assert_int(colonists.size()).is_equal(initial_colonists_count + 1)
	var col_marker: Marker3D = colonists[0]
	assert_str(col_marker.name).contains("ColonistSpawn")
	assert_object(col_marker.get_node_or_null("SpawnVisualizer")).is_not_null()


func test_ghost_previews_furniture_and_spawn() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")

	var hit := {
		"hit": true,
		"surface": "blocky",
		"position": Vector3i(4, 0, 4),
		"normal": Vector3i(0, 1, 0),
	}

	# Test furniture ghost
	editor._set_mode(MapEditorClass.Mode.FURNITURE)
	editor._update_ghost(hit)
	assert_bool(editor._ghost.visible).is_true()
	var def := editor._furniture_defs[editor._selected_furniture_idx]
	assert_object(editor._ghost.mesh).is_equal(def.mesh)

	# Test spawn ghost
	editor._set_mode(MapEditorClass.Mode.SPAWN)
	editor._update_ghost(hit)
	assert_bool(editor._ghost.visible).is_true()
	assert_bool(editor._ghost.mesh is CapsuleMesh).is_true()


func test_map_editor_save_scene_packs_markers() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")

	var spawns: Node3D = editor._map_root.find_child("SpawnPoints") as Node3D
	var player_marker: Marker3D = spawns.find_child("PlayerSpawn") as Marker3D
	player_marker.global_position = Vector3(42.0, 10.0, 24.0)

	var hit := {
		"hit": true,
		"surface": "blocky",
		"position": Vector3i(20, 0, 20),
		"normal": Vector3i(0, 1, 0),
	}
	editor._set_mode(MapEditorClass.Mode.FURNITURE)
	editor._do_furniture_place(hit)

	var packed := PackedScene.new()
	var err := packed.pack(editor._map_root)
	assert_int(err).is_equal(OK)

	var inst := packed.instantiate()
	var inst_spawns: Node3D = inst.find_child("SpawnPoints") as Node3D
	assert_object(inst_spawns).is_not_null()
	var inst_player: Marker3D = inst_spawns.find_child("PlayerSpawn") as Marker3D
	assert_object(inst_player).is_not_null()
	assert_vector(inst_player.position).is_equal(Vector3(42.0, 10.0, 24.0))

	var found_furn := false
	for child in inst_spawns.get_children():
		if child is Marker3D and child.name.begins_with("Furniture_"):
			if child.get_meta("anchor", Vector3i.ZERO) == Vector3i(20, 1, 20):
				found_furn = true
				break
	assert_bool(found_furn).is_true()
	inst.free()


func test_map_editor_escape_shows_confirmation_when_mouse_free() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")

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


func test_map_editor_exit_confirmation_cancel_keeps_map_loaded() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	editor._request_exit()
	assert_bool(editor._exit_dialog.visible).is_true()

	editor._exit_dialog.hide()
	assert_object(editor._map_root).is_not_null()


func test_map_editor_exit_confirmation_confirm_unloads_map() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	editor._request_exit()
	assert_bool(editor._exit_dialog.visible).is_true()

	editor._exit_dialog.confirmed.emit()
	assert_object(editor._map_root).is_null()
	assert_bool(editor._launcher.visible).is_true()


func test_editor_hud_save_button_emits_signal() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	assert_object(hud._save_button).is_not_null()
	assert_str(hud._save_button.text).is_equal("Save")

	var emitted := [false]
	hud.save_requested.connect(func() -> void:
		emitted[0] = true
	)

	hud._save_button.pressed.emit()
	assert_bool(emitted[0]).is_true()


func test_map_editor_save_button_triggers_save_map() -> void:
	_remove_test_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	# Throwaway map: save_map() repacks the scene and rewrites map_def.tres —
	# never point that at committed content (base/dev).
	editor.create_new_map(_heightmap_payload(TEST_HEIGHTMAP_MAP))

	editor._dirty = true
	editor._hud.set_map_info(TEST_HEIGHTMAP_MAP, true)
	assert_str(editor._hud._map_info_label.text).contains("*")

	editor._hud._save_button.pressed.emit()
	assert_bool(editor._dirty).is_false()
	assert_bool(editor._hud._map_info_label.text.contains("*")).is_false()
	await _dispose_test_editor(editor)


func test_editor_grid_overlay_create_and_toggle() -> void:
	var mesh_inst: MeshInstance3D = auto_free(EditorGridOverlayClass.create(50.0, 2.0))
	assert_object(mesh_inst).is_not_null()
	assert_bool(mesh_inst.mesh is ImmediateMesh).is_true()

	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	assert_object(editor._grid_overlay).is_not_null()
	assert_bool(editor._grid_overlay.visible).is_false()

	# Toggle method
	editor._launcher.hide_launcher()
	editor._toggle_grid()
	assert_bool(editor._grid_overlay.visible).is_true()
	editor._launcher.hide_launcher()
	editor._toggle_grid()
	assert_bool(editor._grid_overlay.visible).is_false()

	# Hotkey G
	var g_event := InputEventKey.new()
	g_event.pressed = true
	g_event.keycode = KEY_G
	editor._input(g_event)
	assert_bool(editor._grid_overlay.visible).is_true()


func test_map_editor_coordinate_readout() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	assert_object(hud._coord_label).is_not_null()
	assert_str(hud._coord_label.text).is_empty()

	hud.set_coordinates(Vector3(12.34, 5.67, -8.91))
	assert_str(hud._coord_label.text).contains("X: 12.3")
	assert_str(hud._coord_label.text).contains("Y: 5.7")
	assert_str(hud._coord_label.text).contains("Z: -8.9")

	hud.clear_coordinates()
	assert_str(hud._coord_label.text).is_empty()


func test_map_editor_metadata_editing_and_save() -> void:
	_remove_test_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	# Throwaway map: this test SAVES, which rewrites map_def.tres — pointing it
	# at base used to dirty committed content on every suite run.
	editor.create_new_map(_heightmap_payload(TEST_HEIGHTMAP_MAP))

	assert_object(editor._hud._metadata_panel).is_not_null()
	assert_bool(editor._hud._metadata_panel.visible).is_false()

	# Toggle metadata panel
	editor._hud.toggle_metadata_panel()
	assert_bool(editor._hud._metadata_panel.visible).is_true()

	# Edit metadata fields
	editor._hud._meta_display_name_input.text = "Custom Base Title"
	editor._hud._meta_desc_input.text = "Custom description for testing"
	editor._hud._meta_type_option.selected = 1 # POI
	editor._hud._meta_difficulty_spin.value = 4

	var edits := editor._hud.get_metadata_edits()
	assert_str(edits.get("display_name", "")).is_equal("Custom Base Title")
	assert_str(edits.get("description", "")).is_equal("Custom description for testing")
	assert_int(edits.get("map_type", -1)).is_equal(1)
	assert_int(edits.get("difficulty", -1)).is_equal(4)

	# Save map syncs metadata into MapDef
	editor.save_map()
	assert_str(editor._map_def.display_name).is_equal("Custom Base Title")
	assert_str(editor._map_def.description).is_equal("Custom description for testing")
	assert_int(editor._map_def.map_type).is_equal(1)
	assert_int(editor._map_def.difficulty).is_equal(4)
	await _dispose_test_editor(editor)


func test_map_editor_block_undo() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")

	var entry: Dictionary = {
		"type": "block",
		"ops": [
			{"pos": Vector3i(0, 0, 0), "old_value": 3}
		]
	}
	editor._push_undo(entry)
	assert_int(editor._undo_stack.size()).is_equal(1)

	editor._undo_last()
	assert_int(editor._undo_stack.size()).is_equal(0)
	assert_bool(editor._dirty).is_true()


func test_map_editor_undo_stack_max_depth() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	for i in range(60):
		editor._push_undo({"type": "block", "ops": [{"pos": Vector3i(i, 0, 0), "old_value": i}]})

	assert_int(editor._undo_stack.size()).is_equal(MapEditorClass.MAX_UNDO_DEPTH)
	var first_entry: Dictionary = editor._undo_stack[0]
	assert_int(first_entry["ops"][0]["old_value"]).is_equal(10)


func test_map_editor_terrain_undo() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")

	var hit := {
		"hit": true,
		"point": Vector3(10.0, 0.0, 10.0),
		"normal": Vector3.UP,
	}

	editor._do_terrain_add(hit)
	assert_int(editor._undo_stack.size()).is_equal(1)
	assert_str(editor._undo_stack[0].get("type", "")).is_equal("terrain")
	assert_bool(editor._undo_stack[0].get("was_add", false)).is_true()

	editor._undo_last()
	assert_int(editor._undo_stack.size()).is_equal(0)
	assert_bool(editor._dirty).is_true()


func test_map_editor_ctrl_z_undo_hotkey() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")

	var hit := {
		"hit": true,
		"point": Vector3(5.0, 0.0, 5.0),
		"normal": Vector3.UP,
	}
	editor._do_terrain_carve(hit)
	assert_int(editor._undo_stack.size()).is_equal(1)

	var ctrl_z := InputEventKey.new()
	ctrl_z.pressed = true
	ctrl_z.keycode = KEY_Z
	ctrl_z.ctrl_pressed = true
	editor._input(ctrl_z)

	assert_int(editor._undo_stack.size()).is_equal(0)


func test_editor_palette_panel_filtering_and_selection() -> void:
	var panel: EditorPalettePanel = auto_free(EditorPalettePanelClass.new())
	panel.setup("TEST PALETTE", "Search...", Color.WHITE)

	var item1 := EditorPalettePanelClass.Item.new()
	item1.index = 1
	item1.id = "wood_block"
	item1.display_name = "Wood Block"
	item1.label = "Wood Block [#1]"

	var item2 := EditorPalettePanelClass.Item.new()
	item2.index = 2
	item2.id = "stone_block"
	item2.display_name = "Stone Block"
	item2.label = "Stone Block [#2]"

	var item3 := EditorPalettePanelClass.Item.new()
	item3.index = 3
	item3.id = "metal_plate"
	item3.display_name = "Metal Plate"
	item3.label = "Metal Plate [#3]"

	panel.populate([item1, item2, item3], 2)
	assert_int(panel._item_list.item_count).is_equal(3)
	assert_str(panel._count_label.text).is_equal("(3/3)")
	assert_int(panel._item_list.get_selected_items()[0]).is_equal(1) # item2 is selected

	# Filter by display_name
	panel._on_search_changed("metal")
	assert_int(panel._item_list.item_count).is_equal(1)
	assert_str(panel._count_label.text).is_equal("(1/3)")
	assert_str(panel._item_list.get_item_text(0)).contains("Metal Plate")

	# Filter by id substring
	panel._on_search_changed("wood_block")
	assert_int(panel._item_list.item_count).is_equal(1)
	assert_str(panel._item_list.get_item_text(0)).contains("Wood Block")

	# Clear search restores list
	panel._on_search_changed("")
	assert_int(panel._item_list.item_count).is_equal(3)


func test_editor_hud_block_palette_population_and_filter() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	var b1 := BlockDef.new()
	b1.id = "wood"
	b1.display_name = "Wood Block"
	b1.hp = 50

	var b2 := BlockDef.new()
	b2.id = "stone"
	b2.display_name = "Stone Block"
	b2.hp = 300

	var b3 := BlockDef.new()
	b3.id = "metal"
	b3.display_name = "Metal Block"
	b3.hp = 600

	var dict := {
		2: b1,
		5: b2,
		8: b3,
	}

	hud.populate_block_list(dict, 5)
	assert_int(hud._block_palette._item_list.item_count).is_equal(3)
	assert_str(hud._block_palette._count_label.text).is_equal("(3/3)")

	# Filter for stone
	hud._block_palette._on_search_changed("stone")
	assert_int(hud._block_palette._item_list.item_count).is_equal(1)
	assert_str(hud._block_palette._count_label.text).is_equal("(1/3)")
	assert_str(hud._block_palette._item_list.get_item_text(0)).contains("Stone Block")

	# Filter for metal
	hud._block_palette._on_search_changed("metal")
	assert_int(hud._block_palette._item_list.item_count).is_equal(1)
	assert_str(hud._block_palette._item_list.get_item_text(0)).contains("Metal Block")

	# Reset
	hud._block_palette._on_search_changed("")
	assert_int(hud._block_palette._item_list.item_count).is_equal(3)


func test_editor_hud_block_palette_selection_and_signals() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	var b1 := BlockDef.new()
	b1.id = "wood"
	b1.display_name = "Wood Block"

	var b2 := BlockDef.new()
	b2.id = "stone"
	b2.display_name = "Stone Block"

	hud.populate_block_list({1: b1, 6: b2}, 1)

	var selected_val := [-1]
	hud.block_selected.connect(func(idx: int) -> void:
		selected_val[0] = idx
	)

	# Click second item in list (index 6)
	hud._block_palette._on_item_selected(1)
	assert_int(selected_val[0]).is_equal(6)

	# Select by index method
	hud.select_block_by_index(1)
	assert_int(hud._block_palette._item_list.get_selected_items()[0]).is_equal(0)


func test_map_editor_block_cycle_filtered() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")

	var b1 := BlockDef.new()
	b1.id = "wood_oak"
	b1.display_name = "Oak Wood"

	var b2 := BlockDef.new()
	b2.id = "stone_granite"
	b2.display_name = "Granite Stone"

	var b3 := BlockDef.new()
	b3.id = "wood_pine"
	b3.display_name = "Pine Wood"

	var defs := {1: b1, 2: b2, 3: b3}
	editor._hud.populate_block_list(defs, 1)
	editor._selected_block_index = 1

	# Filter for "wood" -> matches b1 (idx 1) and b3 (idx 3)
	editor._hud._block_palette._on_search_changed("wood")
	assert_int(editor._hud.get_filtered_block_indices().size()).is_equal(2)
	assert_int(editor._selected_block_index).is_equal(1)

	# Cycle next -> should pick 3 (Pine Wood) skipping 2 (Granite Stone)
	editor._cycle_block(1)
	assert_int(editor._selected_block_index).is_equal(3)

	# Cycle next -> wraps back to 1 (Oak Wood)
	editor._cycle_block(1)
	assert_int(editor._selected_block_index).is_equal(1)


func test_map_editor_block_tab_key_cycling() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")

	editor._set_mode(MapEditorClass.Mode.BLOCK)
	var initial_idx := editor._selected_block_index
	var filtered_indices := editor._hud.get_filtered_block_indices()
	assert_bool(filtered_indices.size() > 1).is_true()

	var tab_event := InputEventKey.new()
	tab_event.pressed = true
	tab_event.keycode = KEY_TAB
	editor._input(tab_event)

	assert_int(editor._selected_block_index).is_not_equal(initial_idx)


func test_editor_hud_overlay_mouse_filters() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	assert_int(hud._crosshair.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int((hud._crosshair.get_node("HLine") as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int((hud._crosshair.get_node("VLine") as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int((hud._crosshair.get_node("CoordLabel") as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(hud._mode_badge.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(hud._mode_label.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(hud._terrain_info_panel.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int((hud._terrain_info_panel.get_node("TerrainInfoVBox") as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(hud._spawn_info_panel.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int((hud._spawn_info_panel.get_node("SpawnInfoVBox") as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_map_editor_mouse_lmb_input_recaptures_when_visible() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_VISIBLE)

	var lmb := InputEventMouseButton.new()
	lmb.pressed = true
	lmb.button_index = MOUSE_BUTTON_LEFT
	editor._input(lmb)

	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_CAPTURED)


func test_map_editor_lmb_terrain_input_dispatches_sculpt() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")
	editor._set_mode(MapEditorClass.Mode.TERRAIN)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var hit := {
		"hit": true,
		"point": Vector3(10.0, 0.0, 10.0),
		"normal": Vector3.UP,
	}
	editor._do_terrain_add(hit)
	assert_int(editor._undo_stack.size()).is_equal(1)
	assert_str(editor._undo_stack[-1].get("type", "")).is_equal("terrain")
	assert_bool(editor._undo_stack[-1].get("was_add", false)).is_true()

	editor._do_terrain_carve(hit)
	assert_int(editor._undo_stack.size()).is_equal(2)
	assert_bool(editor._undo_stack[-1].get("was_add", true)).is_false()


func test_map_editor_lmb_furniture_input_dispatches_place_and_remove() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")
	editor._set_mode(MapEditorClass.Mode.FURNITURE)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var hit := {
		"hit": true,
		"surface": "blocky",
		"position": Vector3i(12, 0, 12),
		"normal": Vector3i(0, 1, 0),
	}

	editor._do_furniture_place(hit)
	assert_bool(editor._dirty).is_true()

	editor._do_furniture_remove(hit)
	assert_bool(editor._dirty).is_true()


func test_map_editor_lmb_spawn_input_dispatches_spawns() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.load_map("base")
	editor._set_mode(MapEditorClass.Mode.SPAWN)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var hit_player := {
		"hit": true,
		"surface": "smooth",
		"smooth_point": Vector3(20.0, 1.0, 20.0),
		"position": Vector3i(20, 1, 20),
		"normal": Vector3i.ZERO,
	}
	editor._do_spawn_place("player", hit_player)
	assert_vector(editor._map_def.player_spawn).is_equal(Vector3(20.0, 1.0, 20.0))

	var hit_col := {
		"hit": true,
		"surface": "blocky",
		"position": Vector3i(8, 0, 8),
		"normal": Vector3i(0, 1, 0),
	}
	editor._do_spawn_place("colonist", hit_col)
	var colonists: Array = editor._spawn_markers.get("colonists", [])
	assert_bool(colonists.size() > 0).is_true()


# --- Heightmap terrain (phase 2: launcher setup + terrain drawer) ---------------

## Throwaway map id for creation tests; removed before AND after each test so a
## crashed run never leaves committed-looking content behind.
const TEST_HEIGHTMAP_MAP := "test_heightmap_map"


func _remove_test_map(map_id: String) -> void:
	var dir := DirAccess.open("res://data/maps/" + map_id)
	if dir == null:
		return
	for entry in dir.get_files():
		dir.remove(entry)
	DirAccess.open("res://data/maps/").remove(map_id)


## Unload + drain in-flight streaming tasks BEFORE deleting the throwaway
## folder — without the frames, async block-load workers hit a deleted sqlite
## file and spam errors into the log.
func _dispose_test_editor(editor: MapEditor) -> void:
	editor.unload_map()
	await get_tree().process_frame
	await get_tree().process_frame
	_remove_test_map(TEST_HEIGHTMAP_MAP)


func _heightmap_payload(map_id: String) -> Dictionary:
	var image := Image.create(32, 32, false, Image.FORMAT_RGB8)
	image.fill(Color(0.75, 0.75, 0.75))
	return {
		"map_id": map_id,
		"map_type": MapDef.MapType.POI,
		"terrain_mode": EditorLauncherClass.TerrainMode.HEIGHTMAP,
		"noise_def_path": "",
		"image": image,
		"height_start": -7.0,
		"height_range": 21.0,
	}


## HEIGHTMAP mode refuses to create without a picked image, and a picked image
## rides the payload with the span fields.
func test_editor_launcher_heightmap_payload_validation() -> void:
	var launcher: EditorLauncher = auto_free(EditorLauncherClass.new())
	add_child(launcher)
	var received: Array = []
	launcher.new_map_requested.connect(func(payload: Dictionary) -> void:
		received.append(payload)
	)

	launcher._new_name_input.text = TEST_HEIGHTMAP_MAP
	launcher._terrain_mode_select.selected = EditorLauncherClass.TerrainMode.HEIGHTMAP
	launcher._on_terrain_mode_selected(EditorLauncherClass.TerrainMode.HEIGHTMAP)
	assert_bool(launcher._heightmap_box.visible).is_true()
	assert_bool(launcher._noise_def_select.visible).is_false()

	launcher._on_create_pressed()
	assert_int(received.size()).is_zero()
	assert_bool(launcher._error_label.visible).is_true()

	var image := Image.create(16, 16, false, Image.FORMAT_L8)
	image.fill(Color(0.5, 0.5, 0.5))
	launcher._heightmap_image = image
	launcher._height_start_spin.value = -8.0
	launcher._height_range_spin.value = 24.0
	launcher._on_create_pressed()
	assert_int(received.size()).is_equal(1)
	var payload: Dictionary = received[0]
	assert_int(payload["terrain_mode"]).is_equal(EditorLauncherClass.TerrainMode.HEIGHTMAP)
	assert_object(payload["image"]).is_same(image)
	assert_float(payload["height_start"]).is_equal(-8.0)
	assert_float(payload["height_range"]).is_equal(24.0)


## The launcher's noise dropdown lists shared defs but excludes heightmap-driven
## ones (those are per-map content), with the default preselected.
func test_editor_launcher_noise_def_dropdown_excludes_heightmap_defs() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var select: OptionButton = editor._launcher._noise_def_select
	assert_int(select.item_count).is_greater(0)
	var has_default := false
	var has_heightmap_def := false
	for i in range(select.item_count):
		if select.get_item_text(i) == "ground_default":
			has_default = true
		if select.get_item_text(i) == "heightmap_valley":
			has_heightmap_def = true
	assert_bool(has_default).is_true()
	assert_bool(has_heightmap_def).is_false()
	assert_str(editor._launcher._selected_noise_def_path()).is_equal(
		"res://data/terrain/default_ground.tres"
	)


## load_heightmap_image: the committed example loads as L8; bad paths and
## too-small images are rejected.
func test_editor_launcher_load_heightmap_image() -> void:
	var image := EditorLauncherClass.load_heightmap_image("res://data/terrain/heightmap_valley.png")
	assert_object(image).is_not_null()
	assert_int(image.get_format()).is_equal(Image.FORMAT_L8)
	assert_vector(image.get_size()).is_equal(Vector2i(128, 128))

	assert_object(EditorLauncherClass.load_heightmap_image("res://data/terrain/does_not_exist.png")).is_null()

	var tiny_path := "res://.godot/tiny_heightmap_test.png"
	var tiny := Image.create(8, 8, false, Image.FORMAT_L8)
	tiny.fill(Color(0.5, 0.5, 0.5))
	tiny.save_png(tiny_path)
	assert_object(EditorLauncherClass.load_heightmap_image(tiny_path)).is_null()
	DirAccess.open("res://.godot").remove(tiny_path.get_file())


## Creating a heightmap map writes the per-map terrain_gen.tres (embedded L8
## texture, payload span), wires MapDef.terrain_gen at it, and the loaded map
## builds a VoxelGeneratorImage.
func test_map_editor_heightmap_creation_writes_per_map_def() -> void:
	_remove_test_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	editor.create_new_map(_heightmap_payload(TEST_HEIGHTMAP_MAP))

	var terrain_path := "res://data/maps/%s/terrain_gen.tres" % TEST_HEIGHTMAP_MAP
	assert_bool(ResourceLoader.exists(terrain_path)).is_true()
	var terrain_def := load(terrain_path) as TerrainGenDef
	assert_str(terrain_def.id).is_equal(TEST_HEIGHTMAP_MAP + "_terrain")
	assert_float(terrain_def.height_start).is_equal(-7.0)
	assert_float(terrain_def.height_range).is_equal(21.0)
	assert_object(terrain_def.heightmap).is_not_null()
	var embedded: Image = terrain_def.heightmap.get_image()
	assert_vector(embedded.get_size()).is_equal(Vector2i(32, 32))
	assert_int(embedded.get_format()).is_equal(Image.FORMAT_L8)

	assert_object(editor._map_def.terrain_gen).is_not_null()
	assert_str(editor._map_def.terrain_gen.id).is_equal(TEST_HEIGHTMAP_MAP + "_terrain")
	var generator = editor._map_root.get_smooth_grid().get_terrain().get("generator")
	assert_bool(generator is VoxelGeneratorImage).is_true()

	await _dispose_test_editor(editor)


## Drawer state mirrors the loaded def (mode, span, minimap source) for all
## three def shapes, pending images flip to heightmap mode, and the drawer is
## mutually exclusive with the metadata panel.
func test_editor_hud_terrain_drawer_state_reflects_def() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	var noise_def := TerrainGenDef.new()
	noise_def.id = "noise_def_test"
	hud.set_terrain_drawer_state(noise_def)
	assert_str(hud._terrain_mode_label.text).contains("Procedural (noise)")
	assert_bool(hud._terrain_heightmap_section.visible).is_false()
	assert_bool(hud._terrain_noise_section.visible).is_true()
	assert_str(hud._terrain_pick_button.text).contains("Convert")

	var hm_def := TerrainGenDef.new()
	hm_def.id = "hm_def_test"
	hm_def.height_start = -5.0
	hm_def.height_range = 11.0
	var img := Image.create(16, 16, false, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	hm_def.heightmap = ImageTexture.create_from_image(img)
	hud.set_terrain_drawer_state(hm_def)
	assert_str(hud._terrain_mode_label.text).contains("Heightmap")
	assert_bool(hud._terrain_heightmap_section.visible).is_true()
	assert_float(hud._terrain_start_spin.value).is_equal(-5.0)
	assert_float(hud._terrain_range_spin.value).is_equal(11.0)
	assert_object(hud._terrain_minimap.texture).is_not_null()

	hud.set_terrain_drawer_state(null)
	assert_str(hud._terrain_mode_label.text).contains("None")
	assert_bool(hud._terrain_remove_button.visible).is_false()
	assert_str(hud._terrain_pick_button.text).contains("Add Heightmap")

	hud.set_pending_heightmap_image(img)
	assert_bool(hud._terrain_heightmap_section.visible).is_true()
	assert_object(hud.get_terrain_drawer_edits().get("pending_image")).is_same(img)

	hud.toggle_terrain_drawer()
	assert_bool(hud.is_terrain_drawer_visible()).is_true()
	hud.toggle_metadata_panel()
	assert_bool(hud._metadata_panel.visible).is_true()
	assert_bool(hud.is_terrain_drawer_visible()).is_false()
	assert_bool(hud.is_terrain_drawer_focused()).is_false()


## Apply on a heightmap map persists span edits to the per-map def and reloads
## the map with them; the remove toggle strips terrain_gen entirely.
func test_map_editor_terrain_drawer_edits_apply_and_reload() -> void:
	_remove_test_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(_heightmap_payload(TEST_HEIGHTMAP_MAP))

	editor._hud.toggle_terrain_drawer()
	editor._hud._terrain_start_spin.value = -9.0
	editor._hud._terrain_range_spin.value = 30.0
	editor._on_terrain_apply()

	assert_float(editor._map_def.terrain_gen.height_start).is_equal(-9.0)
	assert_float(editor._map_def.terrain_gen.height_range).is_equal(30.0)
	assert_float(editor._hud._terrain_start_spin.value).is_equal(-9.0)
	var generator = editor._map_root.get_smooth_grid().get_terrain().get("generator")
	assert_bool(generator is VoxelGeneratorImage).is_true()

	editor._hud._on_terrain_remove_toggled()
	assert_str(editor._hud._terrain_remove_button.text).contains("Keep Terrain")
	editor._on_terrain_apply()
	assert_object(editor._map_def.terrain_gen).is_null()
	assert_str(editor._hud._terrain_mode_label.text).contains("None")

	await _dispose_test_editor(editor)
