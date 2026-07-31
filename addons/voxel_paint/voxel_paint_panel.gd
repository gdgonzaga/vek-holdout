@tool
extends PanelContainer
## Side panel for the Voxel Paint EditorPlugin. Provides block selection, brush
## radius, paint/erase mode toggle, and stream (database) management.
##
## Created by voxel_paint_plugin.gd and added to CONTAINER_SPATIAL_EDITOR_SIDE_LEFT.
## Holds a reference back to the plugin to push state changes and read stream info.

var _plugin: EditorPlugin  # set by the plugin after instantiation

# --- Controls (populated in _ready) ----------------------------

var _mode_paint: Button
var _mode_erase: Button
var _block_select: OptionButton
var _radius_slider: HSlider
var _radius_label: Label
var _info_label: Label

# Stream section.
var _stream_label: Label
var _stream_auto_btn: Button
var _stream_pick_btn: Button
var _file_dialog: FileDialog


func _ready() -> void:
	_build_ui()
	_populate_blocks()
	refresh_stream_label()


func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin


# --- Block index -----------------------------------------------------------

func get_current_index() -> int:
	var sel := _block_select.selected
	if sel < 0:
		return 1
	return _block_select.get_item_metadata(sel)


func set_erase_mode(active: bool) -> void:
	_mode_paint.button_pressed = not active
	_mode_erase.button_pressed = active


func get_erase_mode() -> bool:
	return _mode_erase.button_pressed


func get_brush_radius() -> float:
	return _radius_slider.value


# --- Stream label refresh --------------------------------------------------

## Updates the stream path label to reflect the current terrain stream state.
## Called after auto/pick and after the plugin assigns a stream.
func refresh_stream_label() -> void:
	if _plugin == null:
		return
	var path: String = _plugin.get_stream_path()
	if path.is_empty():
		_stream_label.text = "No database — edits won't persist"
		_stream_label.add_theme_color_override("font_color", Color(1, 0.5, 0.3))
	else:
		_stream_label.text = path
		_stream_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))


# --- Private ----------------------------------------------------------------

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	# -- Mode toggle --
	var mode_box := HBoxContainer.new()
	_mode_paint = Button.new()
	_mode_paint.text = "Paint"
	_mode_paint.toggle_mode = true
	_mode_paint.button_pressed = true
	_mode_paint.tooltip_text = "Left-click paints blocks"
	_mode_erase = Button.new()
	_mode_erase.text = "Erase"
	_mode_erase.toggle_mode = true
	_mode_erase.tooltip_text = "Left-click erases blocks (paints air)"
	_mode_paint.toggled.connect(_on_paint_toggled)
	_mode_erase.toggled.connect(_on_erase_toggled)
	mode_box.add_child(_mode_paint)
	mode_box.add_child(_mode_erase)

	# -- Block selector --
	var block_label := Label.new()
	block_label.text = "Block:"
	_block_select = OptionButton.new()
	_block_select.tooltip_text = "Voxel type to paint"
	_block_select.item_selected.connect(_on_block_selected)

	# -- Brush radius --
	var radius_label_head := Label.new()
	radius_label_head.text = "Brush Radius:"
	_radius_slider = HSlider.new()
	_radius_slider.min_value = 0.5
	_radius_slider.max_value = 5.0
	_radius_slider.step = 0.5
	_radius_slider.value = 2.0
	_radius_slider.custom_minimum_size.x = 100
	_radius_slider.tooltip_text = "Sphere brush radius in voxels"
	_radius_label = Label.new()
	_radius_label.text = "2.0"
	_radius_slider.value_changed.connect(_on_radius_changed)

	var radius_row := HBoxContainer.new()
	radius_row.add_child(_radius_slider)
	radius_row.add_child(_radius_label)

	# -- Info --
	_info_label = Label.new()
	_info_label.text = "LMB: paint | Shift+LMB: erase"
	_info_label.add_theme_font_size_override("font_size", 11)

	# -- Stream section --
	var stream_head := Label.new()
	stream_head.text = "Database:"
	_stream_label = Label.new()
	_stream_label.text = "No database — edits won't persist"
	_stream_label.add_theme_color_override("font_color", Color(1, 0.5, 0.3))
	_stream_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var stream_btn_row := HBoxContainer.new()
	_stream_auto_btn = Button.new()
	_stream_auto_btn.text = "Auto"
	_stream_auto_btn.tooltip_text = "Create database alongside the scene file (.tscn → .sqlite)"
	_stream_auto_btn.pressed.connect(_on_auto_stream)
	_stream_pick_btn = Button.new()
	_stream_pick_btn.text = "Pick..."
	_stream_pick_btn.tooltip_text = "Choose an existing .sqlite file"
	_stream_pick_btn.pressed.connect(_on_pick_stream)
	stream_btn_row.add_child(_stream_auto_btn)
	stream_btn_row.add_child(_stream_pick_btn)

	# -- File dialog (for Pick) --
	_file_dialog = FileDialog.new()
	_file_dialog.title = "Select SQLite Database"
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.filters = PackedStringArray(["*.sqlite ; SQLite Database"])
	_file_dialog.file_selected.connect(_on_file_selected)
	_file_dialog.min_size = Vector2i(500, 400)

	# Assemble.
	vbox.add_child(mode_box)
	vbox.add_child(HSeparator.new())
	vbox.add_child(block_label)
	vbox.add_child(_block_select)
	vbox.add_child(HSeparator.new())
	vbox.add_child(radius_label_head)
	vbox.add_child(radius_row)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_info_label)
	vbox.add_child(HSeparator.new())
	vbox.add_child(stream_head)
	vbox.add_child(_stream_label)
	vbox.add_child(stream_btn_row)

	add_child(vbox)
	add_child(_file_dialog)


func _populate_blocks() -> void:
	var lib: VoxelBlockyLibrary = load("res://data/blocks/voxel_library.tres") as VoxelBlockyLibrary
	if lib == null:
		push_warning("VoxelPaintPanel: could not load voxel_library.tres")
		return
	var block_names := {
		1: "terrain",
		2: "metal",
		3: "reinforced",
		4: "scrap",
		5: "stone",
		6: "wood",
	}
	_block_select.clear()
	var idx := 0
	for lib_idx in range(1, 7):
		var name: String = block_names.get(lib_idx, "block_%d" % lib_idx)
		_block_select.add_item(name.capitalize())
		_block_select.set_item_metadata(idx, lib_idx)
		idx += 1
	_block_select.selected = 5  # default: wood


func _on_paint_toggled(pressed: bool) -> void:
	if pressed:
		_mode_erase.button_pressed = false


func _on_erase_toggled(pressed: bool) -> void:
	if pressed:
		_mode_paint.button_pressed = false


func _on_block_selected(_index: int) -> void:
	pass


func _on_radius_changed(value: float) -> void:
	_radius_label.text = "%.1f" % value


func _on_auto_stream() -> void:
	if _plugin == null:
		return
	var path: String = _plugin.auto_create_stream()
	if not path.is_empty():
		refresh_stream_label()


func _on_pick_stream() -> void:
	_file_dialog.popup_centered()


func _on_file_selected(path: String) -> void:
	if _plugin == null:
		return
	_plugin.set_stream(path)
	refresh_stream_label()
