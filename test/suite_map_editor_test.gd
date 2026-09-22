class_name SuiteMapEditorTest
extends GdUnitTestSuite

const MapEditorClass = preload("res://tools/map_editor/map_editor.gd")
const EditorHUDClass = preload("res://tools/map_editor/editor_hud.gd")
const EditorLauncherClass = preload("res://tools/map_editor/editor_launcher.gd")
const EditorGridOverlayClass = preload("res://tools/map_editor/editor_grid_overlay.gd")
const EditorPalettePanelClass = preload("res://tools/map_editor/editor_palette_panel.gd")
const Doubles = preload("res://test/helpers/doubles.gd")
const Sandbox = preload("res://test/helpers/map_editor_sandbox.gd")


## Sweeps crash leftovers once per suite run so a prior aborted run's throwaway
## maps never collide with this suite's own sandbox ids.
func before() -> void:
	Sandbox.sweep_stale()


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

	hud.set_mode(MapEditorClass.Mode.STRUCTURE)
	assert_str(hud._mode_label.text).contains("STRUCTURE")
	assert_bool(hud._structure_browser.visible).is_true()

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
	var maps := MapRepository.scan_maps()

	assert_bool(maps.is_empty()).is_false()
	for m in maps:
		assert_object(m).is_not_null()
		assert_str(m.id).is_not_empty()


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


func test_inject_terrain_gen_null_def_overrides_embedded_def() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var map_root := Node3D.new()
	var smooth := SmoothGrid.new()
	smooth.name = "SmoothGrid"
	smooth.terrain_gen = TerrainGenDef.new()
	map_root.add_child(smooth)
	var def := MapDef.new()
	def.terrain_gen = null

	editor._inject_terrain_gen(map_root, def)

	assert_object(smooth.terrain_gen).is_null()
	map_root.free()


func test_save_map_does_not_embed_injected_terrain_gen() -> void:
	var id := Sandbox.map_id("embed")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(id))
	assert_object(editor._map_root.get_smooth_grid().terrain_gen).is_not_null()

	editor.save_map()

	var packed := load(editor._map_scene_path) as PackedScene
	var instance := packed.instantiate()
	var smooth := instance.get_node_or_null("SmoothGrid") as SmoothGrid
	assert_object(smooth).is_not_null()
	assert_object(smooth.terrain_gen).is_null()
	instance.free()
	# The live grid keeps its def after saving.
	assert_object(editor._map_root.get_smooth_grid().terrain_gen).is_not_null()
	await Sandbox.dispose(get_tree(), editor, id)


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


func test_editor_hud_block_info() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	hud.set_mode(MapEditorClass.Mode.BLOCK)
	assert_bool(hud._block_palette.visible).is_true()

	hud.set_block_info("Planks", 5)
	assert_str(hud._block_palette.get_selected_text()).contains("Planks")
	assert_str(hud._brush_label.text).contains("5x5x5")

	hud.set_block_info("Wood", 1)
	assert_str(hud._brush_label.text).contains("1x1x1")

	hud.set_mode(MapEditorClass.Mode.NAVIGATE)
	assert_bool(hud._block_palette.visible).is_false()


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
	assert_bool(editor._ghost_view.mesh_instance.visible).is_true()
	assert_vector(editor._ghost_view.mesh_instance.scale).is_equal(Vector3(5, 5, 5))
	assert_vector(editor._ghost_view.mesh_instance.global_position).is_equal(Vector3(4.5, 3.5, 7.5))

	editor._brush_diameter = 4
	editor._update_ghost(hit)
	assert_vector(editor._ghost_view.mesh_instance.scale).is_equal(Vector3(4, 4, 4))
	assert_vector(editor._ghost_view.mesh_instance.global_position).is_equal(Vector3(5.0, 4.0, 8.0))


func test_map_editor_block_editing_init() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	assert_object(editor._block_library).is_not_null()
	var base := editor._block_library.get_base_indices()
	var expected_idx: int = base[0] if not base.is_empty() else 0
	assert_int(editor._selected_block_index).is_equal(expected_idx)
	assert_int(editor._brush_diameter).is_equal(1)
	assert_object(editor._ghost_view.mesh_instance).is_not_null()
	assert_bool(editor._ghost_view.mesh_instance.visible).is_false()


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
	assert_bool(hud._block_palette.visible).is_false()

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
	assert_bool(editor._ghost_view.mesh_instance.visible).is_true()
	assert_bool(editor._ghost_view.mesh_instance.mesh is SphereMesh).is_true()
	assert_vector(editor._ghost_view.mesh_instance.scale).is_equal(Vector3(2.5, 2.5, 2.5))
	assert_vector(editor._ghost_view.mesh_instance.global_position).is_equal(Vector3(4.5, 2.0, 7.5))
	# The drawn sphere must match the edited sphere: mesh radius times scale equals the brush radius.
	var sphere := editor._ghost_view.mesh_instance.mesh as SphereMesh
	assert_float(sphere.radius * editor._ghost_view.mesh_instance.scale.x).is_equal_approx(2.5, 0.001)
	assert_float(sphere.height * editor._ghost_view.mesh_instance.scale.y).is_equal_approx(5.0, 0.001)


func test_map_editor_terrain_state_on_load() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("terrain_state_on_load")
	# Smooth terrain needed: this test's whole point is that a live smooth grid exists after load.
	await Sandbox.create_and_load(get_tree(), editor, id, true)

	assert_object(editor._smooth_grid).is_not_null()
	await Sandbox.dispose(get_tree(), editor, id)


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


## M cycles BuildLibrary's terrain materials into _terrain_material_id (the
## Terrain-mode mirror of the block palette); an unknown current id snaps into
## range; the HUD display shows position feedback. BuildLibrary state is
## swapped and restored (autoloads persist across suites).
func test_map_editor_terrain_material_cycling() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor._launcher.hide_launcher()

	var extra: TerrainMaterialDef = auto_free(TerrainMaterialDef.new())
	extra.id = "rock_cycler"
	extra.display_name = "Rock Cycler"
	var saved_materials: Dictionary = BuildLibrary._materials_by_id.duplicate()
	# Hermetic two-material catalog — the real one now ships rock/iron/gold
	# defs whose scan order and count would make the cycle assertions brittle.
	BuildLibrary._materials_by_id = {"ground": saved_materials["ground"], "rock_cycler": extra}

	editor._terrain_material_id = "ground"
	editor._cycle_terrain_material(1)
	assert_str(editor._terrain_material_id).is_equal("rock_cycler")
	editor._cycle_terrain_material(1)
	assert_str(editor._terrain_material_id).is_equal("ground")
	assert_str(editor._terrain_material_display()).is_equal("ground (1/2)")
	editor._terrain_material_id = "bogus"
	editor._cycle_terrain_material(1)
	assert_str(editor._terrain_material_id).is_equal("ground")

	BuildLibrary._materials_by_id = saved_materials


