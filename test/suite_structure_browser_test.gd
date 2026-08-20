class_name SuiteStructureBrowserTest
extends GdUnitTestSuite

const StructureBrowserClass = preload("res://tools/map_editor/structure_browser.gd")
const StructureToolClass = preload("res://tools/map_editor/structure_tool.gd")
const EditorHUDClass = preload("res://tools/map_editor/editor_hud.gd")
const MapEditorClass = preload("res://tools/map_editor/map_editor.gd")


func _create_sample_structure(id_name: String, cat: String, size_vec: Vector3i) -> StructureDef:
	var def: StructureDef = auto_free(StructureDef.new())
	def.id = id_name
	def.display_name = id_name.capitalize()
	def.category = cat
	def.vox_file_path = "res://data/structures/vox/" + id_name + ".vox"
	def.pivot_anchor = StructureDef.PivotAnchor.BOTTOM_CENTER
	def.bounding_box_size = size_vec
	return def


func test_structure_browser_setup_and_empty_state() -> void:
	var browser: StructureBrowserClass = auto_free(StructureBrowserClass.new())
	browser.setup()

	assert_object(browser._title_label).is_not_null()
	assert_str(browser._title_label.text).is_equal("Structures")
	assert_str(browser._count_label.text).is_equal("(0)")
	assert_object(browser.get_selected_structure()).is_null()
	assert_int(browser.get_selected_index()).is_equal(0)
	assert_array(browser.get_filtered_indices()).is_empty()


func test_structure_browser_populate_and_selection() -> void:
	var browser: StructureBrowserClass = auto_free(StructureBrowserClass.new())
	browser.setup()

	var s1: StructureDef = _create_sample_structure("watchtower", "Buildings", Vector3i(6, 12, 6))
	var s2: StructureDef = _create_sample_structure("stone_ruin", "Ruins", Vector3i(10, 4, 10))
	var s3: StructureDef = _create_sample_structure("wooden_shack", "Buildings", Vector3i(8, 6, 8))

	var list: Array[StructureDef] = [s1, s2, s3]
	browser.populate(list, 1)

	assert_str(browser._count_label.text).is_equal("(3/3)")
	assert_int(browser.get_selected_index()).is_equal(1)
	assert_object(browser.get_selected_structure()).is_equal(s2)
	assert_str(browser._selected_label.text).contains("Stone Ruin")
	assert_str(browser._category_label.text).contains("Ruins")
	assert_str(browser._dims_label.text).contains("10x4x10")

	# Select by index
	browser.select_by_index(0)
	assert_int(browser.get_selected_index()).is_equal(0)
	assert_object(browser.get_selected_structure()).is_equal(s1)

	# Select by def
	browser.select_by_def(s3)
	assert_int(browser.get_selected_index()).is_equal(2)
	assert_object(browser.get_selected_structure()).is_equal(s3)


func test_structure_browser_populate_list_dictionary() -> void:
	var browser: StructureBrowserClass = auto_free(StructureBrowserClass.new())
	browser.setup()

	var s1: StructureDef = _create_sample_structure("cottage", "Housing", Vector3i(8, 6, 8))
	var s2: StructureDef = _create_sample_structure("barracks", "Military", Vector3i(12, 8, 12))

	var dict: Dictionary = {
		"Housing": [s1],
		"Military": [s2]
	}
	browser.populate_list(dict)

	assert_str(browser._count_label.text).is_equal("(2/2)")
	assert_int(browser.get_filtered_indices().size()).is_equal(2)
	assert_object(browser.get_selected_structure()).is_equal(s1)


