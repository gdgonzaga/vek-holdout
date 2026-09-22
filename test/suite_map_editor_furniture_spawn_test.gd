extends GdUnitTestSuite
## Furniture placement/cycling/rotation and spawn marker placement (player,
## colonist, enemy), including ghost previews and the spawn selector HUD
## interaction (split from suite_map_editor_test.gd, R12D).

const MapEditorClass = preload("res://tools/map_editor/map_editor.gd")
const EditorHUDClass = preload("res://tools/map_editor/editor_hud.gd")
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