func test_editor_hud_furniture_and_spawn_info() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	hud.set_mode(MapEditorClass.Mode.FURNITURE)
	assert_bool(hud._furniture_palette.visible).is_true()
	assert_bool(hud._spawn_info_panel.visible).is_false()
	assert_bool(hud._block_palette.visible).is_false()
	assert_bool(hud._terrain_info_panel.visible).is_false()

	hud.set_furniture_info("Shelf1", 1)
	assert_str(hud._furniture_palette.get_selected_text()).contains("Shelf1")
	assert_str(hud._yaw_label.text).contains("90°")

	hud.set_furniture_info("Shelf1", 2)
	assert_str(hud._yaw_label.text).contains("180°")

	hud.set_mode(MapEditorClass.Mode.SPAWN)
	assert_bool(hud._spawn_info_panel.visible).is_true()
	assert_bool(hud._furniture_palette.visible).is_false()
	assert_str(hud._spawn_hint_label.text).contains("Player Spawn")

	hud.set_mode(MapEditorClass.Mode.NAVIGATE)
	assert_bool(hud._furniture_palette.visible).is_false()
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

	assert_int(hud._furniture_palette.get_item_count()).is_equal(3)
	assert_str(hud._furniture_palette._count_label.text).is_equal("(3/3)")
	assert_int(hud._furniture_palette._item_list.get_selected_items()[0]).is_equal(0)

	# Filter by "shelf"
	hud._furniture_palette._on_search_changed("shelf")
	assert_int(hud._furniture_palette.get_item_count()).is_equal(1)
	assert_str(hud._furniture_palette._count_label.text).is_equal("(1/3)")
	assert_str(hud._furniture_palette._item_list.get_item_text(0)).contains("Metal Shelf")

	# Filter by ID "storage"
	hud._furniture_palette._on_search_changed("storage")
	assert_int(hud._furniture_palette.get_item_count()).is_equal(1)
	assert_str(hud._furniture_palette._item_list.get_item_text(0)).contains("Storage Box")

	# Clear filter
	hud._furniture_palette._on_search_changed("")
	assert_int(hud._furniture_palette.get_item_count()).is_equal(3)


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
	hud._furniture_palette._on_item_selected(1)
	assert_int(selected_indices.size()).is_equal(1)
	assert_int(selected_indices[0]).is_equal(1)

	# Programmatic selection
	hud.select_furniture_by_index(0)
	assert_int(hud._selected_global_idx).is_equal(0)
	assert_int(hud._furniture_palette._item_list.get_selected_items()[0]).is_equal(0)


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

	# Mouse wheel rotates furniture
	var wheel_event := InputEventMouseButton.new()
	wheel_event.pressed = true
	wheel_event.button_index = MOUSE_BUTTON_WHEEL_UP
	editor._input(wheel_event)
	assert_int(editor._yaw).is_equal(1)

	editor._input(wheel_event)
	assert_int(editor._yaw).is_equal(2)

	# R cycles rotation axis
	var r_event := InputEventKey.new()
	r_event.pressed = true
	r_event.keycode = KEY_R
	editor._input(r_event)
	assert_int(editor._active_rotation_axis).is_equal(1) # RotationAxis.X


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
	editor._hud._furniture_palette._on_search_changed("target")
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
	var id := Sandbox.map_id("furniture_place_and_remove")
	await Sandbox.create_and_load(get_tree(), editor, id, false)
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
	await Sandbox.dispose(get_tree(), editor, id)


func test_map_editor_spawn_markers_cache_and_place() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("spawn_markers_cache_and_place")
	await Sandbox.create_and_load(get_tree(), editor, id, false)
	editor._set_mode(MapEditorClass.Mode.SPAWN)

	assert_object(editor._spawns.player_marker()).is_not_null()
	var player_marker: Marker3D = editor._spawns.player_marker()
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
	var initial_colonists_count: int = editor._spawns.counts()["colonists"]
	editor._do_spawn_place("colonist", hit_colonist)
	var colonists: Array[Marker3D] = editor._spawns.colonist_markers()
	assert_int(colonists.size()).is_equal(initial_colonists_count + 1)
	var col_marker: Marker3D = colonists[0]
	assert_str(col_marker.name).contains("ColonistSpawn")
	assert_object(col_marker.get_node_or_null("SpawnVisualizer")).is_not_null()
	await Sandbox.dispose(get_tree(), editor, id)


func test_ghost_previews_furniture_and_spawn() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("ghost_previews_furniture_and_spawn")
	await Sandbox.create_and_load(get_tree(), editor, id, false)

	var hit := {
		"hit": true,
		"surface": "blocky",
		"position": Vector3i(4, 0, 4),
		"normal": Vector3i(0, 1, 0),
	}

	# Test furniture ghost
	editor._set_mode(MapEditorClass.Mode.FURNITURE)
	editor._update_ghost(hit)
	assert_bool(editor._ghost_view.mesh_instance.visible).is_true()
	var def := editor._furniture_defs[editor._selected_furniture_idx]
	assert_object(editor._ghost_view.mesh_instance.mesh).is_equal(def.mesh)

	# Test spawn ghost
	editor._set_mode(MapEditorClass.Mode.SPAWN)
	editor._update_ghost(hit)
	assert_bool(editor._ghost_view.mesh_instance.visible).is_true()
	assert_bool(editor._ghost_view.mesh_instance.mesh is CapsuleMesh).is_true()
	await Sandbox.dispose(get_tree(), editor, id)


func test_map_editor_save_scene_packs_markers() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("save_scene_packs_markers")
	await Sandbox.create_and_load(get_tree(), editor, id, false)

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
	editor._hud._meta_flora_spawns_spin.value = 5
	editor._hud._meta_flora_cap_spin.value = 40
	editor._hud._meta_flora_attempts_spin.value = 10

	var edits := editor._hud.get_metadata_edits()
	assert_str(edits.get("display_name", "")).is_equal("Custom Base Title")
	assert_str(edits.get("description", "")).is_equal("Custom description for testing")
	assert_int(edits.get("map_type", -1)).is_equal(1)
	assert_int(edits.get("difficulty", -1)).is_equal(4)
	assert_int(edits.get("flora_spawns_per_day", -1)).is_equal(5)
	assert_int(edits.get("flora_spawn_cap", -1)).is_equal(40)
	assert_int(edits.get("flora_max_spawn_attempts", -1)).is_equal(10)

	# Save map syncs metadata into MapDef
	editor.save_map()
	assert_str(editor._map_def.display_name).is_equal("Custom Base Title")
	assert_str(editor._map_def.description).is_equal("Custom description for testing")
	assert_int(editor._map_def.map_type).is_equal(1)
	assert_int(editor._map_def.difficulty).is_equal(4)
	assert_int(editor._map_def.flora_spawns_per_day).is_equal(5)
	assert_int(editor._map_def.flora_spawn_cap).is_equal(40)
	assert_int(editor._map_def.flora_max_spawn_attempts).is_equal(10)
	await _dispose_test_editor(editor)


func test_map_editor_block_undo() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("block_undo")
	await Sandbox.create_and_load(get_tree(), editor, id, false)

	var entry: Dictionary = {
		"type": "block",
		"ops": [
			{"pos": Vector3i(0, 0, 0), "old_value": 3}
		]
	}
	editor._history.push(entry)
	assert_int(editor._history.size()).is_equal(1)

	editor._undo_last()
	assert_int(editor._history.size()).is_equal(0)
	assert_bool(editor._dirty).is_true()
	await Sandbox.dispose(get_tree(), editor, id)


func test_map_editor_terrain_undo() -> void:
	var id := Sandbox.map_id("undo_terrain")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(id))
	var hit := {"hit": true, "point": Vector3(10.0, 0.0, 10.0), "normal": Vector3.UP}

	editor._do_terrain_add(hit)

	assert_int(editor._history.size()).is_equal(1)
	var entry: Dictionary = editor._history.entries[0]
	assert_str(entry.get("type", "")).is_equal("terrain")
	assert_bool(entry.has("snapshot")).is_true()
	# Restore, not invert: the entry no longer records add/carve intent.
	assert_bool(entry.has("was_add")).is_false()

	editor._undo_last()
	assert_int(editor._history.size()).is_equal(0)
	assert_bool(editor._dirty).is_true()
	await Sandbox.dispose(get_tree(), editor, id)


