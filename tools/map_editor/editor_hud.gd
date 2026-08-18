class_name EditorHUD
extends CanvasLayer
## In-game overlay for MapEditor.
##
## Displays mode indicator badge, hotkey strip, active block/brush info,
## terrain sculpting info, filterable furniture palette, spawn hint info,
## map name and dirty indicator.
##
## Owned by MapEditor. Built procedurally in code.

signal furniture_selected(index: int)
signal save_requested()

var _mode_badge: PanelContainer
var _mode_label: Label
var _map_info_label: Label
var _save_button: Button
var _hotkey_label: Label
var _crosshair: Control

var _block_info_panel: PanelContainer
var _block_label: Label
var _brush_label: Label

var _terrain_info_panel: PanelContainer
var _terrain_material_label: Label
var _terrain_radius_label: Label
var _terrain_warning_label: Label

var _furniture_info_panel: PanelContainer
var _furniture_count_label: Label
var _furniture_search_input: LineEdit
var _furniture_item_list: ItemList
var _furniture_label: Label
var _yaw_label: Label
var _furniture_dims_label: Label
var _furniture_id_label: Label
var _furniture_defs: Array[FurnitureDef] = []
var _filtered_indices: Array[int] = []
var _selected_global_idx: int = 0

var _spawn_info_panel: PanelContainer
var _spawn_hint_label: Label

const MODE_NAMES: Array[String] = [
	"NAVIGATE",
	"BLOCK",
	"TERRAIN",
	"FURNITURE",
	"SPAWN",
]

const MODE_HOTKEYS: Array[String] = [
	"[LMB] Look   [WASD/Space/C] Fly   [Shift] Fast   [Esc] Release Mouse / Menu   [F1-F5] Modes",
	"[LMB] Paint   [Shift+LMB] Erase   [[/]] Block   [B+Scroll] Size   [Ctrl+S] Save   [F1-F5] Modes",
	"[LMB] Add   [Shift+LMB] Carve   [[/]] Radius   [B+Scroll] Radius   [Ctrl+S] Save   [F1-F5] Modes",
	"[LMB] Place   [Shift+LMB] Remove   [Tab/List] Select   [R] Rotate   [Ctrl+S] Save   [F1-F5] Modes",
	"[LMB] Player Spawn   [Shift+LMB] Colonist Spawn   [Ctrl+S] Save   [F1-F5] Modes",
]


func setup(parent: Node = null) -> void:
	if parent != null and get_parent() == null:
		parent.add_child(self)
	_build_ui()


