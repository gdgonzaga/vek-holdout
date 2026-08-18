class_name EditorLauncher
extends CanvasLayer
## Launcher UI overlay for selecting an existing map or creating a new map.
##
## Owned by MapEditor. Built procedurally in code.

signal map_selected(map_id: String)

## Emitted when the user presses the delete button next to a map in the
## existing-maps list. MapEditor shows a confirmation dialog before removing
## the map directory.
signal map_delete_requested(map_id: String)

## Create-request payload — a Dictionary (not a class) so a future blocky-image
## authoring key extends it without another signature change. Keys:
## `map_id: String`, `map_type: int`, `terrain_mode: int` (TerrainMode),
## `noise_def_path: String`, `image: Image` (L8, HEIGHTMAP mode only),
## `height_start: float`, `height_range: float`.
signal new_map_requested(payload: Dictionary)

var _backdrop: ColorRect
var _panel: PanelContainer
var _maps_container: VBoxContainer
var _new_name_input: LineEdit
var _new_type_select: OptionButton
var _error_label: Label

const TYPE_NAMES: Array[String] = ["BASE", "POI", "BUILDING", "TOWN"]

## Terrain setup for new maps, chosen in the create form. NOISE keeps the
## shared-def pipeline (data/terrain/*.tres); HEIGHTMAP embeds the picked
## image in a per-map terrain_gen.tres; NONE opts the map out of smooth
## terrain entirely (SmoothGrid frees itself on load).
enum TerrainMode { NOISE, HEIGHTMAP, NONE }

const TERRAIN_MODE_NAMES: Array[String] = ["Procedural (noise)", "Heightmap (image)", "None"]
## Below this an image is more placeholder than terrain; above it the map gets
## huge relative to colony scale (and the embedded texture grows with it).
const MIN_HEIGHTMAP_SIZE := 16
const WARN_HEIGHTMAP_SIZE := 1024

var _terrain_mode_select: OptionButton
var _noise_def_select: OptionButton
var _noise_def_paths: Array[String] = []
var _heightmap_path_label: Label
var _heightmap_pick_button: Button
var _heightmap_minimap: TextureRect
var _heightmap_stats_label: Label
var _height_start_spin: SpinBox
var _height_range_spin: SpinBox
var _heightmap_image: Image = null
var _heightmap_box: Control = null
var _file_dialog: FileDialog = null


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

	# Terrain setup: how the new map's smooth terrain is generated.
	var terrain_hbox := HBoxContainer.new()
	terrain_hbox.add_theme_constant_override("separation", 8)
	main_vbox.add_child(terrain_hbox)

	_terrain_mode_select = OptionButton.new()
	for mode_name in TERRAIN_MODE_NAMES:
		_terrain_mode_select.add_item(mode_name)
	_terrain_mode_select.selected = TerrainMode.NOISE
	_terrain_mode_select.item_selected.connect(_on_terrain_mode_selected)
	terrain_hbox.add_child(_terrain_mode_select)

	_noise_def_select = OptionButton.new()
	_noise_def_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_noise_def_select.tooltip_text = "Shared TerrainGenDef from data/terrain/"
	terrain_hbox.add_child(_noise_def_select)

	# Heightmap-mode controls (visible only in that mode).
	_heightmap_box = VBoxContainer.new()
	_heightmap_box.add_theme_constant_override("separation", 6)
	_heightmap_box.visible = false
	main_vbox.add_child(_heightmap_box)

	var pick_row := HBoxContainer.new()
	pick_row.add_theme_constant_override("separation", 8)
	_heightmap_box.add_child(pick_row)

	_heightmap_path_label = Label.new()
	_heightmap_path_label.text = "No image picked"
	_heightmap_path_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heightmap_path_label.add_theme_font_size_override("font_size", 12)
	_heightmap_path_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	pick_row.add_child(_heightmap_path_label)

	_heightmap_pick_button = Button.new()
	_heightmap_pick_button.text = "Browse…"
	_heightmap_pick_button.pressed.connect(_on_browse_pressed)
	pick_row.add_child(_heightmap_pick_button)

	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 10)
	_heightmap_box.add_child(preview_row)

	_heightmap_minimap = TextureRect.new()
	_heightmap_minimap.custom_minimum_size = Vector2(96, 96)
	_heightmap_minimap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_heightmap_minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_heightmap_minimap.visible = false
	preview_row.add_child(_heightmap_minimap)

	_heightmap_stats_label = Label.new()
	_heightmap_stats_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_heightmap_stats_label.add_theme_font_size_override("font_size", 12)
	_heightmap_stats_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	preview_row.add_child(_heightmap_stats_label)

	var span_row := HBoxContainer.new()
	span_row.add_theme_constant_override("separation", 8)
	_heightmap_box.add_child(span_row)

	var start_lbl := Label.new()
	start_lbl.text = "Start:"
	start_lbl.add_theme_font_size_override("font_size", 12)
	span_row.add_child(start_lbl)

	_height_start_spin = SpinBox.new()
	_height_start_spin.min_value = -100.0
	_height_start_spin.max_value = 100.0
	_height_start_spin.step = 0.5
	_height_start_spin.value = -6.0
	_height_start_spin.value_changed.connect(_update_heightmap_stats)
	span_row.add_child(_height_start_spin)

	var range_lbl := Label.new()
	range_lbl.text = "Range:"
	range_lbl.add_theme_font_size_override("font_size", 12)
	span_row.add_child(range_lbl)

	_height_range_spin = SpinBox.new()
	_height_range_spin.min_value = 1.0
	_height_range_spin.max_value = 200.0
	_height_range_spin.step = 0.5
	_height_range_spin.value = 16.0
	_height_range_spin.value_changed.connect(_update_heightmap_stats)
	span_row.add_child(_height_range_spin)

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

		var del_btn := Button.new()
		del_btn.text = "✕"
		del_btn.tooltip_text = "Delete this map"
		del_btn.custom_minimum_size = Vector2(36, 0)
		del_btn.add_theme_color_override("font_color", Color(0.9, 0.35, 0.35))
		del_btn.pressed.connect(func(): _on_map_delete_requested(def.id))
		row.add_child(del_btn)

		_maps_container.add_child(row)


