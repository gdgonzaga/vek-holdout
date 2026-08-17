class_name EditorLauncher
extends CanvasLayer
## Launcher UI overlay for selecting an existing map or creating a new map.
##
## Owned by MapEditor. Built procedurally in code.

signal map_selected(map_id: String)
signal new_map_requested(name: String, type: int)

var _backdrop: ColorRect
var _panel: PanelContainer
var _maps_container: VBoxContainer
var _new_name_input: LineEdit
var _new_type_select: OptionButton
var _error_label: Label

const TYPE_NAMES: Array[String] = ["BASE", "POI", "BUILDING", "TOWN"]


func _init() -> void:
	layer = 105
	_build_ui()


func _build_ui() -> void:
	# Full screen backdrop
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(0.04, 0.06, 0.09, 0.88)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)

	# Centered Dialog Panel
	_panel = PanelContainer.new()
	_panel.name = "LauncherPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(560, 480)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.12, 0.16, 0.95)
	panel_style.border_color = Color(0.25, 0.35, 0.5, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", panel_style)
	_backdrop.add_child(_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 14)
	_panel.add_child(main_vbox)

	# Header Title
	var title := Label.new()
	title.text = "VEK HOLDOUT — MAP EDITOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	main_vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Dual-Voxel Terrain & Structures Authoring Environment"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
	main_vbox.add_child(subtitle)

	# Section: Existing Maps
	var existing_title := Label.new()
	existing_title.text = "OPEN EXISTING MAP"
	existing_title.add_theme_font_size_override("font_size", 14)
	existing_title.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	main_vbox.add_child(existing_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 180)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)

	_maps_container = VBoxContainer.new()
	_maps_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_maps_container.add_theme_constant_override("separation", 6)
	scroll.add_child(_maps_container)

	var separator := HSeparator.new()
	main_vbox.add_child(separator)

	# Section: Create New Map
	var new_title := Label.new()
	new_title.text = "CREATE NEW MAP"
	new_title.add_theme_font_size_override("font_size", 14)
	new_title.add_theme_color_override("font_color", Color(0.7, 0.8, 0.95))
	main_vbox.add_child(new_title)

	var new_hbox := HBoxContainer.new()
	new_hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(new_hbox)

	_new_name_input = LineEdit.new()
	_new_name_input.placeholder_text = "map_id (snake_case)"
	_new_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_name_input.text_submitted.connect(func(_t: String): _on_create_pressed())
	new_hbox.add_child(_new_name_input)

	_new_type_select = OptionButton.new()
	for name in TYPE_NAMES:
		_new_type_select.add_item(name)
	_new_type_select.selected = 1 # Default POI
	new_hbox.add_child(_new_type_select)

	var create_btn := Button.new()
	create_btn.text = "Create & Open"
	create_btn.pressed.connect(_on_create_pressed)
	new_hbox.add_child(create_btn)

	_error_label = Label.new()
	_error_label.add_theme_font_size_override("font_size", 12)
	_error_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	_error_label.visible = false
	main_vbox.add_child(_error_label)


func setup(maps: Array[MapDef]) -> void:
	for child in _maps_container.get_children():
		child.queue_free()

	if maps.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No maps found in data/maps/"
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_maps_container.add_child(empty_lbl)
		return

	for def in maps:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var btn := Button.new()
		var type_str := TYPE_NAMES[def.map_type] if def.map_type >= 0 and def.map_type < TYPE_NAMES.size() else "UNKNOWN"
		btn.text = "%s (%s) — [%s]" % [def.display_name, def.id, type_str]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func(): _on_map_selected(def.id))
		row.add_child(btn)

		_maps_container.add_child(row)


func _on_map_selected(map_id: String) -> void:
	map_selected.emit(map_id)


func _on_create_pressed() -> void:
	var name_text := _new_name_input.text.strip_edges()
	if name_text.is_empty():
		_show_error("Map name cannot be empty")
		return
	if " " in name_text:
		_show_error("Map name cannot contain spaces (use snake_case)")
		return
	_error_label.visible = false
	var chosen_type := _new_type_select.selected
	new_map_requested.emit(name_text, chosen_type)


func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true


func show_launcher() -> void:
	visible = true


func hide_launcher() -> void:
	visible = false
