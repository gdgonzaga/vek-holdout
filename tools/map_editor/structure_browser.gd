class_name StructureBrowser
extends PanelContainer
## Reusable filterable sidebar panel for MapEditor structure stamp mode.
##
## Displays category filter dropdown, search input, item count,
## ItemList with icons and tooltips, footer metadata summary,
## and selection synchronization.

signal structure_selected(def: StructureDef)
signal item_selected(index: int)

class StructureItem:
	var index: int = 0
	var def: StructureDef = null
	var id: String = ""
	var display_name: String = ""
	var category: String = "General"
	var label: String = ""
	var tooltip: String = ""
	var icon: Texture2D = null


var _title_label: Label
var _count_label: Label
var _category_option: OptionButton
var _search_input: LineEdit
var _item_list: ItemList
var _footer_vbox: VBoxContainer
var _selected_label: Label
var _id_label: Label
var _category_label: Label
var _dims_label: Label
var _pivot_label: Label

var _items: Array[StructureItem] = []
var _structures: Array[StructureDef] = []
var _filtered_indices: Array[int] = [] # Maps list row -> StructureItem.index
var _selected_index: int = 0
var _categories: Array[String] = ["All Categories"]
var _selected_category: String = "All Categories"


func setup(
	title: String = "Structures",
	placeholder: String = "Search structures...",
	border_color: Color = Color(0.65, 0.4, 0.85, 0.9),
	title_color: Color = Color(0.9, 0.85, 0.98)
) -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = 16.0
	offset_top = 16.0
	offset_right = 300.0
	offset_bottom = 470.0
	custom_minimum_size = Vector2(284, 440)
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
	_title_label.name = "StructureTitle"
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

	# Category OptionButton
	_category_option = OptionButton.new()
	_category_option.name = "CategoryOption"
	_category_option.add_theme_font_size_override("font_size", 11)
	_category_option.item_selected.connect(_on_category_selected)
	main_vbox.add_child(_category_option)

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
	_item_list.focus_mode = Control.FOCUS_NONE
	_item_list.select_mode = ItemList.SELECT_SINGLE
	_item_list.allow_reselect = true
	_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_item_list.item_selected.connect(_on_item_selected)
	main_vbox.add_child(_item_list)

	# Footer Summary
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

	_category_label = Label.new()
	_category_label.name = "CategoryLabel"
	_category_label.text = "Category: -"
	_category_label.add_theme_font_size_override("font_size", 11)
	_category_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	_footer_vbox.add_child(_category_label)

	_dims_label = Label.new()
	_dims_label.name = "DimsLabel"
	_dims_label.text = "Dimensions: -"
	_dims_label.add_theme_font_size_override("font_size", 11)
	_dims_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	_footer_vbox.add_child(_dims_label)

	_pivot_label = Label.new()
	_pivot_label.name = "PivotLabel"
	_pivot_label.text = "Pivot: -"
	_pivot_label.add_theme_font_size_override("font_size", 11)
	_pivot_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	_footer_vbox.add_child(_pivot_label)


func populate(structures: Array[StructureDef], selected_idx: int = 0) -> void:
	_structures = structures
	_items.clear()
	_categories = ["All Categories"]

	for i in range(structures.size()):
		var def := structures[i]
		if def == null:
			continue
		var item := StructureItem.new()
		item.index = i
		item.def = def
		item.id = def.id
		item.display_name = def.display_name if not def.display_name.is_empty() else def.id
		item.category = def.category if not def.category.is_empty() else "General"
		item.label = "%s [%s]" % [item.display_name, item.category] if not item.category.is_empty() else item.display_name
		item.tooltip = "ID: %s\nCategory: %s\nSize: %dx%dx%d\nFile: %s" % [
			def.id,
			item.category,
			def.bounding_box_size.x,
			def.bounding_box_size.y,
			def.bounding_box_size.z,
			def.vox_file_path
		]
		_items.append(item)

		if not _categories.has(item.category):
			_categories.append(item.category)

	_update_category_options()
	_selected_index = selected_idx
	var current_query := _search_input.text if _search_input != null else ""
	_filter_items(current_query)


func populate_list(categories: Dictionary) -> void:
	var flat_defs: Array[StructureDef] = []
	for cat_name: String in categories.keys():
		var cat_val: Variant = categories[cat_name]
		if cat_val is Array:
			for item: Variant in (cat_val as Array):
				if item is StructureDef:
					var sdef := item as StructureDef
					if sdef.category.is_empty():
						sdef.category = cat_name
					flat_defs.append(sdef)
	populate(flat_defs, 0)


func _update_category_options() -> void:
	if _category_option == null:
		return
	_category_option.clear()
	for i in range(_categories.size()):
		_category_option.add_item(_categories[i], i)
	var cat_idx := _categories.find(_selected_category)
	if cat_idx != -1:
		_category_option.select(cat_idx)
	else:
		_selected_category = "All Categories"
		_category_option.select(0)


func _on_category_selected(index: int) -> void:
	if index >= 0 and index < _categories.size():
		_selected_category = _categories[index]
		var query := _search_input.text if _search_input != null else ""
		_filter_items(query)


