extends GdUnitTestSuite

## RowFocus (ui/shared/row_focus): keeps keyboard focus on "the same button of the same
## row" when a list is torn down and rebuilt, so Tab / Enter flows survive every refresh.
## Pure UI plumbing, no game content.

var _list: VBoxContainer


func before_test() -> void:
	_list = auto_free(VBoxContainer.new()) as VBoxContainer
	add_child(_list)


func _fill(keys: Array[String], disabled_button: String = "") -> void:
	## Replaces the list's rows with one row per key, each holding a One and an All button.
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.free()
	for key: String in keys:
		var row := HBoxContainer.new()
		row.set_meta(RowFocus.KEY_META, key)
		for button_name: String in ["OneButton", "AllButton"]:
			var button := Button.new()
			button.name = button_name
			button.disabled = (key == disabled_button and button_name == "OneButton")
			row.add_child(button)
		_list.add_child(row)


func _button(row_index: int, button_name: String) -> Button:
	return _list.get_child(row_index).find_child(button_name, true, false) as Button


func _focus_owner() -> Control:
	return get_viewport().gui_get_focus_owner()


func test_capture_is_empty_when_focus_is_outside_the_list() -> void:
	_fill(["a", "b"])
	assert_bool(RowFocus.capture(_list).is_empty()).is_true()


func test_focus_returns_to_the_same_button_of_the_same_row_after_a_rebuild() -> void:
	# Break caught: rebuilding the rows drops focus, so a keyboard user must re-Tab after every click.
	_fill(["a", "b", "c"])
	_button(1, "AllButton").grab_focus()
	var token := RowFocus.capture(_list)

	_fill(["a", "b", "c"])
	RowFocus.restore(_list, token)

	assert_object(_focus_owner()).is_same(_button(1, "AllButton"))


func test_focus_follows_the_row_key_when_rows_reorder() -> void:
	_fill(["a", "b", "c"])
	_button(2, "OneButton").grab_focus()
	var token := RowFocus.capture(_list)

	_fill(["c", "a", "b"])
	RowFocus.restore(_list, token)

	assert_object(_focus_owner()).is_same(_button(0, "OneButton"))


func test_focus_moves_to_the_row_now_at_that_position_when_its_row_is_gone() -> void:
	_fill(["a", "b", "c"])
	_button(1, "OneButton").grab_focus()
	var token := RowFocus.capture(_list)

	_fill(["a", "c"])  # "b" moved away entirely; "c" now sits at index 1
	RowFocus.restore(_list, token)

	assert_object(_focus_owner()).is_same(_button(1, "OneButton"))


func test_focus_falls_back_to_the_last_row_when_the_tail_row_is_gone() -> void:
	_fill(["a", "b"])
	_button(1, "OneButton").grab_focus()
	var token := RowFocus.capture(_list)

	_fill(["a"])
	RowFocus.restore(_list, token)

	assert_object(_focus_owner()).is_same(_button(0, "OneButton"))


func test_focus_skips_a_button_that_became_disabled() -> void:
	_fill(["a", "b"])
	_button(0, "OneButton").grab_focus()
	var token := RowFocus.capture(_list)

	_fill(["a", "b"], "a")  # "a"'s OneButton is now disabled
	RowFocus.restore(_list, token)

	assert_object(_focus_owner()).is_same(_button(0, "AllButton"))


func test_restore_with_an_empty_token_leaves_focus_alone() -> void:
	_fill(["a"])
	var elsewhere := auto_free(Button.new()) as Button
	add_child(elsewhere)
	elsewhere.grab_focus()

	RowFocus.restore(_list, {})

	assert_object(_focus_owner()).is_same(elsewhere)