## Populate the noise-def dropdown (heightmap-driven defs are excluded — they
## are per-map content, not shared baselines) and preselect the default.
func setup_noise_defs(entries: Array[Dictionary], default_path: String) -> void:
	_noise_def_paths.clear()
	_noise_def_select.clear()
	var default_idx := 0
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var path := entry.get("path", "") as String
		_noise_def_paths.append(path)
		_noise_def_select.add_item(entry.get("id", "def") as String)
		if path == default_path:
			default_idx = i
	if _noise_def_select.item_count > 0:
		_noise_def_select.selected = default_idx


func _on_map_selected(map_id: String) -> void:
	map_selected.emit(map_id)


func _on_map_delete_requested(map_id: String) -> void:
	map_delete_requested.emit(map_id)


func _on_terrain_mode_selected(index: int) -> void:
	_noise_def_select.visible = index == TerrainMode.NOISE
	_heightmap_box.visible = index == TerrainMode.HEIGHTMAP


func _on_browse_pressed() -> void:
	if _file_dialog == null:
		_file_dialog = create_image_file_dialog()
		_file_dialog.file_selected.connect(_on_image_file_selected)
	if _file_dialog.get_parent() == null:
		add_child(_file_dialog)
	_file_dialog.popup_centered(Vector2i(900, 600))


func _on_image_file_selected(path: String) -> void:
	var image := load_heightmap_image(path)
	if image == null:
		_show_error("Could not load a usable heightmap from '%s'" % path.get_file())
		return
	_error_label.visible = false
	_heightmap_image = image
	_heightmap_path_label.text = path.get_file()
	_heightmap_minimap.visible = true
	_heightmap_minimap.texture = ImageTexture.create_from_image(image)
	_update_heightmap_stats()


func _update_heightmap_stats(_value: float = 0.0) -> void:
	if _heightmap_image == null:
		_heightmap_stats_label.text = ""
		return
	var size := _heightmap_image.get_size()
	var start := _height_start_spin.value
	var span := _height_range_spin.value
	_heightmap_stats_label.text = "%d×%d px → %d×%d m\nspan %.1f m … %.1f m" % [
		size.x, size.y, size.x, size.y, start, start + span,
	]


func _selected_noise_def_path() -> String:
	var idx := _noise_def_select.selected
	if idx >= 0 and idx < _noise_def_paths.size():
		return _noise_def_paths[idx]
	return ""


func _on_create_pressed() -> void:
	var name_text := _new_name_input.text.strip_edges()
	if name_text.is_empty():
		_show_error("Map name cannot be empty")
		return
	if " " in name_text:
		_show_error("Map name cannot contain spaces (use snake_case)")
		return
	var terrain_mode := _terrain_mode_select.selected
	if terrain_mode == TerrainMode.HEIGHTMAP and _heightmap_image == null:
		_show_error("Pick a heightmap image first (Browse…)")
		return
	_error_label.visible = false
	var chosen_type := _new_type_select.selected
	new_map_requested.emit({
		"map_id": name_text,
		"map_type": chosen_type,
		"terrain_mode": terrain_mode,
		"noise_def_path": _selected_noise_def_path(),
		"image": _heightmap_image,
		"height_start": _height_start_spin.value,
		"height_range": _height_range_spin.value,
	})


func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true


func show_launcher() -> void:
	visible = true


func hide_launcher() -> void:
	visible = false


# --- heightmap image picking (shared with the editor's terrain drawer) --------

## File dialog for picking heightmap images from anywhere on disk — the
## external-tool handoff point.
static func create_image_file_dialog() -> FileDialog:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray([
		"*.png ; PNG Image", "*.jpg, *.jpeg ; JPEG Image", "*.bmp ; BMP Image",
		"*.webp ; WebP Image", "*.tga ; TGA Image",
	])
	return dialog


## Load + validate + normalize an image file into the L8 grayscale the
## generator consumes (the same contract SmoothGrid._prepare_heightmap_image
## applies to texture pixels, kept local so the tool doesn't reach into
## subsystem privates). Null on unusable input, reason pushed.
static func load_heightmap_image(path: String) -> Image:
	var image := Image.load_from_file(path)
	if image == null:
		push_error("MapEditor: heightmap '%s' could not be loaded" % path)
		return null
	if image.get_width() < MIN_HEIGHTMAP_SIZE or image.get_height() < MIN_HEIGHTMAP_SIZE:
		push_error("MapEditor: heightmap '%s' is %dx%d — below %d px" % [
			path, image.get_width(), image.get_height(), MIN_HEIGHTMAP_SIZE,
		])
		return null
	if image.get_width() > WARN_HEIGHTMAP_SIZE or image.get_height() > WARN_HEIGHTMAP_SIZE:
		push_warning("MapEditor: heightmap '%s' is very large — %d×%d px means %d×%d m of terrain and an equally large embedded texture" % [
			path, image.get_width(), image.get_height(), image.get_width(), image.get_height(),
		])
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_L8)
	return image
