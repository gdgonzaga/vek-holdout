extends GdUnitTestSuite
## Block brush sizing/targeting, block cycling and filtering, rotation
## hotkeys, the eyedropper, and ghost-mesh rendering for rotatable blocks
## (split from suite_map_editor_test.gd, R12D).

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

	await Sandbox.dispose(get_tree(), editor, TEST_HEIGHTMAP_MAP)


func test_map_editor_eyedropper_reads_stored_block_index() -> void:
	Sandbox.remove_map(TEST_HEIGHTMAP_MAP)
	var editor: MapEditor = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(TEST_HEIGHTMAP_MAP))

	# Stored voxels are plain library model indices (the mesher's addressing
	# scheme — packed values render nothing, see BlockyGrid's class doc).
	var target_pos := Vector3i(10, 5, 10)
	# hygiene-ok: awaits map_editor.gd's own bounded block-write retry loop (max
	# 5 attempts x 0.1s = 0.5s worst case), not a new wall-clock wait; the
	# landed result is asserted directly below instead of trusted implicitly.
	var landed := await editor._apply_block_brush(target_pos, 4)
	assert_bool(landed).is_true()

	var hit := {
		"hit": true,
		"position": target_pos,
		"normal": Vector3i.UP,
		"surface": "blocky"
	}

	editor._do_block_pick(hit)

	assert_int(editor._selected_block_index).is_equal(4)
	assert_int(editor._active_rotation_index).is_equal(0)

	await Sandbox.dispose(get_tree(), editor, TEST_HEIGHTMAP_MAP)


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

	await Sandbox.dispose(get_tree(), editor, TEST_HEIGHTMAP_MAP)


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