func test_terrain_snapshot_covers_the_brush_region() -> void:
	var id := Sandbox.map_id("undo_region")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(id))
	editor._sculpt_radius = 2.0
	var point := Vector3(4.0, 1.0, 4.0)

	var snapshot: Dictionary = editor._capture_brush_region(point, 2.0)

	# The brush box plus margin: the centre and both extremes are inside the captured set.
	var sdf: Dictionary = snapshot.get("sdf", {})
	assert_bool(sdf.has(Vector3i(4, 1, 4))).is_true()
	assert_bool(sdf.has(Vector3i(2 - SmoothGrid.EDIT_SNAPSHOT_MARGIN, 1 - 2 - SmoothGrid.EDIT_SNAPSHOT_MARGIN, 4))).is_true()
	assert_bool(sdf.has(Vector3i(6 + SmoothGrid.EDIT_SNAPSHOT_MARGIN, 3 + SmoothGrid.EDIT_SNAPSHOT_MARGIN, 4))).is_true()
	await Sandbox.dispose(get_tree(), editor, id)


func test_map_editor_ctrl_z_undo_hotkey() -> void:
	var id := Sandbox.map_id("ctrl_z")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(id))

	var hit := {
		"hit": true,
		"point": Vector3(5.0, 0.0, 5.0),
		"normal": Vector3.UP,
	}
	editor._do_terrain_carve(hit)
	assert_int(editor._history.size()).is_equal(1)

	var ctrl_z := InputEventKey.new()
	ctrl_z.pressed = true
	ctrl_z.keycode = KEY_Z
	ctrl_z.ctrl_pressed = true
	editor._input(ctrl_z)

	assert_int(editor._history.size()).is_equal(0)
	await Sandbox.dispose(get_tree(), editor, id)


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
	var id := Sandbox.map_id("block_cycle_filtered")
	await Sandbox.create_and_load(get_tree(), editor, id, false)

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
	await Sandbox.dispose(get_tree(), editor, id)


func test_map_editor_block_tab_key_cycling() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("block_tab_key_cycling")
	await Sandbox.create_and_load(get_tree(), editor, id, false)

	editor._set_mode(MapEditorClass.Mode.BLOCK)
	var initial_idx := editor._selected_block_index
	var filtered_indices := editor._hud.get_filtered_block_indices()
	assert_bool(filtered_indices.size() > 1).is_true()

	var tab_event := InputEventKey.new()
	tab_event.pressed = true
	tab_event.keycode = KEY_TAB
	editor._input(tab_event)

	assert_int(editor._selected_block_index).is_not_equal(initial_idx)
	await Sandbox.dispose(get_tree(), editor, id)


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


func test_map_editor_lmb_terrain_input_dispatches_sculpt() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("lmb_terrain_input_dispatches_sculpt")
	# Smooth terrain needed: _sculpt() is a no-op without a live _smooth_grid.
	await Sandbox.create_and_load(get_tree(), editor, id, true)
	editor._set_mode(MapEditorClass.Mode.TERRAIN)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	var hit := {
		"hit": true,
		"point": Vector3(10.0, 0.0, 10.0),
		"normal": Vector3.UP,
	}
	editor._do_terrain_add(hit)
	assert_int(editor._history.size()).is_equal(1)
	assert_str(editor._history.entries[-1].get("type", "")).is_equal("terrain")
	assert_bool(editor._history.entries[-1].has("snapshot")).is_true()

	editor._do_terrain_carve(hit)
	assert_int(editor._history.size()).is_equal(2)
	assert_str(editor._history.entries[-1].get("type", "")).is_equal("terrain")
	assert_bool(editor._history.entries[-1].has("snapshot")).is_true()
	await Sandbox.dispose(get_tree(), editor, id)


func test_map_editor_lmb_furniture_input_dispatches_place_and_remove() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("lmb_furniture_input_dispatches_place_and_remove")
	await Sandbox.create_and_load(get_tree(), editor, id, false)
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
	await Sandbox.dispose(get_tree(), editor, id)


func test_map_editor_lmb_spawn_input_dispatches_spawns() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("lmb_spawn_input_dispatches_spawns")
	await Sandbox.create_and_load(get_tree(), editor, id, false)
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
	var colonists: Array[Marker3D] = editor._spawns.colonist_markers()
	assert_bool(colonists.size() > 0).is_true()
	await Sandbox.dispose(get_tree(), editor, id)


# --- Heightmap terrain (phase 2: launcher setup + terrain drawer) ---------------

## Throwaway map id for creation tests; removed before AND after each test so a
## crashed run never leaves committed-looking content behind.
var TEST_HEIGHTMAP_MAP := Sandbox.map_id("heightmap_map")


func _remove_test_map(map_id: String) -> void:
	Sandbox.remove_map(map_id)


func _dispose_test_editor(editor: MapEditor) -> void:
	await Sandbox.dispose(get_tree(), editor, TEST_HEIGHTMAP_MAP)


func _heightmap_payload(map_id: String) -> Dictionary:
	return Sandbox.heightmap_payload(map_id)


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
	launcher._height_min_spin.value = -8.0
	launcher._height_max_spin.value = 16.0
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


## load_heightmap_image: a valid image loads and converts to L8; bad paths and
## too-small images are rejected. Fixtures are generated in memory and written
## only under user:// — res:// stays read-only (Hard rule 4) and the assertion
## no longer depends on the shipped heightmap_valley.png's own dimensions.
func test_editor_launcher_load_heightmap_image() -> void:
	var valid_path := "user://sandbox_heightmap_valid_test.png"
	var valid_source := Image.create(32, 32, false, Image.FORMAT_RGB8)
	valid_source.fill(Color(0.4, 0.4, 0.4))
	valid_source.save_png(valid_path)

	var image := EditorLauncherClass.load_heightmap_image(valid_path)
	assert_object(image).is_not_null()
	assert_int(image.get_format()).is_equal(Image.FORMAT_L8)
	assert_vector(image.get_size()).is_equal(Vector2i(32, 32))

	assert_object(EditorLauncherClass.load_heightmap_image("user://sandbox_heightmap_does_not_exist.png")).is_null()

	var tiny_path := "user://sandbox_tiny_heightmap_test.png"
	var tiny := Image.create(8, 8, false, Image.FORMAT_L8)
	tiny.fill(Color(0.5, 0.5, 0.5))
	tiny.save_png(tiny_path)
	assert_object(EditorLauncherClass.load_heightmap_image(tiny_path)).is_null()

	DirAccess.remove_absolute(valid_path)
	DirAccess.remove_absolute(tiny_path)


## Creating a heightmap map writes the per-map terrain_gen.tres (embedded L8
## texture, payload span), wires MapDef.terrain_gen at it, and the loaded map
## builds a VoxelGeneratorImage.
func test_map_editor_heightmap_creation_writes_per_map_def() -> void:
	_remove_test_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	editor.create_new_map(_heightmap_payload(TEST_HEIGHTMAP_MAP))

	var terrain_path := Sandbox.map_dir(TEST_HEIGHTMAP_MAP) + "terrain_gen.tres"
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
	assert_float(hud._terrain_min_spin.value).is_equal(-5.0)
	assert_float(hud._terrain_max_spin.value).is_equal(6.0)
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
	editor._hud._terrain_min_spin.value = -9.0
	editor._hud._terrain_max_spin.value = 21.0
	editor._on_terrain_apply()

	assert_float(editor._map_def.terrain_gen.height_start).is_equal(-9.0)
	assert_float(editor._map_def.terrain_gen.height_range).is_equal(30.0)
	assert_float(editor._hud._terrain_min_spin.value).is_equal(-9.0)
	assert_float(editor._hud._terrain_max_spin.value).is_equal(21.0)
	var generator = editor._map_root.get_smooth_grid().get_terrain().get("generator")
	assert_bool(generator is VoxelGeneratorImage).is_true()

	editor._hud._on_terrain_remove_toggled()
	assert_str(editor._hud._terrain_remove_button.text).contains("Keep Terrain")
	editor._on_terrain_apply()
	assert_object(editor._map_def.terrain_gen).is_null()
	assert_str(editor._hud._terrain_mode_label.text).contains("None")

	await _dispose_test_editor(editor)