func test_structure_browser_category_filtering() -> void:
	var browser: StructureBrowserClass = auto_free(StructureBrowserClass.new())
	browser.setup()

	var s1: StructureDef = _create_sample_structure("watchtower", "Buildings", Vector3i(6, 12, 6))
	var s2: StructureDef = _create_sample_structure("stone_ruin", "Ruins", Vector3i(10, 4, 10))
	var s3: StructureDef = _create_sample_structure("wooden_shack", "Buildings", Vector3i(8, 6, 8))

	browser.populate([s1, s2, s3])

	# Filter by "Buildings"
	var buildings_idx: int = browser._categories.find("Buildings")
	assert_bool(buildings_idx != -1).is_true()
	browser._on_category_selected(buildings_idx)

	assert_str(browser._count_label.text).is_equal("(2/3)")
	var filtered: Array[int] = browser.get_filtered_indices()
	assert_int(filtered.size()).is_equal(2)
	assert_int(filtered[0]).is_equal(0)
	assert_int(filtered[1]).is_equal(2)

	# Filter by "Ruins"
	var ruins_idx: int = browser._categories.find("Ruins")
	browser._on_category_selected(ruins_idx)
	assert_str(browser._count_label.text).is_equal("(1/3)")
	assert_int(browser.get_filtered_indices().size()).is_equal(1)
	assert_int(browser.get_filtered_indices()[0]).is_equal(1)

	# Reset to "All Categories"
	browser._on_category_selected(0)
	assert_str(browser._count_label.text).is_equal("(3/3)")


func test_structure_browser_search_filtering() -> void:
	var browser: StructureBrowserClass = auto_free(StructureBrowserClass.new())
	browser.setup()

	var s1: StructureDef = _create_sample_structure("watchtower", "Buildings", Vector3i(6, 12, 6))
	var s2: StructureDef = _create_sample_structure("stone_ruin", "Ruins", Vector3i(10, 4, 10))
	var s3: StructureDef = _create_sample_structure("wooden_shack", "Buildings", Vector3i(8, 6, 8))

	browser.populate([s1, s2, s3])

	# Search "shack"
	browser._on_search_changed("shack")
	assert_str(browser._count_label.text).is_equal("(1/3)")
	assert_int(browser.get_filtered_indices().size()).is_equal(1)
	assert_int(browser.get_filtered_indices()[0]).is_equal(2)

	# Search "wood"
	browser._on_search_changed("wood")
	assert_str(browser._count_label.text).is_equal("(1/3)")

	# Clear search
	browser._on_search_changed("")
	assert_str(browser._count_label.text).is_equal("(3/3)")


func test_structure_browser_signals() -> void:
	var browser: StructureBrowserClass = auto_free(StructureBrowserClass.new())
	browser.setup()

	var s1: StructureDef = _create_sample_structure("watchtower", "Buildings", Vector3i(6, 12, 6))
	var s2: StructureDef = _create_sample_structure("stone_ruin", "Ruins", Vector3i(10, 4, 10))
	browser.populate([s1, s2])

	var selected_defs: Array[StructureDef] = []
	var selected_indices: Array[int] = []
	browser.structure_selected.connect(func(def: StructureDef) -> void: selected_defs.append(def))
	browser.item_selected.connect(func(idx: int) -> void: selected_indices.append(idx))

	browser._on_item_selected(1)
	assert_int(selected_indices.size()).is_equal(1)
	assert_int(selected_indices[0]).is_equal(1)
	assert_int(selected_defs.size()).is_equal(1)
	assert_object(selected_defs[0]).is_equal(s2)


