class_name SuiteEditorUndoHistoryTest
extends GdUnitTestSuite

const EditorUndoHistoryClass = preload("res://tools/map_editor/editor_undo_history.gd")


func test_pop_on_empty_stack_returns_empty_dictionary() -> void:
	var history: EditorUndoHistory = auto_free(EditorUndoHistoryClass.new())
	assert_bool(history.is_empty()).is_true()
	assert_int(history.size()).is_equal(0)
	var popped: Dictionary = history.pop()
	assert_dict(popped).is_empty()


func test_push_and_pop_returns_newest_entry_first() -> void:
	var history: EditorUndoHistory = auto_free(EditorUndoHistoryClass.new())
	history.push({"type": "first", "val": 1})
	history.push({"type": "second", "val": 2})

	assert_bool(history.is_empty()).is_false()
	assert_int(history.size()).is_equal(2)

	var second: Dictionary = history.pop()
	assert_str(second.get("type", "")).is_equal("second")
	assert_int(second.get("val", 0)).is_equal(2)

	var first: Dictionary = history.pop()
	assert_str(first.get("type", "")).is_equal("first")
	assert_int(first.get("val", 0)).is_equal(1)

	assert_bool(history.is_empty()).is_true()


func test_push_beyond_max_depth_caps_size_and_drops_oldest_entry() -> void:
	var history: EditorUndoHistory = auto_free(EditorUndoHistoryClass.new())
	var total := EditorUndoHistoryClass.MAX_DEPTH + 10
	for i in range(total):
		history.push({"id": i})

	assert_int(history.size()).is_equal(EditorUndoHistoryClass.MAX_DEPTH)
	# Oldest remaining entry should be index 10 (entries 0..9 were dropped)
	assert_int(history.entries[0].get("id", -1)).is_equal(10)
	# Newest entry should be total - 1
	var newest: Dictionary = history.pop()
	assert_int(newest.get("id", -1)).is_equal(total - 1)


func test_clear_removes_all_entries() -> void:
	var history: EditorUndoHistory = auto_free(EditorUndoHistoryClass.new())
	history.push({"a": 1})
	history.push({"b": 2})
	history.clear()
	assert_bool(history.is_empty()).is_true()
	assert_int(history.size()).is_equal(0)