func _on_search_changed(new_text: String) -> void:
	_filter_items(new_text)


func _filter_items(query: String) -> void:
	if _item_list == null:
		return
	_item_list.clear()
	_filtered_indices.clear()

	var q := query.strip_edges().to_lower()
	for item in _items:
		if item == null:
			continue
		var cat_matches := (_selected_category == "All Categories") or (item.category == _selected_category)
		if not cat_matches:
			continue
		var dname := item.display_name if not item.display_name.is_empty() else item.id
		var matches := q.is_empty() or dname.to_lower().contains(q) or item.id.to_lower().contains(q) or item.category.to_lower().contains(q)
		if matches:
			_filtered_indices.append(item.index)
			var display_text := item.label if not item.label.is_empty() else dname
			var list_idx := _item_list.add_item(display_text, item.icon)
			if not item.tooltip.is_empty():
				_item_list.set_item_tooltip(list_idx, item.tooltip)

	if _count_label != null:
		_count_label.text = "(%d/%d)" % [_filtered_indices.size(), _items.size()]

	var found_selected_idx := _filtered_indices.find(_selected_index)
	if found_selected_idx != -1:
		_item_list.select(found_selected_idx)
		_item_list.ensure_current_is_visible()
		_update_footer_for_index(_selected_index)
	elif not _filtered_indices.is_empty():
		_selected_index = _filtered_indices[0]
		_item_list.select(0)
		_item_list.ensure_current_is_visible()
		_update_footer_for_index(_selected_index)
		item_selected.emit(_selected_index)
		if _selected_index >= 0 and _selected_index < _structures.size():
			structure_selected.emit(_structures[_selected_index])
	else:
		set_selected_info(null)


func _on_item_selected(list_idx: int) -> void:
	if list_idx >= 0 and list_idx < _filtered_indices.size():
		var global_idx := _filtered_indices[list_idx]
		_selected_index = global_idx
		_update_footer_for_index(_selected_index)
		item_selected.emit(global_idx)
		if global_idx >= 0 and global_idx < _structures.size():
			structure_selected.emit(_structures[global_idx])


func _update_footer_for_index(idx: int) -> void:
	if idx >= 0 and idx < _structures.size():
		set_selected_info(_structures[idx])
	else:
		set_selected_info(null)


func select_by_index(global_idx: int) -> void:
	_selected_index = global_idx
	if _item_list == null:
		return
	var found_list_idx := _filtered_indices.find(global_idx)
	if found_list_idx != -1:
		_item_list.select(found_list_idx)
		_item_list.ensure_current_is_visible()
		_update_footer_for_index(global_idx)
	else:
		_item_list.deselect_all()


func select_by_def(def: StructureDef) -> void:
	if def == null:
		return
	for i in range(_structures.size()):
		if _structures[i] == def or _structures[i].id == def.id:
			select_by_index(i)
			return


func get_selected_structure() -> StructureDef:
	if _selected_index >= 0 and _selected_index < _structures.size():
		return _structures[_selected_index]
	return null


func get_selected_index() -> int:
	return _selected_index


func get_filtered_indices() -> Array[int]:
	return _filtered_indices


func is_search_focused() -> bool:
	return _search_input != null and _search_input.has_focus()


func unfocus_search() -> void:
	if _search_input != null and _search_input.has_focus():
		_search_input.release_focus()


func get_footer_vbox() -> VBoxContainer:
	return _footer_vbox


func set_selected_info(def: StructureDef) -> void:
	if def == null:
		if _selected_label != null:
			_selected_label.text = "Selected: None"
		if _id_label != null:
			_id_label.text = "ID: -"
		if _category_label != null:
			_category_label.text = "Category: -"
		if _dims_label != null:
			_dims_label.text = "Dimensions: -"
		if _pivot_label != null:
			_pivot_label.text = "Pivot: -"
		return

	if _selected_label != null:
		var name_str := def.display_name if not def.display_name.is_empty() else def.id
		_selected_label.text = "Selected: " + name_str
	if _id_label != null:
		_id_label.text = "ID: " + def.id
	if _category_label != null:
		_category_label.text = "Category: " + (def.category if not def.category.is_empty() else "General")
	if _dims_label != null:
		_dims_label.text = "Dimensions: %dx%dx%d" % [
			def.bounding_box_size.x,
			def.bounding_box_size.y,
			def.bounding_box_size.z
		]
	if _pivot_label != null:
		var anchor_name: String = "BOTTOM_CENTER"
		match def.pivot_anchor:
			StructureDef.PivotAnchor.BOTTOM_CENTER:
				anchor_name = "BOTTOM_CENTER"
			StructureDef.PivotAnchor.BOTTOM_CORNER:
				anchor_name = "BOTTOM_CORNER"
			StructureDef.PivotAnchor.GEOMETRIC_CENTER:
				anchor_name = "GEOMETRIC_CENTER"
			StructureDef.PivotAnchor.CUSTOM:
				anchor_name = "CUSTOM"
		_pivot_label.text = "Pivot: " + anchor_name