func _build_ui() -> void:
	# Root container covering full screen
	var root := Control.new()
	root.name = "HUDContainer"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Block Info (Top Left) ---
	_block_info_panel = PanelContainer.new()
	_block_info_panel.name = "BlockInfoPanel"
	_block_info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_block_info_panel.offset_left = 16.0
	_block_info_panel.offset_top = 16.0
	_block_info_panel.offset_right = 240.0
	_block_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_block_info_panel.visible = false

	var block_style := StyleBoxFlat.new()
	block_style.bg_color = Color(0.08, 0.1, 0.14, 0.8)
	block_style.border_color = Color(0.2, 0.25, 0.35, 0.8)
	block_style.set_border_width_all(1)
	block_style.set_corner_radius_all(4)
	block_style.set_content_margin_all(8)
	_block_info_panel.add_theme_stylebox_override("panel", block_style)

	var vbox := VBoxContainer.new()
	vbox.name = "BlockInfoVBox"
	_block_info_panel.add_child(vbox)

	_block_label = Label.new()
	_block_label.name = "BlockLabel"
	_block_label.text = "Block: Wood"
	_block_label.add_theme_font_size_override("font_size", 13)
	_block_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	vbox.add_child(_block_label)

	_brush_label = Label.new()
	_brush_label.name = "BrushLabel"
	_brush_label.text = "Brush: 1x1x1"
	_brush_label.add_theme_font_size_override("font_size", 13)
	_brush_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	vbox.add_child(_brush_label)

	root.add_child(_block_info_panel)

	# --- Terrain Info (Top Left) ---
	_terrain_info_panel = PanelContainer.new()
	_terrain_info_panel.name = "TerrainInfoPanel"
	_terrain_info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_terrain_info_panel.offset_left = 16.0
	_terrain_info_panel.offset_top = 16.0
	_terrain_info_panel.offset_right = 240.0
	_terrain_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain_info_panel.visible = false

	var terrain_style := StyleBoxFlat.new()
	terrain_style.bg_color = Color(0.08, 0.1, 0.14, 0.8)
	terrain_style.border_color = Color(0.2, 0.35, 0.25, 0.8)
	terrain_style.set_border_width_all(1)
	terrain_style.set_corner_radius_all(4)
	terrain_style.set_content_margin_all(8)
	_terrain_info_panel.add_theme_stylebox_override("panel", terrain_style)

	var terrain_vbox := VBoxContainer.new()
	terrain_vbox.name = "TerrainInfoVBox"
	_terrain_info_panel.add_child(terrain_vbox)

	_terrain_material_label = Label.new()
	_terrain_material_label.name = "TerrainMaterialLabel"
	_terrain_material_label.text = "Material: Ground"
	_terrain_material_label.add_theme_font_size_override("font_size", 13)
	_terrain_material_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	terrain_vbox.add_child(_terrain_material_label)

	_terrain_radius_label = Label.new()
	_terrain_radius_label.name = "TerrainRadiusLabel"
	_terrain_radius_label.text = "Radius: 2.0 m"
	_terrain_radius_label.add_theme_font_size_override("font_size", 13)
	_terrain_radius_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	terrain_vbox.add_child(_terrain_radius_label)

	_terrain_warning_label = Label.new()
	_terrain_warning_label.name = "TerrainWarningLabel"
	_terrain_warning_label.text = "Smooth terrain unavailable\n(terrain.sqlite missing)"
	_terrain_warning_label.add_theme_font_size_override("font_size", 11)
	_terrain_warning_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3))
	_terrain_warning_label.visible = false
	terrain_vbox.add_child(_terrain_warning_label)

	root.add_child(_terrain_info_panel)

	# --- Furniture Palette Sidebar (Top Left) ---
	_furniture_info_panel = PanelContainer.new()
	_furniture_info_panel.name = "FurnitureInfoPanel"
	_furniture_info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_furniture_info_panel.offset_left = 16.0
	_furniture_info_panel.offset_top = 16.0
	_furniture_info_panel.offset_right = 300.0
	_furniture_info_panel.offset_bottom = 440.0
	_furniture_info_panel.custom_minimum_size = Vector2(284, 400)
	_furniture_info_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_furniture_info_panel.visible = false

	var furn_style := StyleBoxFlat.new()
	furn_style.bg_color = Color(0.08, 0.1, 0.14, 0.92)
	furn_style.border_color = Color(0.6, 0.3, 0.7, 0.85)
	furn_style.set_border_width_all(1)
	furn_style.set_corner_radius_all(6)
	furn_style.set_content_margin_all(10)
	_furniture_info_panel.add_theme_stylebox_override("panel", furn_style)

	var furn_vbox := VBoxContainer.new()
	furn_vbox.name = "FurnitureVBox"
	furn_vbox.add_theme_constant_override("separation", 6)
	_furniture_info_panel.add_child(furn_vbox)

	# Header: Title + Count
	var header_hbox := HBoxContainer.new()
	header_hbox.name = "HeaderHBox"
	furn_vbox.add_child(header_hbox)

	var title_lbl := Label.new()
	title_lbl.name = "PaletteTitle"
	title_lbl.text = "FURNITURE PALETTE"
	title_lbl.add_theme_font_size_override("font_size", 13)
	title_lbl.add_theme_color_override("font_color", Color(0.85, 0.65, 0.95))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_lbl)

	_furniture_count_label = Label.new()
	_furniture_count_label.name = "FurnitureCountLabel"
	_furniture_count_label.text = "(0)"
	_furniture_count_label.add_theme_font_size_override("font_size", 11)
	_furniture_count_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	_furniture_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header_hbox.add_child(_furniture_count_label)

	# Search LineEdit
	_furniture_search_input = LineEdit.new()
	_furniture_search_input.name = "FurnitureSearchInput"
	_furniture_search_input.placeholder_text = "Filter furniture... (Esc to unfocus)"
	_furniture_search_input.clear_button_enabled = true
	_furniture_search_input.add_theme_font_size_override("font_size", 12)
	_furniture_search_input.text_changed.connect(_on_furniture_search_changed)
	furn_vbox.add_child(_furniture_search_input)

	# ItemList
	_furniture_item_list = ItemList.new()
	_furniture_item_list.name = "FurnitureItemList"
	_furniture_item_list.select_mode = ItemList.SELECT_SINGLE
	_furniture_item_list.allow_reselect = true
	_furniture_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_furniture_item_list.custom_minimum_size = Vector2(0, 200)
	_furniture_item_list.add_theme_font_size_override("font_size", 12)
	_furniture_item_list.item_selected.connect(_on_furniture_item_selected)
	furn_vbox.add_child(_furniture_item_list)

	# Separator
	var sep := HSeparator.new()
	sep.name = "Separator"
	furn_vbox.add_child(sep)

	# Footer Info: Details
	_furniture_label = Label.new()
	_furniture_label.name = "FurnitureLabel"
	_furniture_label.text = "Furniture: None"
	_furniture_label.add_theme_font_size_override("font_size", 12)
	_furniture_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	furn_vbox.add_child(_furniture_label)

	_yaw_label = Label.new()
	_yaw_label.name = "YawLabel"
	_yaw_label.text = "Rotation: 0° [R]"
	_yaw_label.add_theme_font_size_override("font_size", 12)
	_yaw_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	furn_vbox.add_child(_yaw_label)

	_furniture_dims_label = Label.new()
	_furniture_dims_label.name = "FurnitureDimsLabel"
	_furniture_dims_label.text = "Size: 1x1x1"
	_furniture_dims_label.add_theme_font_size_override("font_size", 11)
	_furniture_dims_label.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	furn_vbox.add_child(_furniture_dims_label)

	_furniture_id_label = Label.new()
	_furniture_id_label.name = "FurnitureIdLabel"
	_furniture_id_label.text = ""
	_furniture_id_label.add_theme_font_size_override("font_size", 11)
	_furniture_id_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	_furniture_id_label.visible = false
	furn_vbox.add_child(_furniture_id_label)

	root.add_child(_furniture_info_panel)

	# --- Spawn Info (Top Left) ---
	_spawn_info_panel = PanelContainer.new()
	_spawn_info_panel.name = "SpawnInfoPanel"
	_spawn_info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_spawn_info_panel.offset_left = 16.0
	_spawn_info_panel.offset_top = 16.0
	_spawn_info_panel.offset_right = 280.0
	_spawn_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spawn_info_panel.visible = false

	var spawn_style := StyleBoxFlat.new()
	spawn_style.bg_color = Color(0.08, 0.1, 0.14, 0.8)
	spawn_style.border_color = Color(0.4, 0.2, 0.2, 0.8)
	spawn_style.set_border_width_all(1)
	spawn_style.set_corner_radius_all(4)
	spawn_style.set_content_margin_all(8)
	_spawn_info_panel.add_theme_stylebox_override("panel", spawn_style)

	var spawn_vbox := VBoxContainer.new()
	spawn_vbox.name = "SpawnInfoVBox"
	_spawn_info_panel.add_child(spawn_vbox)

	_spawn_hint_label = Label.new()
	_spawn_hint_label.name = "SpawnHintLabel"
	_spawn_hint_label.text = "LMB: Player Spawn\nShift+LMB: Colonist Spawn"
	_spawn_hint_label.add_theme_font_size_override("font_size", 13)
	_spawn_hint_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	spawn_vbox.add_child(_spawn_hint_label)

	root.add_child(_spawn_info_panel)

	# --- Mode Badge (Top Center) ---
	_mode_badge = PanelContainer.new()
	_mode_badge.name = "ModeBadge"
	_mode_badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mode_badge.offset_top = 16.0
	_mode_badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mode_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.12, 0.15, 0.2, 0.85)
	badge_style.border_color = Color(0.3, 0.5, 0.8, 0.9)
	badge_style.set_border_width_all(2)
	badge_style.set_corner_radius_all(6)
	badge_style.set_content_margin_all(8)
	badge_style.content_margin_left = 16
	badge_style.content_margin_right = 16
	_mode_badge.add_theme_stylebox_override("panel", badge_style)

	_mode_label = Label.new()
	_mode_label.name = "ModeLabel"
	_mode_label.text = "[ F1 ] NAVIGATE"
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_label.add_theme_font_size_override("font_size", 16)
	_mode_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_mode_badge.add_child(_mode_label)
	root.add_child(_mode_badge)

	# --- Map Info (Top Right) ---
	var info_panel := PanelContainer.new()
	info_panel.name = "MapInfoPanel"
	info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_panel.offset_left = -280.0
	info_panel.offset_top = 16.0
	info_panel.offset_right = -16.0
	info_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var info_style := StyleBoxFlat.new()
	info_style.bg_color = Color(0.08, 0.1, 0.14, 0.8)
	info_style.border_color = Color(0.2, 0.25, 0.35, 0.8)
	info_style.set_border_width_all(1)
	info_style.set_corner_radius_all(4)
	info_style.set_content_margin_all(6)
	info_panel.add_theme_stylebox_override("panel", info_style)

	var info_hbox := HBoxContainer.new()
	info_hbox.name = "MapInfoHBox"
	info_hbox.add_theme_constant_override("separation", 8)
	info_panel.add_child(info_hbox)

	_save_button = Button.new()
	_save_button.name = "SaveButton"
	_save_button.text = "Save"
	_save_button.tooltip_text = "Save map (Ctrl+S)"
	_save_button.add_theme_font_size_override("font_size", 12)
	_save_button.pressed.connect(_on_save_pressed)
	info_hbox.add_child(_save_button)

	_map_info_label = Label.new()
	_map_info_label.name = "MapInfoLabel"
	_map_info_label.text = "Map: none"
	_map_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_map_info_label.add_theme_font_size_override("font_size", 13)
	_map_info_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	info_hbox.add_child(_map_info_label)

	root.add_child(info_panel)

	# --- Hotkey Strip (Bottom Center) ---
	var hotkey_panel := PanelContainer.new()
	hotkey_panel.name = "HotkeyPanel"
	hotkey_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotkey_panel.offset_bottom = -16.0
	hotkey_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hotkey_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hotkey_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hotkey_style := StyleBoxFlat.new()
	hotkey_style.bg_color = Color(0.08, 0.1, 0.14, 0.85)
	hotkey_style.border_color = Color(0.2, 0.25, 0.35, 0.8)
	hotkey_style.set_border_width_all(1)
	hotkey_style.set_corner_radius_all(6)
	hotkey_style.set_content_margin_all(8)
	hotkey_style.content_margin_left = 16
	hotkey_style.content_margin_right = 16
	hotkey_panel.add_theme_stylebox_override("panel", hotkey_style)

	_hotkey_label = Label.new()
	_hotkey_label.name = "HotkeyLabel"
	_hotkey_label.text = MODE_HOTKEYS[0]
	_hotkey_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hotkey_label.add_theme_font_size_override("font_size", 13)
	_hotkey_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
	hotkey_panel.add_child(_hotkey_label)
	root.add_child(hotkey_panel)

	# --- Crosshair (Center) ---
	_crosshair = Control.new()
	_crosshair.name = "Crosshair"
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Build cross lines
	var h_line := ColorRect.new()
	h_line.name = "HLine"
	h_line.color = Color(1.0, 1.0, 1.0, 0.75)
	h_line.offset_left = -6
	h_line.offset_right = 6
	h_line.offset_top = -1
	h_line.offset_bottom = 1
	_crosshair.add_child(h_line)

	var v_line := ColorRect.new()
	v_line.name = "VLine"
	v_line.color = Color(1.0, 1.0, 1.0, 0.75)
	v_line.offset_left = -1
	v_line.offset_right = 1
	v_line.offset_top = -6
	v_line.offset_bottom = 6
	_crosshair.add_child(v_line)

	root.add_child(_crosshair)


