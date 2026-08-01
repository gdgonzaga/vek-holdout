@tool
extends PanelContainer
## Side panel for the Voxel Paint EditorPlugin.
##
## Two sections:
##   1. MAPS — list/open existing maps, create new ones. Each map owns a .tscn
##      stamped from subsystems/maps/map_template.tscn plus a per-map sqlite
##      stream. Creation + open are delegated to the plugin.
##   2. PAINT — block/brush selection, paint/erase/furniture modes. Dormant
##      until a VoxelTerrain is bound (after opening a map).
##
## Created by voxel_paint_plugin.gd and added to CONTAINER_SPATIAL_EDITOR_SIDE_LEFT.
## Holds a reference back to the plugin to delegate map ops and read state.

# Modes — kept as int constants here so the panel doesn't need to know the plugin's
# enum. The plugin reads get_mode() and compares against its own PaintMode enum.
const MODE_PAINT := 0
const MODE_ERASE := 1
const MODE_FURNITURE := 2

var _plugin: EditorPlugin  # set by the plugin after instantiation

# --- Controls (populated in _ready) ----------------------------

# Maps section.
var _maps_grid: GridContainer
var _no_maps_label: Label
var _new_map_btn: Button
var _refresh_maps_btn: Button
var _new_map_dialog: ConfirmationDialog
var _new_map_input: LineEdit

# Terrain status (bound db path, or "no terrain").
var _terrain_status_label: Label

# Paint modes.
var _mode_paint: Button
var _mode_erase: Button
var _mode_furniture: Button
var _block_select: OptionButton
var _radius_slider: HSlider
var _radius_label: Label
var _info_label: Label
# Furniture section.
var _furniture_select: OptionButton
var _rotate_hint: Label
# Containers for show/hide based on mode.
var _paint_controls: VBoxContainer
var _furniture_controls: VBoxContainer
# Cached FurnitureDef resources by id, keyed when _populate_furniture loads them.
var _furniture_defs_by_id: Dictionary = {}

# Current mode (MODE_PAINT / MODE_ERASE / MODE_FURNITURE).
var _mode: int = MODE_PAINT
# Whether furniture mode is available (has SpawnPoints).
var _furniture_enabled: bool = true


func _ready() -> void:
	_build_ui()
	_populate_blocks()
	_populate_furniture()
	refresh_maps()
	refresh_terrain_status()
	_update_mode_visibility()


func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin


# --- Accessors (read by the plugin) -----------------------------------------

func get_mode() -> int:
	return _mode


func get_selected_furniture_id() -> String:
	if _mode != MODE_FURNITURE or _furniture_select.selected < 0:
		return ""
	return _furniture_select.get_item_metadata(_furniture_select.selected) if _furniture_select.get_item_metadata(_furniture_select.selected) is String else ""


## Returns the cached FurnitureDef for the selected dropdown entry, or null.
func get_selected_furniture_def() -> FurnitureDef:
	var def_id := get_selected_furniture_id()
	if def_id.is_empty():
		return null
	return _furniture_defs_by_id.get(def_id)


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


## Grey out the Furniture mode button when no SpawnPoints container exists.
func set_furniture_enabled(enabled: bool) -> void:
	_furniture_enabled = enabled
	_mode_furniture.disabled = not enabled
	if not enabled and _mode == MODE_FURNITURE:
		# Force back to paint mode.
		_mode_furniture.button_pressed = false
		_on_paint_toggled(true)


## Re-scan BuildLibrary and repopulate the furniture selector.
func refresh_furniture_list() -> void:
	_populate_furniture()


# --- Maps section -----------------------------------------------------------

## Rebuild the maps grid from the plugin's catalog scan. Safe to call when no
## plugin is bound (shows the empty hint).
func refresh_maps() -> void:
	for child in _maps_grid.get_children():
		child.queue_free()
	var maps: Array = _plugin.list_maps() if _plugin != null else []
	if maps.is_empty():
		_no_maps_label.visible = true
		_maps_grid.visible = false
		return
	_no_maps_label.visible = false
	_maps_grid.visible = true
	for entry in maps:
		var btn := Button.new()
		btn.text = String(entry["display_name"])
		btn.tooltip_text = "Open %s\nscene: %s" % [entry["id"], entry["scene_path"]]
		btn.custom_minimum_size = Vector2(110, 0)
		btn.pressed.connect(_on_map_clicked.bind(String(entry["scene_path"])))
		_maps_grid.add_child(btn)


# --- Terrain status ---------------------------------------------------------

