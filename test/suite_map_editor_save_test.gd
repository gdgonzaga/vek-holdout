extends GdUnitTestSuite
## Save/dirty-flag flow and the unsaved-changes apply guard: successful and
## failed saves, scene packing of spawn markers, metadata round-tripping, and
## the dialog paths for applying terrain edits onto a dirty map (split from
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


func test_map_editor_save_button_triggers_save_map() -> void:
	Sandbox.remove_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	# Throwaway map: save_map() repacks the scene and rewrites map_def.tres —
	# never point that at committed content (base/dev).
	editor.create_new_map(Sandbox.heightmap_payload(TEST_HEIGHTMAP_MAP))

	editor._dirty = true
	editor._hud.set_map_info(TEST_HEIGHTMAP_MAP, true)
	assert_str(editor._hud._map_info_label.text).contains("*")

	editor._hud._save_button.pressed.emit()
	assert_bool(editor._dirty).is_false()
	assert_bool(editor._hud._map_info_label.text.contains("*")).is_false()
	await Sandbox.dispose(get_tree(), editor, TEST_HEIGHTMAP_MAP)


func test_map_editor_metadata_editing_and_save() -> void:
	Sandbox.remove_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	# Throwaway map: this test SAVES, which rewrites map_def.tres — pointing it
	# at base used to dirty committed content on every suite run.
	editor.create_new_map(Sandbox.heightmap_payload(TEST_HEIGHTMAP_MAP))

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
	await Sandbox.dispose(get_tree(), editor, TEST_HEIGHTMAP_MAP)


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


func _spawn_hit() -> Dictionary:
	return {"hit": true, "position": Vector3i.ZERO, "normal": Vector3i.UP, "surface": "blocky"}


func _dirty_sandbox_editor(id: String) -> MapEditor:
	Sandbox.remove_map(id)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(id))
	editor._do_spawn_place("enemy", _spawn_hit())
	return editor
