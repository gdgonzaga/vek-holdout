extends GdUnitTestSuite
## Palette panel and filter/selection logic: the generic EditorPalettePanel
## helpers plus the HUD's block-palette population, selection, filtering and
## base-def-only invariants (split from suite_map_editor_test.gd, R12D).

const MapEditorClass = preload("res://tools/map_editor/map_editor.gd")
const EditorHUDClass = preload("res://tools/map_editor/editor_hud.gd")
const EditorPalettePanelClass = preload("res://tools/map_editor/editor_palette_panel.gd")
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


func test_editor_hud_block_palette_contains_only_base_defs() -> void:
	var hud: EditorHUD = auto_free(EditorHUDClass.new())
	hud.setup()

	var lib := BlockLibrary.new()
	hud.populate_block_library(lib)

	var filtered := hud.get_filtered_block_indices()
	# Should contain only base block indices (excluding rotation variants)
	assert_int(filtered.size()).is_equal(lib.get_base_indices().size())
	assert_array(filtered).contains_exactly(lib.get_base_indices())


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