func populate_furniture_list(defs: Array[FurnitureDef], selected_idx: int = 0) -> void:
	_furniture_defs = defs
	_selected_global_idx = selected_idx
	var current_query := _furniture_search_input.text if _furniture_search_input != null else ""
	_filter_furniture_list(current_query)


func _on_furniture_search_changed(new_text: String) -> void:
	_filter_furniture_list(new_text)


func _filter_furniture_list(query: String) -> void:
	if _furniture_item_list == null:
		return
	_furniture_item_list.clear()
	_filtered_indices.clear()

	var q := query.strip_edges().to_lower()
	for i in range(_furniture_defs.size()):
		var def := _furniture_defs[i]
		if def == null:
			continue
		var dname := def.display_name if not def.display_name.is_empty() else def.id
		var matches := q.is_empty() or dname.to_lower().contains(q) or def.id.to_lower().contains(q)
		if matches:
			_filtered_indices.append(i)
			var label := "%s  [%dx%dx%d]" % [dname, def.dimensions.x, def.dimensions.y, def.dimensions.z]
			var list_idx := _furniture_item_list.add_item(label, def.icon)
			_furniture_item_list.set_item_tooltip(list_idx, "%s (%s)\nDimensions: %dx%dx%d" % [
				dname,
				def.id,
				def.dimensions.x,
				def.dimensions.y,
				def.dimensions.z,
			])

	if _furniture_count_label != null:
		_furniture_count_label.text = "(%d/%d)" % [_filtered_indices.size(), _furniture_defs.size()]

	# Re-select the active item if present in filtered items, or select first match
	var found_selected_idx := _filtered_indices.find(_selected_global_idx)
	if found_selected_idx != -1:
		_furniture_item_list.select(found_selected_idx)
		_furniture_item_list.ensure_current_is_visible()
	elif not _filtered_indices.is_empty():
		_selected_global_idx = _filtered_indices[0]
		_furniture_item_list.select(0)
		_furniture_item_list.ensure_current_is_visible()
		furniture_selected.emit(_selected_global_idx)


