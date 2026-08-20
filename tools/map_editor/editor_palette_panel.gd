class_name EditorPalettePanel
extends PanelContainer
## Reusable filterable search sidebar for MapEditor placement modes (Blocks, Furniture).
##
## Provides a search LineEdit, item count indicator, ItemList with icons and tooltips,
## automatic query filtering, index-mapping to underlying models, and selection synchronization.

signal item_selected(index: int)

class Item:
	var index: int = 0
	var id: String = ""
	var display_name: String = ""
	var label: String = ""
	var icon: Texture2D = null
	var tooltip: String = ""


var _title_label: Label
var _count_label: Label
var _search_input: LineEdit
var _item_list: ItemList
var _footer_vbox: VBoxContainer
var _selected_label: Label
var _id_label: Label

var _items: Array[Item] = []
var _filtered_indices: Array[int] = [] # Maps list row -> item.index
var _selected_index: int = 0


func setup(
	title: String,
	placeholder: String,
	border_color: Color,
	title_color: Color = Color(0.85, 0.9, 0.95)
) -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 16.0
	offset_top = 16.0
	offset_right = 300.0
	offset_bottom = 440.0
	custom_minimum_size = Vector2(284, 400)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.14, 0.92)
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)

	var main_vbox := VBoxContainer.new()
	main_vbox.name = "MainVBox"
	main_vbox.add_theme_constant_override("separation", 6)
	add_child(main_vbox)

	# Header: Title + Count
	var header_hbox := HBoxContainer.new()
	header_hbox.name = "HeaderHBox"
	main_vbox.add_child(header_hbox)

	_title_label = Label.new()
	_title_label.name = "PaletteTitle"
	_title_label.text = title
	_title_label.add_theme_font_size_override("font_size", 13)
	_title_label.add_theme_color_override("font_color", title_color)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(_title_label)

	_count_label = Label.new()
	_count_label.name = "CountLabel"
	_count_label.text = "(0)"
	_count_label.add_theme_font_size_override("font_size", 11)
	_count_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_hbox.add_child(_count_label)

	# Search LineEdit
	_search_input = LineEdit.new()
	_search_input.name = "SearchInput"
	_search_input.placeholder_text = placeholder
	_search_input.clear_button_enabled = true
	_search_input.add_theme_font_size_override("font_size", 12)
	_search_input.text_changed.connect(_on_search_changed)
	main_vbox.add_child(_search_input)

	# ItemList
	_item_list = ItemList.new()
	_item_list.name = "ItemList"
	_item_list.select_mode = ItemList.SELECT_SINGLE
	_item_list.allow_reselect = true
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.item_selected.connect(_on_item_selected)
	main_vbox.add_child(_item_list)

	# Selected item summary footer
	_footer_vbox = VBoxContainer.new()
	_footer_vbox.name = "FooterVBox"
	_footer_vbox.add_theme_constant_override("separation", 2)
	main_vbox.add_child(_footer_vbox)

	_selected_label = Label.new()
	_selected_label.name = "SelectedLabel"
	_selected_label.text = "Selected: None"
	_selected_label.add_theme_font_size_override("font_size", 12)
	_selected_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	_footer_vbox.add_child(_selected_label)

	_id_label = Label.new()
	_id_label.name = "IdLabel"
	_id_label.text = "ID: -"
	_id_label.add_theme_font_size_override("font_size", 11)
	_id_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	_footer_vbox.add_child(_id_label)


func populate(items: Array[Item], selected_idx: int = 0) -> void:
	_items = items
	_selected_index = selected_idx
	var current_query := _search_input.text if _search_input != null else ""
	_filter_items(current_query)


func _on_search_changed(new_text: String) -> void:
	_filter_items(new_text)


func _filter_items(query: String) -> void:
	if _item_list == null:
		return
	_item_list.clear()
	_item_list.fixed_icon_size =  Vector2i(64, 64)
	_filtered_indices.clear()

	var q := query.strip_edges().to_lower()
	for item in _items:
		if item == null:
			continue
		var dname := item.display_name if not item.display_name.is_empty() else item.id
		var matches := q.is_empty() or dname.to_lower().contains(q) or item.id.to_lower().contains(q)
		if matches:
			_filtered_indices.append(item.index)
			var display_text := item.label if not item.label.is_empty() else dname
			var list_idx := _item_list.add_item(display_text, item.icon)
			if not item.tooltip.is_empty():
				_item_list.set_item_tooltip(list_idx, item.tooltip)

	if _count_label != null:
		_count_label.text = "(%d/%d)" % [_filtered_indices.size(), _items.size()]

	# Re-select active item if present in filtered list, or pick first match
	var found_selected_idx := _filtered_indices.find(_selected_index)
	if found_selected_idx != -1:
		_item_list.select(found_selected_idx)
		_item_list.ensure_current_is_visible()
	elif not _filtered_indices.is_empty():
		_selected_index = _filtered_indices[0]
		_item_list.select(0)
		_item_list.ensure_current_is_visible()
		item_selected.emit(_selected_index)


func _on_item_selected(list_idx: int) -> void:
	if list_idx >= 0 and list_idx < _filtered_indices.size():
		var global_idx := _filtered_indices[list_idx]
		_selected_index = global_idx
		item_selected.emit(global_idx)


func select_by_index(global_idx: int) -> void:
	_selected_index = global_idx
	if _item_list == null:
		return
	var found_list_idx := _filtered_indices.find(global_idx)
	if found_list_idx != -1:
		_item_list.select(found_list_idx)
		_item_list.ensure_current_is_visible()
	else:
		_item_list.deselect_all()


func get_filtered_indices() -> Array[int]:
	return _filtered_indices


func is_search_focused() -> bool:
	return _search_input != null and _search_input.has_focus()


func unfocus_search() -> void:
	if _search_input != null and _search_input.has_focus():
		_search_input.release_focus()


func get_footer_vbox() -> VBoxContainer:
	return _footer_vbox


func set_selected_info(name: String, id_str: String = "") -> void:
	if _selected_label != null:
		_selected_label.text = "Selected: " + name
	if _id_label != null:
		if not id_str.is_empty():
			_id_label.text = "ID: " + id_str
			_id_label.visible = true
		else:
			_id_label.visible = false