func test_structure_tool_lifecycle_and_transforms() -> void:
	var tool: StructureToolClass = auto_free(StructureToolClass.new())

	assert_bool(tool.is_active).is_false()
	tool.activate()
	assert_bool(tool.is_active).is_true()

	var s1: StructureDef = _create_sample_structure("fortress", "Defenses", Vector3i(16, 10, 16))
	tool.set_active_structure(s1)
	assert_object(tool.get_active_structure()).is_equal(s1)

	# Rotation
	assert_int(tool.current_rotation).is_equal(0)
	tool.rotate_clockwise()
	assert_int(tool.current_rotation).is_equal(1)
	tool.rotate_clockwise()
	assert_int(tool.current_rotation).is_equal(2)
	tool.rotate_counter_clockwise()
	assert_int(tool.current_rotation).is_equal(1)

	# Y-offset
	assert_int(tool.current_y_offset).is_equal(0)
	tool.adjust_y_offset(2)
	assert_int(tool.current_y_offset).is_equal(2)
	tool.adjust_y_offset(-5)
	assert_int(tool.current_y_offset).is_equal(-3)

	# Nudge
	assert_vector(tool.current_nudge).is_equal(Vector3i.ZERO)
	tool.nudge(Vector3i(1, 0, -2))
	assert_vector(tool.current_nudge).is_equal(Vector3i(1, 0, -2))

	# Placement origin calculation
	var base_pos: Vector3i = Vector3i(10, 20, 30)
	var origin: Vector3i = tool.get_placement_origin(base_pos)
	# base (10, 20, 30) + nudge (1, 0, -2) + y_offset (-3) = (11, 17, 28)
	assert_vector(origin).is_equal(Vector3i(11, 17, 28))

	# Pivot offset
	var pivot: Vector3i = tool.calculate_pivot_offset()
	# BOTTOM_CENTER for 16x10x16 -> (8, 0, 8)
	assert_vector(pivot).is_equal(Vector3i(8, 0, 8))

	# Reset
	tool.reset_transform()
	assert_int(tool.current_rotation).is_equal(0)
	assert_int(tool.current_y_offset).is_equal(0)
	assert_vector(tool.current_nudge).is_equal(Vector3i.ZERO)

	tool.deactivate()
	assert_bool(tool.is_active).is_false()


func test_editor_hud_structure_mode_and_info() -> void:
	var hud: EditorHUDClass = auto_free(EditorHUDClass.new())
	hud.setup()

	# Mode 5 is STRUCTURE
	hud.set_mode(5)
	assert_str(hud._mode_label.text).contains("STRUCTURE")
	assert_bool(hud._structure_browser.visible).is_true()
	assert_bool(hud._block_palette.visible).is_false()
	assert_bool(hud._furniture_palette.visible).is_false()

	var s1: StructureDef = _create_sample_structure("tower", "Buildings", Vector3i(6, 12, 6))
	hud.populate_structure_list([s1], 0)
	assert_int(hud.get_filtered_structure_indices().size()).is_equal(1)

	hud.set_structure_info(s1)
	assert_str(hud._structure_browser._selected_label.text).contains("Tower")

func test_map_editor_structure_mode_and_cycling() -> void:
	var editor: MapEditorClass = auto_free(MapEditorClass.new())
	add_child(editor)

	var s1: StructureDef = _create_sample_structure("tower", "Buildings", Vector3i(6, 12, 6))
	var s2: StructureDef = _create_sample_structure("wall", "Defenses", Vector3i(4, 3, 1))
	editor._structure_defs = [s1, s2]
	editor._selected_structure_idx = 0

	# Switch to STRUCTURE mode (Mode.STRUCTURE = 5)
	editor._set_mode(MapEditorClass.Mode.STRUCTURE)
	assert_int(editor._mode).is_equal(MapEditorClass.Mode.STRUCTURE)
	assert_bool(editor._structure_tool.is_active).is_true()
	assert_object(editor._structure_tool.get_active_structure()).is_equal(s1)

	# Cycle structure forward
	editor._cycle_structure(1)
	assert_int(editor._selected_structure_idx).is_equal(1)
	assert_object(editor._structure_tool.get_active_structure()).is_equal(s2)

	# Cycle structure backward
	editor._cycle_structure(-1)
	assert_int(editor._selected_structure_idx).is_equal(0)
	assert_object(editor._structure_tool.get_active_structure()).is_equal(s1)

	# Switch away from STRUCTURE mode
	editor._set_mode(MapEditorClass.Mode.NAVIGATE)
	assert_bool(editor._structure_tool.is_active).is_false()
