extends GdUnitTestSuite
## New-map dialog payload construction and heightmap image handling: launcher
## population/signals, heightmap payload validation, the noise-def dropdown,
## image loading/quantizing, delete signal, and the snap-to-grid toggle
## (split from suite_map_editor_test.gd, R12D).

const MapEditorClass = preload("res://tools/map_editor/map_editor.gd")
const EditorLauncherClass = preload("res://tools/map_editor/editor_launcher.gd")
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


func test_editor_launcher_population_and_signals() -> void:
	var launcher: EditorLauncher = auto_free(EditorLauncherClass.new())
	add_child(launcher)

	# R12C hygiene cleanup: a synthetic sandbox id/path stands in for a shipped
	# map — EditorLauncher.setup() only renders display_name, it never loads
	# scene_path, so this never touched res:// content even before the rename.
	var map_def := MapDef.new()
	map_def.id = Sandbox.map_id("launcher_population")
	map_def.display_name = "Base Camp"
	map_def.description = "Starting outpost"
	map_def.map_type = MapDef.MapType.BASE
	map_def.scene_path = Sandbox.map_dir(map_def.id) + "map.tscn"

	launcher.setup([map_def])
	assert_int(launcher._maps_container.get_child_count()).is_equal(1)
	var row: HBoxContainer = launcher._maps_container.get_child(0) as HBoxContainer
	var btn: Button = row.get_child(0) as Button
	assert_str(btn.text).contains("Base Camp")


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
## ones (those are per-map content), with the default preselected. Fed from a
## throwaway user:// directory (via MapRepository.scan_noise_defs' optional
## dir_path parameter) instead of shipped res://data/terrain content, so the
## assertions stay content-agnostic.
func test_editor_launcher_noise_def_dropdown_excludes_heightmap_defs() -> void:
	var scratch_dir := "user://sandbox_scan_noise_defs_editor/"
	DirAccess.make_dir_recursive_absolute(scratch_dir)
	var noise_path := scratch_dir + "sandbox_noise.tres"
	var heightmap_path := scratch_dir + "sandbox_heightmap.tres"
	var noise_def := Sandbox.save_noise_def(noise_path, 20260922, 0.02)
	var heightmap_def := _make_heightmap_terrain_gen_def(heightmap_path)

	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	# Repopulate the dropdown from the synthetic directory, overriding the
	# real-TERRAIN_DIR scan _ready() already ran, so nothing here depends on
	# shipped defs.
	var entries := MapRepository.scan_noise_defs(scratch_dir)
	editor._launcher.setup_noise_defs(entries, noise_path)

	var select: OptionButton = editor._launcher._noise_def_select
	assert_int(select.item_count).is_greater(0)
	var has_noise_def := false
	var has_heightmap_def := false
	for i in range(select.item_count):
		if select.get_item_text(i) == noise_def.id:
			has_noise_def = true
		if select.get_item_text(i) == heightmap_def.id:
			has_heightmap_def = true
	assert_bool(has_noise_def).is_true()
	assert_bool(has_heightmap_def).is_false()
	assert_str(editor._launcher._selected_noise_def_path()).is_equal(noise_path)

	DirAccess.remove_absolute(noise_path)
	DirAccess.remove_absolute(heightmap_path)
	DirAccess.remove_absolute(scratch_dir)


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


func _make_heightmap_terrain_gen_def(path: String) -> TerrainGenDef:
	## Auxiliary: Builds and persists a synthetic heightmap-driven TerrainGenDef so
	## the dropdown-exclusion assertion has a real entry to drop, without reading
	## shipped res://data/terrain content.
	var def := TerrainGenDef.new()
	def.id = "sandbox_heightmap_def"
	var image := Image.create(4, 4, false, Image.FORMAT_L8)
	image.fill(Color(0.5, 0.5, 0.5))
	def.heightmap = ImageTexture.create_from_image(image)
	def.take_over_path(path)
	ResourceSaver.save(def, path)
	return def