func test_apply_edits_never_modify_a_shared_def_file() -> void:
	var id := Sandbox.map_id("shared")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.blocky_only_payload(id))
	var shared_path := "user://sandbox_shared_apply.tres"
	var shared := Sandbox.save_noise_def(shared_path, 20260817, 0.0125)
	editor._map_def.terrain_gen = shared
	editor._save_map_def()
	editor._reload_current_map()

	editor._hud._terrain_seed_spin.value = 777
	editor._on_terrain_apply()

	var on_disk := ResourceLoader.load(shared_path, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainGenDef
	assert_int(on_disk.noise_seed).is_equal(20260817)
	assert_float(on_disk.noise_frequency).is_equal(0.0125)
	assert_str(editor._map_def.terrain_gen.resource_path).is_equal(Sandbox.map_dir(id) + "terrain_gen.tres")
	assert_int(editor._map_def.terrain_gen.noise_seed).is_equal(777)
	DirAccess.remove_absolute(shared_path)
	await Sandbox.dispose(get_tree(), editor, id)


func test_replace_image_carries_water_settings() -> void:
	var id := Sandbox.map_id("water_keep")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var payload := Sandbox.heightmap_payload(id)
	payload["water_enabled"] = true
	payload["water_level"] = -3.0
	editor.create_new_map(payload)

	var image := Image.create(32, 32, false, Image.FORMAT_L8)
	image.fill(Color(0.4, 0.4, 0.4))
	editor._hud.set_pending_heightmap_image(image)
	editor._on_terrain_apply()

	assert_bool(editor._map_def.terrain_gen.water_enabled).is_true()
	assert_float(editor._map_def.terrain_gen.water_level).is_equal(-3.0)
	await Sandbox.dispose(get_tree(), editor, id)


func test_replace_image_returns_the_new_def_not_the_cached_one() -> void:
	var id := Sandbox.map_id("cache")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(id))
	var old_def: TerrainGenDef = editor._map_def.terrain_gen

	var image := Image.create(48, 48, false, Image.FORMAT_L8)
	image.fill(Color(0.2, 0.2, 0.2))
	editor._hud.set_pending_heightmap_image(image)
	editor._on_terrain_apply()

	assert_object(editor._map_def.terrain_gen).is_not_same(old_def)
	assert_int(editor._map_def.terrain_gen.heightmap.get_width()).is_equal(48)
	await Sandbox.dispose(get_tree(), editor, id)


func test_remove_terrain_sticks_after_reload() -> void:
	var id := Sandbox.map_id("remove")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(id))

	editor._hud._on_terrain_remove_toggled()
	editor._on_terrain_apply()

	assert_object(editor._map_def.terrain_gen).is_null()
	assert_object(editor._map_root.get_smooth_grid().terrain_gen).is_null()
	await Sandbox.dispose(get_tree(), editor, id)


func test_apply_reloads_the_map_exactly_once() -> void:
	var id := Sandbox.map_id("once")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var payload := Sandbox.heightmap_payload(id)
	payload["water_enabled"] = true
	editor.create_new_map(payload)

	var loads: Array[int] = [0]
	editor.child_entered_tree.connect(func(n: Node) -> void:
		if n is Map:
			loads[0] += 1
	)
	editor._on_terrain_apply()

	assert_int(loads[0]).is_equal(1)
	await Sandbox.dispose(get_tree(), editor, id)


# --- Map deletion (launcher button + confirmation dialog) -------------------


## Each map row in the launcher gets a ✕ delete button that emits
## map_delete_requested with the correct map id.
func test_editor_launcher_delete_button_emits_signal() -> void:
	var map_def := MapDef.new()
	map_def.id = "test_del_button"
	map_def.display_name = "Test Del Button"
	map_def.map_type = MapDef.MapType.POI

	var launcher: EditorLauncher = auto_free(EditorLauncherClass.new())
	add_child(launcher)
	var received: Array[String] = []
	launcher.map_delete_requested.connect(func(id: String) -> void:
		received.append(id)
	)
	launcher.setup([map_def])

	var container: VBoxContainer = launcher._maps_container
	var row: HBoxContainer = container.get_child(0) as HBoxContainer
	assert_object(row).is_not_null()

	var del_btn: Button = null
	for child in row.get_children():
		if child is Button and child.text == "✕":
			del_btn = child as Button
			break
	assert_object(del_btn).is_not_null()
	assert_str(del_btn.tooltip_text).is_equal("Delete this map")

	del_btn.pressed.emit()
	assert_array(received).contains_exactly(["test_del_button"])


## _delete_map removes the map directory and all its files from disk.
func test_map_editor_delete_map_removes_directory() -> void:
	_remove_test_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(_heightmap_payload(TEST_HEIGHTMAP_MAP))

	var dir_path := Sandbox.map_dir(TEST_HEIGHTMAP_MAP)
	assert_bool(DirAccess.dir_exists_absolute(dir_path)).is_true()

	var ok := MapRepository.delete_map(TEST_HEIGHTMAP_MAP)
	assert_bool(ok).is_true()
	assert_bool(DirAccess.dir_exists_absolute(dir_path)).is_false()


## Canceling the delete confirmation dialog leaves the map on disk.
func test_map_editor_delete_confirmation_cancel_keeps_map() -> void:
	_remove_test_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(_heightmap_payload(TEST_HEIGHTMAP_MAP))

	editor._request_delete_map(TEST_HEIGHTMAP_MAP)
	assert_str(editor._pending_delete_map_id).is_equal(TEST_HEIGHTMAP_MAP)
	assert_bool(editor._delete_dialog.visible).is_true()

	editor._delete_dialog.hide()
	assert_bool(DirAccess.dir_exists_absolute(Sandbox.map_dir(TEST_HEIGHTMAP_MAP))).is_true()

	editor._pending_delete_map_id = ""
	await _dispose_test_editor(editor)


## Confirming the delete dialog removes the map and refreshes the launcher
## list (the deleted map no longer appears).
func test_map_editor_delete_confirmation_confirm_removes_map() -> void:
	_remove_test_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(_heightmap_payload(TEST_HEIGHTMAP_MAP))

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


func test_editor_hud_rotation_indicator() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	hud.set_rotation_info(0, "Y [Yaw]")
	var orientation_lbl: Label = hud.find_child("OrientationLabel", true, false)
	assert_object(orientation_lbl).is_not_null()
	assert_str(orientation_lbl.text).contains("Rot: #0")
	assert_str(orientation_lbl.text).contains("Axis: Y [Yaw]")

	hud.set_rotation_info(5, "X [Pitch]")
	assert_str(orientation_lbl.text).contains("Rot: #5")
	assert_str(orientation_lbl.text).contains("Axis: X [Pitch]")