## Reflect whether painting is bound to a terrain. Called by the plugin after
## binding/unbinding and safe to call with no plugin.
func refresh_terrain_status() -> void:
	if _plugin == null or not _plugin.is_terrain_bound():
		_terrain_status_label.text = "No terrain — open or create a map"
		_terrain_status_label.add_theme_color_override("font_color", Color(1, 0.5, 0.3))
		return
	var path: String = _plugin.get_stream_path()
	if path.is_empty():
		_terrain_status_label.text = "Terrain bound — no database (edits won't persist)"
		_terrain_status_label.add_theme_color_override("font_color", Color(1, 0.5, 0.3))
	else:
		_terrain_status_label.text = path
		_terrain_status_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))


# --- Private ----------------------------------------------------------------

func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)

	# -- Maps section --
	var maps_head := HBoxContainer.new()
	var maps_title := Label.new()
	maps_title.text = "Maps"
	maps_head.add_child(maps_title)
	maps_head.add_child(Control.new())  # spacer
	_refresh_maps_btn = Button.new()
	_refresh_maps_btn.text = "⟳"
	_refresh_maps_btn.tooltip_text = "Rescan data/maps/"
	_refresh_maps_btn.custom_minimum_size = Vector2(24, 0)
	_refresh_maps_btn.pressed.connect(refresh_maps)
	maps_head.add_child(_refresh_maps_btn)

	_maps_grid = GridContainer.new()
	_maps_grid.columns = 3
	_maps_grid.add_theme_constant_override("h_separation", 4)
	_maps_grid.add_theme_constant_override("v_separation", 4)

	_no_maps_label = Label.new()
	_no_maps_label.text = "No maps yet — create one below."
	_no_maps_label.add_theme_font_size_override("font_size", 11)
	_no_maps_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	_new_map_btn = Button.new()
	_new_map_btn.text = "+ New Map"
	_new_map_btn.tooltip_text = "Create a new map from the template"
	_new_map_btn.pressed.connect(_on_new_map)

	# -- New Map dialog --
	_new_map_dialog = ConfirmationDialog.new()
	_new_map_dialog.title = "New Map"
	_new_map_dialog.min_size = Vector2i(300, 120)
	_new_map_dialog.ok_button_text = "Create"
	var dialog_vbox := VBoxContainer.new()
	var label := Label.new()
	label.text = "Map name (no spaces):"
	_new_map_input = LineEdit.new()
	_new_map_input.placeholder_text = "e.g. abandoned_factory"
	_new_map_input.caret_blink = true
	dialog_vbox.add_child(label)
	dialog_vbox.add_child(_new_map_input)
	_new_map_dialog.add_child(dialog_vbox)
	_new_map_dialog.confirmed.connect(_on_new_map_confirmed)

	# -- Terrain status --
	_terrain_status_label = Label.new()
	_terrain_status_label.text = "No terrain — open or create a map"
	_terrain_status_label.add_theme_color_override("font_color", Color(1, 0.5, 0.3))
	_terrain_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

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
	_mode_furniture = Button.new()
	_mode_furniture.text = "Furniture"
	_mode_furniture.toggle_mode = true
	_mode_furniture.tooltip_text = "Left-click places furniture, Shift+LMB removes"
	_mode_paint.toggled.connect(_on_paint_toggled)
	_mode_erase.toggled.connect(_on_erase_toggled)
	_mode_furniture.toggled.connect(_on_furniture_toggled)
	mode_box.add_child(_mode_paint)
	mode_box.add_child(_mode_erase)
	mode_box.add_child(_mode_furniture)

	# -- Paint controls (block selector, brush radius) --
	_paint_controls = VBoxContainer.new()
	var block_label := Label.new()
	block_label.text = "Block:"
	_block_select = OptionButton.new()
	_block_select.tooltip_text = "Voxel type to paint"
	_block_select.item_selected.connect(_on_block_selected)

	var radius_label_head := Label.new()
	radius_label_head.text = "Brush Radius:"
	_radius_slider = HSlider.new()
	_radius_slider.min_value = 0.5
	_radius_slider.max_value = 5.0
	_radius_slider.step = 0.5
	_radius_slider.value = 1.0
	_radius_slider.custom_minimum_size.x = 100
	_radius_slider.tooltip_text = "Sphere brush radius in voxels"
	_radius_label = Label.new()
	_radius_label.text = "1.0"
	_radius_slider.value_changed.connect(_on_radius_changed)

	var radius_row := HBoxContainer.new()
	radius_row.add_child(_radius_slider)
	radius_row.add_child(_radius_label)

	_paint_controls.add_child(block_label)
	_paint_controls.add_child(_block_select)
	_paint_controls.add_child(radius_label_head)
	_paint_controls.add_child(radius_row)

	# -- Furniture controls (selector + hint) --
	_furniture_controls = VBoxContainer.new()
	var furniture_label := Label.new()
	furniture_label.text = "Furniture:"
	_furniture_select = OptionButton.new()
	_furniture_select.tooltip_text = "Furniture type to place"
	_rotate_hint = Label.new()
	_rotate_hint.text = "R: rotate | Shift+LMB: remove"
	_rotate_hint.add_theme_font_size_override("font_size", 11)
	_furniture_controls.add_child(furniture_label)
	_furniture_controls.add_child(_furniture_select)
	_furniture_controls.add_child(_rotate_hint)

	# -- Info --
	_info_label = Label.new()
	_info_label.text = "LMB: paint | Shift+LMB: erase"
	_info_label.add_theme_font_size_override("font_size", 11)

	# Assemble: maps at top, then terrain status, then paint controls.
	vbox.add_child(maps_head)
	vbox.add_child(_maps_grid)
	vbox.add_child(_no_maps_label)
	vbox.add_child(_new_map_btn)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_terrain_status_label)
	vbox.add_child(HSeparator.new())
	vbox.add_child(mode_box)
	vbox.add_child(_paint_controls)
	vbox.add_child(_furniture_controls)
	vbox.add_child(HSeparator.new())
	vbox.add_child(_info_label)

	add_child(vbox)
	add_child(_new_map_dialog)


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


