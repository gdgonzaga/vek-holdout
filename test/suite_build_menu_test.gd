## Test suite for BuildMenu fuzzy search filtering and UI interaction.
extends GdUnitTestSuite

const _BuildMenuScene := preload("res://ui/build_menu/build_menu.tscn")


func test_fuzzy_match_score_scenarios() -> void:
	# 1. Exact match
	assert_int(BuildMenu.fuzzy_match_score("wood", "wood")).is_equal(1000)

	# 2. Prefix match (case-insensitive)
	var prefix_score: int = BuildMenu.fuzzy_match_score("wood", "Wood Wall")
	assert_int(prefix_score).is_greater(800)

	# 3. Contiguous substring match
	var sub_score: int = BuildMenu.fuzzy_match_score("wall", "Wood Wall")
	assert_int(sub_score).is_greater(500)

	# 4. Fuzzy subsequence match (w...l...l)
	var subseq_score: int = BuildMenu.fuzzy_match_score("wll", "Wood Wall")
	assert_int(subseq_score).is_greater(0)

	# 5. Non-match
	assert_int(BuildMenu.fuzzy_match_score("xyz", "Wood Wall")).is_equal(0)


func test_build_menu_populate_and_filter() -> void:
	var menu: BuildMenu = auto_free(_BuildMenuScene.instantiate()) as BuildMenu
	add_child(menu)
	menu.populate()

	var list: VBoxContainer = menu.get_node("%List") as VBoxContainer
	assert_object(list).is_not_null()

	var total_count: int = list.get_child_count()
	assert_int(total_count).is_greater(0)

	# Search for "deconstruct" (matches Deconstruct tool precisely)
	menu.filter_entries("deconstruct")
	var visible_count: int = 0
	var top_visible_id: String = ""
	for child in list.get_children():
		if child is BuildMenuEntry and (child as BuildMenuEntry).visible:
			visible_count += 1
			if top_visible_id.is_empty():
				top_visible_id = (child as BuildMenuEntry).entry_id

	assert_int(visible_count).is_equal(1)
	assert_str(top_visible_id).is_equal(BuildLibrary.DECONSTRUCT_ID)

	# Clear search filter
	menu.filter_entries("")
	var restored_count: int = 0
	for child in list.get_children():
		if child is BuildMenuEntry and (child as BuildMenuEntry).visible:
			restored_count += 1

	assert_int(restored_count).is_equal(total_count)


func test_build_menu_text_submitted_emits_selection() -> void:
	var menu: BuildMenu = auto_free(_BuildMenuScene.instantiate()) as BuildMenu
	add_child(menu)
	menu.populate()

	var selected_ids: Array[String] = []
	var cb := func(id: String) -> void:
		selected_ids.append(id)
	EventBus.buildable_selected.connect(cb)

	menu.filter_entries("deconstruct")
	menu._on_search_text_submitted("deconstruct")

	EventBus.buildable_selected.disconnect(cb)

	assert_int(selected_ids.size()).is_equal(1)
	assert_str(selected_ids[0]).is_equal(BuildLibrary.DECONSTRUCT_ID)