func test_map_editor_rotation_hotkeys_and_reset() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	if editor._launcher != null:
		editor._launcher.hide()
	editor._selected_block_index = 7 # wood_stairs (rotatable)
	editor._mode = 1 # Mode.BLOCK

	# Default rotation is 0 and axis is Y (0)
	assert_int(editor._active_rotation_index).is_equal(0)
	assert_int(editor._active_rotation_axis).is_equal(0) # RotationAxis.Y

	# Wheel up rotates along current axis (Y / Yaw)
	var ev_wheel_up := InputEventMouseButton.new()
	ev_wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	ev_wheel_up.pressed = true
	editor._input(ev_wheel_up)
	assert_int(editor._active_rotation_index).is_not_equal(0)
	var yaw_rot := editor._active_rotation_index

	# R key cycles axis to X [Pitch] (1)
	var ev_r := InputEventKey.new()
	ev_r.keycode = KEY_R
	ev_r.pressed = true
	editor._input(ev_r)
	assert_int(editor._active_rotation_axis).is_equal(1) # RotationAxis.X

	# Wheel up now rotates along X [Pitch]
	editor._input(ev_wheel_up)
	assert_int(editor._active_rotation_index).is_not_equal(yaw_rot)

	# R key cycles axis to Z [Roll] (2)
	editor._input(ev_r)
	assert_int(editor._active_rotation_axis).is_equal(2) # RotationAxis.Z

	# R key cycles axis back to Y [Yaw] (0)
	editor._input(ev_r)
	assert_int(editor._active_rotation_axis).is_equal(0) # RotationAxis.Y

	# Reset rotation via Z key
	var ev_z := InputEventKey.new()
	ev_z.keycode = KEY_Z
	ev_z.pressed = true
	editor._input(ev_z)
	assert_int(editor._active_rotation_index).is_equal(0)
	assert_int(editor._active_rotation_axis).is_equal(0)

	# Test Furniture mode wheel rotation
	editor._mode = 3 # Mode.FURNITURE
	assert_int(editor._yaw).is_equal(0)
	editor._input(ev_wheel_up)
	assert_int(editor._yaw).is_equal(1)

	var ev_wheel_down := InputEventMouseButton.new()
	ev_wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	ev_wheel_down.pressed = true
	editor._input(ev_wheel_down)
	assert_int(editor._yaw).is_equal(0)

	await _dispose_test_editor(editor)


func test_map_editor_eyedropper_reads_stored_block_index() -> void:
	_remove_test_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(_heightmap_payload(TEST_HEIGHTMAP_MAP))

	# Stored voxels are plain library model indices (the mesher's addressing
	# scheme — packed values render nothing, see BlockyGrid's class doc).
	var target_pos := Vector3i(10, 5, 10)
	await editor._apply_block_brush(target_pos, 4)

	var hit := {
		"hit": true,
		"position": target_pos,
		"normal": Vector3i.UP,
		"surface": "blocky"
	}

	editor._do_block_pick(hit)

	assert_int(editor._selected_block_index).is_equal(4)
	assert_int(editor._active_rotation_index).is_equal(0)

	await _dispose_test_editor(editor)


func test_editor_hud_block_palette_contains_only_base_defs() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	var lib := BlockLibrary.new()
	hud.populate_block_library(lib)

	var filtered := hud.get_filtered_block_indices()
	# Should contain only base block indices (excluding rotation variants)
	assert_int(filtered.size()).is_equal(lib.get_base_indices().size())
	assert_array(filtered).contains_exactly(lib.get_base_indices())


func test_map_editor_ghost_preview_renders_custom_mesh_with_rotation() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	# Stairs block index
	var stairs_idx: int = editor._block_library.get_index("wood_stairs")
	if stairs_idx <= 0:
		stairs_idx = editor._block_library.get_index("stairs_wood")
	assert_int(stairs_idx).is_greater(0)
	editor._selected_block_index = stairs_idx
	editor._mode = 1 # Mode.BLOCK
	editor._brush_diameter = 1
	editor._active_rotation_index = 0

	var stairs_def: BlockDef = editor._block_library.get_def_by_index(stairs_idx)
	assert_object(stairs_def.mesh).is_not_null()

	var dummy_hit := {
		"hit": true,
		"position": Vector3i(5, 5, 5),
		"normal": Vector3i.UP,
		"surface": "blocky"
	}

	editor._update_ghost(dummy_hit)

	# Ghost mesh should use the custom stairs mesh, not box_mesh
	assert_object(editor._ghost_view.mesh_instance.mesh).is_equal(stairs_def.mesh)
	assert_bool(editor._ghost_view.mesh_instance.transform.basis.is_equal_approx(Basis.IDENTITY)).is_true()
	assert_object(editor._ghost_view.axis_line).is_not_null()
	assert_bool(editor._ghost_view.axis_line.visible).is_true()

	# Rotate block brush and verify basis updates
	editor._rotate_block_brush(Vector3.UP)
	editor._update_ghost(dummy_hit)
	assert_int(editor._active_rotation_index).is_not_equal(0)
	var expected_basis := VoxelBlockEncoder.rot_index_to_basis(editor._active_rotation_index)
	assert_bool(editor._ghost_view.mesh_instance.transform.basis.is_equal_approx(expected_basis)).is_true()
	assert_bool(editor._ghost_view.axis_line.visible).is_true()

	# Multi-block brush diameter > 1 uses box_mesh
	editor._brush_diameter = 2
	editor._update_ghost(dummy_hit)
	assert_object(editor._ghost_view.mesh_instance.mesh).is_equal(editor._ghost_view.box_mesh)

	# Single block def without mesh uses box_mesh
	editor._brush_diameter = 1
	var custom_def := BlockDef.new()
	custom_def.id = "no_mesh_block"
	custom_def.mesh = null
	editor._block_library._defs_by_index[99] = custom_def
	editor._selected_block_index = 99
	editor._update_ghost(dummy_hit)
	assert_object(editor._ghost_view.mesh_instance.mesh).is_equal(editor._ghost_view.box_mesh)

	await _dispose_test_editor(editor)


## quantize_heightmap_image quantizes continuous float heights into integer grid steps.
func test_editor_launcher_quantize_heightmap_image() -> void:
	var img := Image.create(4, 1, false, Image.FORMAT_L8)
	# span: start = -6.0, range = 16.0
	# v = 0.0 -> h = -6.0 -> snapped -6.0 -> v = 0.0
	# v = 0.5 -> h = 2.0 -> snapped 2.0 -> v = 0.5
	# v = 0.52 -> h = 2.32 -> snapped 2.0 -> v = 0.5
	# v = 0.56 -> h = 2.96 -> snapped 3.0 -> v = 9.0/16.0 = 0.5625
	img.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 1.0))
	img.set_pixel(1, 0, Color(0.5, 0.5, 0.5, 1.0))
	img.set_pixel(2, 0, Color(0.52, 0.52, 0.52, 1.0))
	img.set_pixel(3, 0, Color(0.56, 0.56, 0.56, 1.0))

	var q_img := EditorLauncherClass.quantize_heightmap_image(img, -6.0, 16.0, 1.0)
	assert_object(q_img).is_not_null()
	assert_int(q_img.get_format()).is_equal(Image.FORMAT_RF)

	var p0: float = q_img.get_pixel(0, 0).r
	var p1: float = q_img.get_pixel(1, 0).r
	var p2: float = q_img.get_pixel(2, 0).r
	var p3: float = q_img.get_pixel(3, 0).r

	var h0: float = -6.0 + p0 * 16.0
	var h1: float = -6.0 + p1 * 16.0
	var h2: float = -6.0 + p2 * 16.0
	var h3: float = -6.0 + p3 * 16.0

	assert_float(h0).is_equal_approx(-6.0, 0.05)
	assert_float(h1).is_equal_approx(2.0, 0.05)
	assert_float(h2).is_equal_approx(2.0, 0.05)
	assert_float(h3).is_equal_approx(3.0, 0.05)