## Scan res://data/furniture/ directly for .tres FurnitureDef resources.
## Editor-side loader, independent of the runtime BuildLibrary autoload —
## autoloads aren't reliably reachable from @tool context (the panel lives in
## the editor UI tree, not the game scene tree). Mirrors how _populate_blocks
## loads voxel_library.tres directly rather than via BuildLibrary.
func _load_furniture_defs() -> Array:
	var out: Array = []
	var dir_path := "res://data/furniture/"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("VoxelPaintPanel: could not open %s" % dir_path)
		return out
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res = load(dir_path + fname)
			if res is FurnitureDef:
				out.append(res)
		fname = dir.get_next()
	return out


## Populate the furniture selector from disk. Shows only FurnitureDef entries.
func _populate_furniture() -> void:
	_furniture_select.clear()
	_furniture_defs_by_id.clear()
	var defs := _load_furniture_defs()
	for def in defs:
		_furniture_defs_by_id[def.id] = def
		_furniture_select.add_item(def.display_name)
		_furniture_select.set_item_metadata(_furniture_select.item_count - 1, def.id)
	if _furniture_select.item_count > 0:
		_furniture_select.selected = 0


## Show/hide paint and furniture control groups and update the info label.
func _update_mode_visibility() -> void:
	_paint_controls.visible = (_mode == MODE_PAINT or _mode == MODE_ERASE)
	_furniture_controls.visible = (_mode == MODE_FURNITURE)
	match _mode:
		MODE_PAINT:
			_info_label.text = "LMB: paint | Shift+LMB: erase"
		MODE_ERASE:
			_info_label.text = "LMB: erase | Shift+LMB: paint"
		MODE_FURNITURE:
			_info_label.text = "LMB: place | Shift+LMB: remove | R: rotate"


# --- Signal handlers -------------------------------------------------------

func _on_map_clicked(scene_path: String) -> void:
	if _plugin == null:
		return
	_plugin.open_map_scene(scene_path)


func _on_new_map() -> void:
	_new_map_input.text = ""
	_new_map_input.grab_focus()
	_new_map_dialog.popup_centered()


func _on_new_map_confirmed() -> void:
	var name: String = _new_map_input.text.strip_edges()
	if name.is_empty():
		return
	if _plugin == null:
		return
	var path: String = _plugin.create_new_map(name)
	if not path.is_empty():
		refresh_maps()
		refresh_terrain_status()


func _on_paint_toggled(pressed: bool) -> void:
	if pressed:
		_mode = MODE_PAINT
		_mode_erase.button_pressed = false
		_mode_furniture.button_pressed = false
		_update_mode_visibility()


func _on_erase_toggled(pressed: bool) -> void:
	if pressed:
		_mode = MODE_ERASE
		_mode_paint.button_pressed = false
		_mode_furniture.button_pressed = false
		_update_mode_visibility()


func _on_furniture_toggled(pressed: bool) -> void:
	if pressed and _furniture_enabled:
		_mode = MODE_FURNITURE
		_mode_paint.button_pressed = false
		_mode_erase.button_pressed = false
		_update_mode_visibility()
	elif not pressed and _mode == MODE_FURNITURE:
		# User toggled off while in furniture mode — fall back to paint.
		_mode = MODE_PAINT
		_mode_paint.button_pressed = true
		_update_mode_visibility()
	elif not pressed:
		# Toggled off while not in furniture mode — ignore (another button won).
		_mode_paint.button_pressed = true


func _on_block_selected(_index: int) -> void:
	pass


func _on_radius_changed(value: float) -> void:
	_radius_label.text = "%.1f" % value
