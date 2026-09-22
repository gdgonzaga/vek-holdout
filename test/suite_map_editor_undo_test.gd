extends GdUnitTestSuite
## Block, terrain and structure undo: history push/pop invariants, the
## terrain-snapshot region captured around a brush edit, and the ctrl+z
## hotkey (split from suite_map_editor_test.gd, R12D; the structure-stamp
## undo test moved here from suite_structure_ghost_and_stamping_test.gd
## since it also exercises MapEditor's undo history).

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


## Moved from suite_structure_ghost_and_stamping_test.gd (R12D): this is the
## one structure test that stamps into a live, loaded map's real BlockyGrid,
## so its palette fixture must name a block BlockLibrary actually has instead
## of the literal "stone_wall" id the shared fixture used, which logged
## "ERROR: BlockyGrid: unknown block_id 'stone_wall'" on every run.
func test_map_editor_structure_stamp_and_undo() -> void:
	var id := Sandbox.map_id("undo_structure")
	Sandbox.remove_map(id)
	var editor: MapEditorClass = auto_free(MapEditorClass.new())
	add_child(editor)
	editor.create_new_map(Sandbox.heightmap_payload(id))
	# Real block id fixture: read it from the loaded map's own library so the
	# stamp lands on a block BlockyGrid recognizes.
	var mapping := _create_sample_mapping(editor._block_library.get_all_defs()[0].id)
	var def := _create_sample_structure(mapping)
	editor._structure_defs = [def]
	editor._selected_structure_idx = 0
	editor._set_mode(MapEditorClass.Mode.STRUCTURE)
	editor._structure_tool.set_cached_vox_data(_create_sample_vox_data())

	editor._do_structure_stamp({"hit": true, "position": Vector3i(10, 20, 30), "normal": Vector3i.UP, "surface": "blocky"})

	assert_int(editor._history.size()).is_equal(1)
	var entry: Dictionary = editor._history.entries[0]
	assert_str(entry["type"]).is_equal("structure")
	assert_bool(entry.has("terrain_snapshot")).is_true()
	assert_bool(editor._dirty).is_true()

	editor._undo_last()
	assert_int(editor._history.size()).is_equal(0)
	await Sandbox.dispose(get_tree(), editor, id)


func _create_sample_vox_data() -> VoxData:
	## Auxiliary: builds the 3x2x3 four-color vox fixture the structure stamp test stamps into the grid.
	var data: VoxData = auto_free(VoxData.new())
	data.dimensions = Vector3i(3, 2, 3)
	data.palette = [
		Color(1.0, 0.0, 0.0, 1.0), # 1: Red
		Color(0.0, 1.0, 0.0, 1.0), # 2: Green
		Color(0.0, 0.0, 1.0, 1.0), # 3: Blue
		Color(1.0, 1.0, 0.0, 1.0), # 4: Yellow
	]
	data.set_voxel(Vector3i(1, 0, 1), 1)
	data.set_voxel(Vector3i(0, 0, 0), 2)
	data.set_voxel(Vector3i(1, 1, 1), 3)
	data.set_voxel(Vector3i(2, 0, 1), 4)
	return data


func _create_sample_mapping(block_id: String) -> VoxPaletteMapping:
	## Auxiliary: maps the vox fixture's palette entries to a real block id (BLOCK),
	## a terrain material (SMOOTH_TERRAIN), AIR, and IGNORE.
	var mapping: VoxPaletteMapping = auto_free(VoxPaletteMapping.new())
	mapping.id = "test_mapping"
	mapping.display_name = "Test Mapping"

	var e1: VoxPaletteEntry = auto_free(VoxPaletteEntry.new())
	e1.source_index = 1
	e1.target_type = VoxPaletteEntry.TargetType.BLOCK
	e1.block_id = block_id

	var e2: VoxPaletteEntry = auto_free(VoxPaletteEntry.new())
	e2.source_index = 2
	e2.target_type = VoxPaletteEntry.TargetType.SMOOTH_TERRAIN
	e2.terrain_material_id = "rock42"

	var e3: VoxPaletteEntry = auto_free(VoxPaletteEntry.new())
	e3.source_index = 3
	e3.target_type = VoxPaletteEntry.TargetType.AIR

	var e4: VoxPaletteEntry = auto_free(VoxPaletteEntry.new())
	e4.source_index = 4
	e4.target_type = VoxPaletteEntry.TargetType.IGNORE

	mapping.entries = [e1, e2, e3, e4]
	return mapping


func _create_sample_structure(mapping: VoxPaletteMapping) -> StructureDef:
	## Auxiliary: wraps the mapping into the 3x2x3 bottom-center-pivot structure the test stamps.
	var def: StructureDef = auto_free(StructureDef.new())
	def.id = "test_structure"
	def.display_name = "Test Structure"
	def.palette_mapping = mapping
	def.pivot_anchor = StructureDef.PivotAnchor.BOTTOM_CENTER
	def.custom_pivot_offset = Vector3i.ZERO
	def.bounding_box_size = Vector3i(3, 2, 3)
	return def