## Launcher snap_to_grid checkbox updates footprint stats and includes field in payload.
func test_editor_launcher_snap_to_grid_toggle_and_payload() -> void:
	var launcher: EditorLauncher = auto_free(EditorLauncherClass.new())
	add_child(launcher)
	var received: Array = []
	launcher.new_map_requested.connect(func(payload: Dictionary) -> void:
		received.append(payload)
	)

	launcher._new_name_input.text = TEST_HEIGHTMAP_MAP
	launcher._terrain_mode_select.selected = EditorLauncherClass.TerrainMode.HEIGHTMAP
	launcher._on_terrain_mode_selected(EditorLauncherClass.TerrainMode.HEIGHTMAP)

	var image := Image.create(32, 32, false, Image.FORMAT_L8)
	image.fill(Color(0.5, 0.5, 0.5))
	launcher._heightmap_image = image
	launcher._height_min_spin.value = -6.0
	launcher._height_max_spin.value = 10.0

	assert_object(launcher._snap_to_grid_check).is_not_null()
	assert_bool(launcher._snap_to_grid_check.button_pressed).is_true()
	launcher._update_heightmap_stats()
	assert_str(launcher._heightmap_stats_label.text).contains("grid tiers")

	launcher._on_create_pressed()
	assert_int(received.size()).is_equal(1)
	assert_bool(received[0]["snap_to_grid"]).is_true()


## Terrain drawer includes snap_to_grid in edits and span label shows tier info.
func test_editor_hud_terrain_drawer_snap_to_grid() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()
	var hm_def := TerrainGenDef.new()
	hm_def.height_start = -4.0
	hm_def.height_range = 10.0
	var img := Image.create(16, 16, false, Image.FORMAT_L8)
	img.fill(Color.BLACK)
	hm_def.heightmap = ImageTexture.create_from_image(img)
	hud.set_terrain_drawer_state(hm_def)

	# Snap is opt-in: off by default, and absent from an untouched Apply.
	assert_bool(hud._terrain_snap_check.button_pressed).is_false()
	assert_bool(hud.get_terrain_drawer_edits().has("snap_to_grid")).is_false()

	hud._terrain_snap_check.button_pressed = true
	assert_bool(hud.get_terrain_drawer_edits().get("snap_to_grid", false)).is_true()
	assert_str(hud._terrain_span_label.text).contains("grid tiers")


func test_editor_hud_untouched_drawer_reports_no_field_edits() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()
	var noise_def := TerrainGenDef.new()
	noise_def.noise_seed = 20260817
	noise_def.noise_frequency = 0.0125
	hud.set_terrain_drawer_state(noise_def)

	var edits := hud.get_terrain_drawer_edits()
	for key in ["noise_seed", "noise_frequency", "height_start", "height_range", "snap_to_grid"]:
		assert_bool(edits.has(key)).is_false()
	# Values round-trip unclamped and unrounded.
	assert_float(hud._terrain_seed_spin.value).is_equal(20260817.0)
	assert_float(hud._terrain_freq_spin.value).is_equal_approx(0.0125, 0.00001)


func test_editor_hud_edited_field_is_reported_alone() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	add_child(hud)
	hud.setup()
	hud.set_terrain_drawer_state(TerrainGenDef.new())

	hud._terrain_seed_spin.value = 4242

	var edits := hud.get_terrain_drawer_edits()
	assert_int(edits.get("noise_seed", -1)).is_equal(4242)
	assert_bool(edits.has("noise_frequency")).is_false()


func test_editor_hud_reload_of_drawer_state_clears_touched_flags() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	add_child(hud)
	hud.setup()
	hud.set_terrain_drawer_state(TerrainGenDef.new())
	hud._terrain_seed_spin.value = 4242
	hud.set_terrain_drawer_state(TerrainGenDef.new())
	assert_bool(hud.get_terrain_drawer_edits().has("noise_seed")).is_false()


func test_editor_hud_converting_noise_map_seeds_span_from_the_def() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()
	var noise_def := TerrainGenDef.new()
	noise_def.height_start = -3.0
	noise_def.height_range = 8.0
	hud.set_terrain_drawer_state(noise_def)

	var img := Image.create(16, 16, false, Image.FORMAT_L8)
	hud.set_pending_heightmap_image(img)

	var edits := hud.get_terrain_drawer_edits()
	assert_float(edits.get("height_start", 999.0)).is_equal(-3.0)
	assert_float(edits.get("height_range", 999.0)).is_equal(8.0)


func test_editor_hud_adding_heightmap_to_terrainless_map_uses_launcher_defaults() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()
	hud.set_terrain_drawer_state(null)
	hud.set_pending_heightmap_image(Image.create(16, 16, false, Image.FORMAT_L8))

	var edits := hud.get_terrain_drawer_edits()
	assert_float(edits.get("height_start", 999.0)).is_equal(MapTerrainAuthoring.DEFAULT_HEIGHT_START)
	assert_float(edits.get("height_range", 999.0)).is_equal(MapTerrainAuthoring.DEFAULT_HEIGHT_RANGE)


## Map editor creation with snap_to_grid quantizes the embedded texture.
func test_map_editor_heightmap_creation_with_snapping() -> void:
	_remove_test_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	var payload := _heightmap_payload(TEST_HEIGHTMAP_MAP)
	payload["snap_to_grid"] = true
	payload["height_start"] = -6.0
	payload["height_range"] = 16.0
	editor.create_new_map(payload)

	var terrain_path := Sandbox.map_dir(TEST_HEIGHTMAP_MAP) + "terrain_gen.tres"
	assert_bool(ResourceLoader.exists(terrain_path)).is_true()
	var terrain_def := load(terrain_path) as TerrainGenDef
	assert_object(terrain_def.heightmap).is_not_null()

	var img := terrain_def.heightmap.get_image()
	assert_int(img.get_format()).is_equal(Image.FORMAT_RF)

	await _dispose_test_editor(editor)