func _on_furniture_item_selected(list_idx: int) -> void:
	if list_idx >= 0 and list_idx < _filtered_indices.size():
		var global_idx := _filtered_indices[list_idx]
		_selected_global_idx = global_idx
		furniture_selected.emit(global_idx)


func select_furniture_by_index(global_idx: int) -> void:
	_selected_global_idx = global_idx
	if _furniture_item_list == null:
		return
	var found_list_idx := _filtered_indices.find(global_idx)
	if found_list_idx != -1:
		_furniture_item_list.select(found_list_idx)
		_furniture_item_list.ensure_current_is_visible()
	else:
		_furniture_item_list.deselect_all()


func get_filtered_furniture_indices() -> Array[int]:
	return _filtered_indices


func is_search_focused() -> bool:
	return _furniture_search_input != null and _furniture_search_input.has_focus()


func unfocus_search() -> void:
	if _furniture_search_input != null and _furniture_search_input.has_focus():
		_furniture_search_input.release_focus()


func set_block_info(block_name: String, diameter: int) -> void:
	if _block_label != null:
		_block_label.text = "Block: " + block_name
	if _brush_label != null:
		_brush_label.text = "Brush: %dx%dx%d" % [diameter, diameter, diameter]


func set_sculpt_info(radius: float) -> void:
	if _terrain_radius_label != null:
		_terrain_radius_label.text = "Radius: %.1f m" % radius


