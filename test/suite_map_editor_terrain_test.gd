extends GdUnitTestSuite
## Terrain sculpting, the terrain drawer's apply/reload cycle, heightmap and
## water creation, and terrain-generator injection on load (split from
## suite_map_editor_test.gd, R12D).

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


## Creating a heightmap map writes the per-map terrain_gen.tres (embedded L8
## texture, payload span), wires MapDef.terrain_gen at it, and the loaded map
## builds a VoxelGeneratorImage.
func test_map_editor_heightmap_creation_writes_per_map_def() -> void:
	Sandbox.remove_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	editor.create_new_map(Sandbox.heightmap_payload(TEST_HEIGHTMAP_MAP))

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

	await Sandbox.dispose(get_tree(), editor, TEST_HEIGHTMAP_MAP)


## Apply on a heightmap map persists span edits to the per-map def and reloads
## the map with them; the remove toggle strips terrain_gen entirely.
func test_map_editor_terrain_drawer_edits_apply_and_reload() -> void:
	Sandbox.remove_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(TEST_HEIGHTMAP_MAP))

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

	await Sandbox.dispose(get_tree(), editor, TEST_HEIGHTMAP_MAP)


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


## Map editor creation with snap_to_grid quantizes the embedded texture.
func test_map_editor_heightmap_creation_with_snapping() -> void:
	Sandbox.remove_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	var payload := Sandbox.heightmap_payload(TEST_HEIGHTMAP_MAP)
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

	await Sandbox.dispose(get_tree(), editor, TEST_HEIGHTMAP_MAP)


func test_map_editor_new_map_with_water_enabled() -> void:
	var TEST_WATER_MAP := Sandbox.map_id("water_create_map")
	Sandbox.remove_map(TEST_WATER_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)

	var payload := Sandbox.heightmap_payload(TEST_WATER_MAP)
	payload["water_enabled"] = true
	payload["water_level"] = -2.0
	editor.create_new_map(payload)

	assert_bool(editor._map_def.water_enabled).is_true()
	assert_float(editor._map_def.water_level).is_equal(-2.0)

	# Original _dispose_test_editor() always disposed TEST_HEIGHTMAP_MAP (a
	# different id than the map this test actually creates); preserved as-is
	# so behavior is unchanged by the split. The explicit remove_map below is
	# what actually cleans up this test's own TEST_WATER_MAP folder.
	await Sandbox.dispose(get_tree(), editor, TEST_HEIGHTMAP_MAP)
	Sandbox.remove_map(TEST_WATER_MAP)


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