## Map editor creation configures flora parameters and begins with 0 authored trees.
func test_map_editor_new_map_with_flora_parameters() -> void:
	var TEST_FLORA_MAP := Sandbox.map_id("flora_params_map")
	_remove_test_map(TEST_FLORA_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	var payload := _heightmap_payload(TEST_FLORA_MAP)
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

	await _dispose_test_editor(editor)
	_remove_test_map(TEST_FLORA_MAP)


func test_map_editor_enemy_spawn_place_and_remove() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var id := Sandbox.map_id("enemy_spawn_place_and_remove")
	await Sandbox.create_and_load(get_tree(), editor, id, false)
	editor._set_mode(MapEditorClass.Mode.SPAWN)

	var hit_enemy := {
		"hit": true,
		"surface": "blocky",
		"position": Vector3i(12, 0, 12),
		"normal": Vector3i(0, 1, 0),
	}
	var initial_enemy_count: int = editor._spawns.counts()["enemies"]
	editor._do_spawn_place("enemy", hit_enemy)

	var enemies: Array[Marker3D] = editor._spawns.enemy_markers()
	assert_int(enemies.size()).is_equal(initial_enemy_count + 1)
	var last_enemy: Marker3D = enemies[enemies.size() - 1]
	assert_str(last_enemy.name).contains("EnemySpawn")
	assert_object(last_enemy.get_node_or_null("SpawnVisualizer")).is_not_null()

	# Test spawn removal
	editor._do_spawn_remove(hit_enemy)
	enemies = editor._spawns.enemy_markers()
	assert_int(enemies.size()).is_equal(initial_enemy_count)
	await Sandbox.dispose(get_tree(), editor, id)


func test_map_editor_spawn_selector_hud_interaction() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()
	hud.set_mode(MapEditorClass.Mode.SPAWN)

	var counter := Doubles.SignalCounter.new(hud.spawn_type_selected)
	hud.set_spawn_type("enemy")
	hud.set_spawn_counts(true, 3, 5)

	assert_str(hud._spawn_summary_label.text).contains("Player: Set")
	assert_str(hud._spawn_summary_label.text).contains("Colonists: 3")
	assert_str(hud._spawn_summary_label.text).contains("Enemies: 5")


func test_map_editor_new_map_with_water_enabled() -> void:
	var TEST_WATER_MAP := Sandbox.map_id("water_create_map")
	_remove_test_map(TEST_WATER_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	var payload := _heightmap_payload(TEST_WATER_MAP)
	payload["water_enabled"] = true
	payload["water_level"] = -2.0
	editor.create_new_map(payload)

	assert_bool(editor._map_def.water_enabled).is_true()
	assert_float(editor._map_def.water_level).is_equal(-2.0)

	await _dispose_test_editor(editor)
	_remove_test_map(TEST_WATER_MAP)


func test_apply_water_settings_updates_map_and_terrain_def() -> void:
	var id := Sandbox.map_id("water_apply")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var payload := Sandbox.heightmap_payload(id)
	payload["water_enabled"] = true
	payload["water_level"] = -2.0
	editor.create_new_map(payload)

	editor.apply_water_settings(-1.0)

	assert_bool(editor._map_def.water_enabled).is_true()
	assert_float(editor._map_def.water_level).is_equal(-1.0)
	assert_float(editor._map_def.terrain_gen.water_level).is_equal(-1.0)
	await Sandbox.dispose(get_tree(), editor, id)


func test_apply_water_settings_can_turn_water_off() -> void:
	var id := Sandbox.map_id("water_off")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var payload := Sandbox.heightmap_payload(id)
	payload["water_enabled"] = true
	editor.create_new_map(payload)

	editor.apply_water_settings(-2.0, false)

	assert_bool(editor._map_def.water_enabled).is_false()
	assert_bool(editor._map_def.terrain_gen.water_enabled).is_false()
	await Sandbox.dispose(get_tree(), editor, id)


func test_editor_hud_water_button_emits_enabled_and_level() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()
	var got: Array = []
	hud.water_apply_requested.connect(func(enabled: bool, level: float) -> void: got.assign([enabled, level]))
	hud.set_water_drawer_state(true, -3.5)

	hud._drawer_water_flood_button.pressed.emit()

	assert_array(got).is_equal([true, -3.5])


func test_editor_hud_text_control_detection_is_generic() -> void:
	assert_bool(EditorHUDClass.is_text_control(auto_free(LineEdit.new()))).is_true()
	assert_bool(EditorHUDClass.is_text_control(auto_free(TextEdit.new()))).is_true()
	assert_bool(EditorHUDClass.is_text_control(auto_free(Button.new()))).is_false()
	assert_bool(EditorHUDClass.is_text_control(null)).is_false()


func test_editor_hud_focus_inside_any_spinbox_counts_as_input_focus() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	add_child(hud)
	hud.setup()
	hud.toggle_metadata_panel()
	hud._meta_flora_cap_spin.get_line_edit().grab_focus()
	assert_bool(hud.is_any_input_focused()).is_true()
	assert_bool(hud.is_metadata_focused()).is_true()
	hud._meta_flora_cap_spin.get_line_edit().release_focus()
	assert_bool(hud.is_any_input_focused()).is_false()


func test_editor_hud_metadata_edits_omit_unchanged_bounds_and_flora() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()
	# 200 is not on the 16 m spinner step and 62 is not on the 5 step: the spinners round what they display.
	var off_grid := AABB(Vector3(-100.0, -40.0, -100.0), Vector3(200.0, 60.0, 200.0))
	hud.set_metadata("Name", "Desc", 0, 1, off_grid, 3, 62, 15)

	var edits := hud.get_metadata_edits()

	assert_bool(edits.has("world_bounds")).is_false()
	assert_bool(edits.has("flora_spawn_cap")).is_false()
	assert_bool(edits.has("display_name")).is_false()


func test_editor_hud_metadata_edits_report_changed_fields_only() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	add_child(hud)
	hud.setup()
	hud.set_metadata("Name", "Desc", 0, 1, AABB(Vector3(-96, -48, -96), Vector3(192, 64, 192)), 3, 60, 15)

	hud._meta_bounds_xz_spin.value = 224.0
	hud._meta_display_name_input.text = "Renamed"

	var edits := hud.get_metadata_edits()
	assert_bool(edits.has("world_bounds")).is_true()
	assert_str(edits.get("display_name", "")).is_equal("Renamed")
	assert_bool(edits.has("flora_spawn_cap")).is_false()


func test_editor_hud_metadata_edited_signal_fires_on_user_edit_not_on_load() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	add_child(hud)
	hud.setup()
	var counter := Doubles.SignalCounter.new(hud.metadata_edited)

	hud.set_metadata("Name", "Desc", 0, 1)
	assert_int(counter.count).is_equal(0)

	hud._meta_difficulty_spin.value = 5.0
	assert_int(counter.count).is_greater(0)


func test_save_map_failure_keeps_the_map_dirty() -> void:
	var id := Sandbox.map_id("save_fail")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.blocky_only_payload(id))
	editor._mark_dirty()
	# A scene path inside a folder that does not exist makes ResourceSaver.save fail.
	editor._map_scene_path = Sandbox.map_dir(id) + "no_such_dir/map.tscn"

	var ok: bool = editor.save_map()

	assert_bool(ok).is_false()
	assert_bool(editor._dirty).is_true()
	await Sandbox.dispose(get_tree(), editor, id)


func test_save_map_success_returns_true_and_clears_dirty() -> void:
	var id := Sandbox.map_id("save_ok")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.blocky_only_payload(id))
	editor._mark_dirty()

	assert_bool(editor.save_map()).is_true()
	assert_bool(editor._dirty).is_false()
	await Sandbox.dispose(get_tree(), editor, id)


func test_save_map_keeps_off_grid_values_the_author_did_not_touch() -> void:
	var id := Sandbox.map_id("bounds")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.blocky_only_payload(id))
	# 200 is off the 16 m spinner step and 62 is off the 5 step.
	var off_grid := AABB(Vector3(-100.0, -40.0, -100.0), Vector3(200.0, 60.0, 200.0))
	editor._map_def.world_bounds = off_grid
	editor._map_def.flora_spawn_cap = 62
	editor._hud.set_metadata("N", "D", 0, 1, off_grid, 0, 62, 15)

	editor.save_map()

	assert_bool(editor._map_def.world_bounds == off_grid).is_true()
	assert_int(editor._map_def.flora_spawn_cap).is_equal(62)
	await Sandbox.dispose(get_tree(), editor, id)


func _spawn_hit() -> Dictionary:
	return {"hit": true, "position": Vector3i.ZERO, "normal": Vector3i.UP, "surface": "blocky"}


func _dirty_sandbox_editor(id: String) -> MapEditor:
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(id))
	editor._do_spawn_place("enemy", _spawn_hit())
	return editor