func set_terrain_info(material_name: String, radius: float) -> void:
	if _terrain_material_label != null:
		_terrain_material_label.text = "Material: " + material_name.capitalize()
	set_sculpt_info(radius)


func set_furniture_info(name: String, yaw_quarters: int, dims: Vector3i = Vector3i.ONE, id_str: String = "") -> void:
	if _furniture_label != null:
		_furniture_label.text = "Furniture: " + name
	if _yaw_label != null:
		var deg := (yaw_quarters % 4) * 90
		_yaw_label.text = "Rotation: %d° [R]" % deg
	if _furniture_dims_label != null:
		_furniture_dims_label.text = "Size: %dx%dx%d (WxHxD)" % [dims.x, dims.y, dims.z]
	if _furniture_id_label != null:
		if not id_str.is_empty():
			_furniture_id_label.text = "ID: " + id_str
			_furniture_id_label.visible = true
		else:
			_furniture_id_label.visible = false


func set_terrain_available(available: bool) -> void:
	if _terrain_warning_label != null:
		_terrain_warning_label.visible = not available


func set_mode(mode: int) -> void:
	if mode < 0 or mode >= MODE_NAMES.size():
		return
	var key_num := mode + 1
	_mode_label.text = "[ F%d ] %s" % [key_num, MODE_NAMES[mode]]
	_hotkey_label.text = MODE_HOTKEYS[mode]

	if _block_info_panel != null:
		_block_info_panel.visible = (mode == 1) # Mode.BLOCK
	if _terrain_info_panel != null:
		_terrain_info_panel.visible = (mode == 2) # Mode.TERRAIN
	if _furniture_info_panel != null:
		_furniture_info_panel.visible = (mode == 3) # Mode.FURNITURE
	if _spawn_info_panel != null:
		_spawn_info_panel.visible = (mode == 4) # Mode.SPAWN

	# Color the mode badge
	var badge_style := _mode_badge.get_theme_stylebox("panel") as StyleBoxFlat
	if badge_style != null:
		match mode:
			0: # NAVIGATE
				badge_style.border_color = Color(0.3, 0.5, 0.8, 0.9)
			1: # BLOCK
				badge_style.border_color = Color(0.8, 0.6, 0.2, 0.9)
			2: # TERRAIN
				badge_style.border_color = Color(0.3, 0.8, 0.4, 0.9)
			3: # FURNITURE
				badge_style.border_color = Color(0.7, 0.3, 0.8, 0.9)
			4: # SPAWN
				badge_style.border_color = Color(0.9, 0.3, 0.3, 0.9)



func _on_save_pressed() -> void:
	save_requested.emit()


func set_map_info(map_id: String, dirty: bool) -> void:
	if _map_info_label == null:
		return
	var dirty_mark := " *" if dirty else ""
	_map_info_label.text = "Map: %s%s" % [map_id, dirty_mark]


func set_crosshair_color(color: Color) -> void:
	if _crosshair == null:
		return
	for child in _crosshair.get_children():
		if child is ColorRect:
			child.color = color
