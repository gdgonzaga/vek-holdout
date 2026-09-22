extends GdUnitTestSuite
## HUD label/state/signal tests with no map loaded: mode switching, block and
## terrain info panels, furniture/spawn info, save button, grid overlay,
## coordinate readout, terrain drawer state and metadata edit reporting
## (split from suite_map_editor_test.gd, R12D).

const MapEditorClass = preload("res://tools/map_editor/map_editor.gd")
const EditorHUDClass = preload("res://tools/map_editor/editor_hud.gd")
const EditorGridOverlayClass = preload("res://tools/map_editor/editor_grid_overlay.gd")
const Doubles = preload("res://test/helpers/doubles.gd")
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