func test_apply_on_dirty_map_asks_before_reloading() -> void:
	var id := Sandbox.map_id("guard_ask")
	var editor := _dirty_sandbox_editor(id)
	var root_before: Map = editor._map_root

	editor._on_terrain_apply()

	assert_bool(editor._unsaved_dialog.visible).is_true()
	assert_object(editor._map_root).is_same(root_before)
	editor._on_unsaved_canceled()
	await Sandbox.dispose(get_tree(), editor, id)


func test_save_and_continue_keeps_unsaved_markers_across_the_reload() -> void:
	var id := Sandbox.map_id("guard_save")
	var editor := _dirty_sandbox_editor(id)
	var root_before: Map = editor._map_root
	editor._on_terrain_apply()

	editor._on_unsaved_save_confirmed()

	assert_object(editor._map_root).is_not_same(root_before)
	assert_int(editor._spawns.counts()["enemies"]).is_equal(1)
	assert_bool(editor._dirty).is_false()
	await Sandbox.dispose(get_tree(), editor, id)


func test_discard_and_continue_reloads_without_the_markers() -> void:
	var id := Sandbox.map_id("guard_discard")
	var editor := _dirty_sandbox_editor(id)
	editor._on_terrain_apply()

	editor._on_unsaved_custom_action(&"discard")

	assert_int(editor._spawns.counts()["enemies"]).is_equal(0)
	await Sandbox.dispose(get_tree(), editor, id)


func test_cancel_keeps_the_map_and_clears_the_pending_action() -> void:
	var id := Sandbox.map_id("guard_cancel")
	var editor := _dirty_sandbox_editor(id)
	var root_before: Map = editor._map_root
	editor._on_terrain_apply()

	editor._on_unsaved_canceled()

	assert_object(editor._map_root).is_same(root_before)
	assert_bool(editor._pending_after_guard.is_valid()).is_false()
	await Sandbox.dispose(get_tree(), editor, id)


func test_failed_save_does_not_continue_into_the_reload() -> void:
	var id := Sandbox.map_id("guard_fail")
	var editor := _dirty_sandbox_editor(id)
	var root_before: Map = editor._map_root
	editor._map_scene_path = Sandbox.map_dir(id) + "no_such_dir/map.tscn"
	editor._on_terrain_apply()

	editor._on_unsaved_save_confirmed()

	assert_object(editor._map_root).is_same(root_before)
	assert_bool(editor._dirty).is_true()
	await Sandbox.dispose(get_tree(), editor, id)


func test_apply_on_clean_map_reloads_without_asking() -> void:
	var id := Sandbox.map_id("guard_clean")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(id))
	var root_before: Map = editor._map_root

	editor._on_terrain_apply()

	assert_bool(editor._unsaved_dialog.visible).is_false()
	assert_object(editor._map_root).is_not_same(root_before)
	await Sandbox.dispose(get_tree(), editor, id)


func test_panel_triggered_reload_keeps_the_cursor_free() -> void:
	var id := Sandbox.map_id("cursor")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(id))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	editor._on_terrain_apply()

	assert_int(Input.mouse_mode).is_equal(Input.MOUSE_MODE_VISIBLE)
	await Sandbox.dispose(get_tree(), editor, id)


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


func test_spawn_remove_never_deletes_furniture_markers() -> void:
	var id := Sandbox.map_id("spawn_rm")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.blocky_only_payload(id))
	var hit := {"hit": true, "position": Vector3i.ZERO, "normal": Vector3i.UP, "surface": "blocky"}
	editor._do_spawn_place("enemy", hit)
	# A furniture marker sits closer to the hit point than the enemy spawn.
	var spawn_points := editor._map_root.find_child("SpawnPoints") as Node3D
	var furniture := Marker3D.new()
	furniture.name = "Furniture_zz_0"
	spawn_points.add_child(furniture)
	furniture.global_position = editor._get_surface_hit_point(hit)

	editor._do_spawn_remove(hit)

	assert_bool(is_instance_valid(furniture) and not furniture.is_queued_for_deletion()).is_true()
	assert_int(editor._spawns.counts()["enemies"]).is_equal(0)
	await Sandbox.dispose(get_tree(), editor, id)


func test_palette_step_index_wraps_and_handles_edges() -> void:
	var idx: Array[int] = [4, 7, 9]
	assert_int(EditorPalettePanelClass.step_index(idx, 4, 1)).is_equal(7)
	assert_int(EditorPalettePanelClass.step_index(idx, 9, 1)).is_equal(4)
	assert_int(EditorPalettePanelClass.step_index(idx, 4, -1)).is_equal(9)
	assert_int(EditorPalettePanelClass.step_index(idx, 5, 1)).is_equal(4)
	assert_int(EditorPalettePanelClass.step_index([] as Array[int], 0, 1)).is_equal(-1)


func test_palette_filtered_indices_are_a_copy() -> void:
	var panel: EditorPalettePanel = auto_free(EditorPalettePanelClass.new())
	panel.setup("T", "search", Color.WHITE)
	var item := EditorPalettePanelClass.Item.new()
	item.index = 3
	item.id = "zz_a"
	panel.populate([item] as Array[EditorPalettePanel.Item], 3)

	var leaked := panel.get_filtered_indices()
	leaked.append(99)

	assert_int(panel.get_filtered_indices().size()).is_equal(1)


func test_furniture_cycle_with_a_zero_match_filter_does_not_corrupt_the_palette() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	var a := FurnitureDef.new()
	a.id = "zz_a"
	var b := FurnitureDef.new()
	b.id = "zz_b"
	editor._furniture_defs = [a, b] as Array[FurnitureDef]
	editor._hud.populate_furniture_list(editor._furniture_defs, 0)
	editor._hud._furniture_palette._on_search_changed("no_such_furniture")

	editor._cycle_furniture(1)

	assert_int(editor._hud.get_filtered_furniture_indices().size()).is_equal(0)


func test_palette_query_matches_name_id_and_extra_text() -> void:
	assert_bool(EditorPalettePanelClass.query_matches("Wooden Bed", "bed1", "  ", "")).is_true()
	assert_bool(EditorPalettePanelClass.query_matches("Wooden Bed", "bed1", "wood", "")).is_true()
	assert_bool(EditorPalettePanelClass.query_matches("Wooden Bed", "bed1", "BED1", "")).is_true()
	assert_bool(EditorPalettePanelClass.query_matches("Wall", "wall1", "shelter", "Shelter")).is_true()
	assert_bool(EditorPalettePanelClass.query_matches("Wall", "wall1", "door", "Shelter")).is_false()


func test_wheel_belongs_to_the_view_only_when_captured_or_over_no_gui() -> void:
	assert_bool(MapEditorClass.wheel_belongs_to_view(true, true)).is_true()
	assert_bool(MapEditorClass.wheel_belongs_to_view(false, false)).is_true()
	assert_bool(MapEditorClass.wheel_belongs_to_view(false, true)).is_false()


func test_wheel_still_rotates_furniture_while_the_cursor_is_captured() -> void:
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor._launcher.hide_launcher()
	editor._set_mode(MapEditorClass.Mode.FURNITURE)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP

	editor._input(wheel)

	assert_int(editor._yaw).is_equal(1)


func test_block_brush_after_unload_reports_not_landed_instead_of_crashing() -> void:
	var id := Sandbox.map_id("brush_unload")
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.blocky_only_payload(id))
	editor.unload_map()

	var landed: bool = await editor._apply_block_brush(Vector3i.ZERO, 1)

	assert_bool(landed).is_false()
	Sandbox.remove_map(id)


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
