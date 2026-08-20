class_name EditorHUD
extends CanvasLayer
## In-game overlay for MapEditor.
##
## Displays mode indicator badge, hotkey strip, filterable block palette,
## terrain sculpting info, filterable furniture palette, spawn hint info,
## map name and dirty indicator, world coordinate readout, and metadata panel.
##
## Owned by MapEditor. Built procedurally in code.

const EditorPalettePanelClass = preload("res://tools/map_editor/editor_palette_panel.gd")
const StructureBrowserClass = preload("res://tools/map_editor/structure_browser.gd")

signal block_selected(index: int)
signal furniture_selected(index: int)
signal structure_selected(index: int)
signal save_requested()
## Terrain drawer: the editor writes def params / image, then reloads the map.
signal terrain_apply_requested()
## The user asked for a heightmap image file — the editor owns the FileDialog.
signal terrain_pick_image_requested()

var _mode_badge: PanelContainer
var _mode_label: Label
var _map_info_label: Label
var _save_button: Button
var _meta_button: Button
var _hotkey_label: Label
var _crosshair: Control
var _coord_label: Label

var _block_palette: EditorPalettePanel
var _brush_label: Label
var _orientation_label: Label
var _block_info_panel: PanelContainer # Alias for backward compatibility
var _block_label: Label             # Alias for backward compatibility

var _terrain_info_panel: PanelContainer
var _terrain_material_label: Label
var _terrain_radius_label: Label
var _terrain_warning_label: Label

var _furniture_palette: EditorPalettePanel
var _furniture_dims_label: Label
var _yaw_label: Label
var _furniture_info_panel: PanelContainer # Alias for backward compatibility
var _furniture_count_label: Label         # Alias for backward compatibility
var _furniture_search_input: LineEdit     # Alias for backward compatibility
var _furniture_item_list: ItemList         # Alias for backward compatibility
var _furniture_label: Label               # Alias for backward compatibility
var _furniture_id_label: Label            # Alias for backward compatibility
var _furniture_defs: Array[FurnitureDef] = []

var _structure_browser: StructureBrowserClass
var _selected_global_idx: int = 0

var _spawn_info_panel: PanelContainer
var _spawn_hint_label: Label

var _metadata_panel: PanelContainer
var _meta_display_name_input: LineEdit
var _meta_desc_input: TextEdit
var _meta_type_option: OptionButton
var _meta_difficulty_spin: SpinBox

var _terrain_button: Button
var _terrain_drawer: PanelContainer
var _terrain_mode_label: Label
var _terrain_def_label: Label
var _terrain_minimap: TextureRect
var _terrain_start_spin: SpinBox
var _terrain_range_spin: SpinBox
var _terrain_seed_spin: SpinBox
var _terrain_freq_spin: SpinBox
var _terrain_span_label: Label
var _terrain_pick_button: Button
var _terrain_remove_button: Button
var _terrain_heightmap_section: Control = null
var _terrain_noise_section: Control = null
var _pending_heightmap: Image = null
var _terrain_remove_pending := false
var _drawer_is_heightmap := false
var _drawer_has_terrain := false

const MODE_NAMES: Array[String] = [
	"NAVIGATE",
	"BLOCK",
	"TERRAIN",
	"FURNITURE",
	"SPAWN",
	"STRUCTURE",
]

const MODE_HOTKEYS: Array[String] = [
	"[LMB] Look   [WASD/Space/C] Fly   [Shift] Fast   [G] Grid   [Esc] Menu   [F1-F6] Modes",
	"[LMB] Paint   [Shift+LMB] Erase   [Wheel] Rotate   [R] Axis   [I] Pick   [B+Wheel] Size   [Ctrl+Z] Undo   [G] Grid",
	"[LMB] Add   [Shift+LMB] Carve   [[/]] Radius   [B+Wheel] Radius   [Ctrl+Z] Undo   [Ctrl+S] Save   [G] Grid",
	"[LMB] Place   [Shift+LMB] Remove   [Wheel] Rotate   [R] Axis   [Tab/List] Select   [Ctrl+S] Save   [G] Grid",
	"[LMB] Player Spawn   [Shift+LMB] Colonist Spawn   [Ctrl+S] Save   [G] Grid   [F1-F6] Modes",
	"[LMB] Stamp   [Wheel] Rotate   [Ctrl+Wheel] Y-Offset   [Arrows] Nudge   [Tab/List] Select   [Ctrl+Z] Undo   [G] Grid",
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

	# --- Block Palette Sidebar (Top Left) ---
	_block_palette = EditorPalettePanelClass.new()
	_block_palette.name = "BlockPalettePanel"
	_block_palette.setup(
		"BLOCK PALETTE",
		"Filter blocks... (Esc to unfocus)",
		Color(0.8, 0.6, 0.2, 0.85),
		Color(0.95, 0.8, 0.5)
	)
	_block_palette.item_selected.connect(func(idx: int) -> void:
		block_selected.emit(idx)
	)
	_block_palette.visible = false

	# Add brush size info to Block Palette footer
	var block_footer := _block_palette.get_footer_vbox()
	_brush_label = Label.new()
	_brush_label.name = "BrushLabel"
	_brush_label.text = "Brush: 1x1x1 [B+Scroll]"
	_brush_label.add_theme_font_size_override("font_size", 11)
	_brush_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	block_footer.add_child(_brush_label)

	_orientation_label = Label.new()
	_orientation_label.name = "OrientationLabel"
	_orientation_label.unique_name_in_owner = true
	_orientation_label.text = "Rot: #0 [Yaw 0°, Pitch 0°]"
	_orientation_label.add_theme_font_size_override("font_size", 11)
	_orientation_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.95))
	block_footer.add_child(_orientation_label)

	# Backward-compatible references
	_block_info_panel = _block_palette
	_block_label = _block_palette._selected_label

	root.add_child(_block_palette)

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
	terrain_style.border_color = Color(0.2, 0.25, 0.35, 0.8)
	terrain_style.set_border_width_all(1)
	terrain_style.set_corner_radius_all(4)
	terrain_style.set_content_margin_all(8)
	_terrain_info_panel.add_theme_stylebox_override("panel", terrain_style)

	var terrain_vbox := VBoxContainer.new()
	terrain_vbox.name = "TerrainInfoVBox"
	terrain_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain_info_panel.add_child(terrain_vbox)

	_terrain_material_label = Label.new()
	_terrain_material_label.name = "TerrainMaterialLabel"
	_terrain_material_label.text = "Material: Ground"
	_terrain_material_label.add_theme_font_size_override("font_size", 13)
	_terrain_material_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	_terrain_material_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	terrain_vbox.add_child(_terrain_material_label)

	_terrain_radius_label = Label.new()
	_terrain_radius_label.name = "TerrainRadiusLabel"
	_terrain_radius_label.text = "Radius: 2.0 m"
	_terrain_radius_label.add_theme_font_size_override("font_size", 13)
	_terrain_radius_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	_terrain_radius_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	terrain_vbox.add_child(_terrain_radius_label)

	_terrain_warning_label = Label.new()
	_terrain_warning_label.name = "TerrainWarningLabel"
	_terrain_warning_label.text = "Smooth terrain unavailable\n(terrain.sqlite missing)"
	_terrain_warning_label.add_theme_font_size_override("font_size", 11)
	_terrain_warning_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3))
	_terrain_warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_terrain_warning_label.visible = false
	terrain_vbox.add_child(_terrain_warning_label)

	root.add_child(_terrain_info_panel)

	# --- Furniture Palette Sidebar (Top Left) ---
	_furniture_palette = EditorPalettePanelClass.new()
	_furniture_palette.name = "FurnitureInfoPanel"
	_furniture_palette.setup(
		"FURNITURE PALETTE",
		"Filter furniture... (Esc to unfocus)",
		Color(0.6, 0.3, 0.7, 0.85),
		Color(0.85, 0.65, 0.95)
	)
	_furniture_palette.item_selected.connect(func(idx: int) -> void:
		_selected_global_idx = idx
		furniture_selected.emit(idx)
	)
	_furniture_palette.visible = false

	# Add size and rotation info to Furniture Palette footer
	var furn_footer := _furniture_palette.get_footer_vbox()
	var dims_yaw_hbox := HBoxContainer.new()
	dims_yaw_hbox.name = "DimsYawHBox"
	furn_footer.add_child(dims_yaw_hbox)

	_furniture_dims_label = Label.new()
	_furniture_dims_label.name = "FurnitureDimsLabel"
	_furniture_dims_label.text = "Size: 1x1x1"
	_furniture_dims_label.add_theme_font_size_override("font_size", 11)
	_furniture_dims_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	_furniture_dims_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dims_yaw_hbox.add_child(_furniture_dims_label)

	_yaw_label = Label.new()
	_yaw_label.name = "YawLabel"
	_yaw_label.text = "0° [R]"
	_yaw_label.add_theme_font_size_override("font_size", 11)
	_yaw_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	dims_yaw_hbox.add_child(_yaw_label)

	# Backward-compatible references
	_furniture_info_panel = _furniture_palette
	_furniture_count_label = _furniture_palette._count_label
	_furniture_search_input = _furniture_palette._search_input
	_furniture_item_list = _furniture_palette._item_list
	_furniture_label = _furniture_palette._selected_label
	_furniture_id_label = _furniture_palette._id_label

	root.add_child(_furniture_palette)

	# --- Structure Browser Sidebar (Top Left) ---
	_structure_browser = StructureBrowserClass.new()
	_structure_browser.name = "StructureBrowserPanel"
	_structure_browser.setup(
		"STRUCTURES",
		"Filter structures... (Esc to unfocus)",
		Color(0.65, 0.4, 0.85, 0.85),
		Color(0.9, 0.85, 0.98)
	)
	_structure_browser.item_selected.connect(func(idx: int) -> void:
		_selected_global_idx = idx
		structure_selected.emit(idx)
	)
	_structure_browser.visible = false
	root.add_child(_structure_browser)

	# --- Spawn Info (Top Left) ---
	_spawn_info_panel = PanelContainer.new()
	_spawn_info_panel.name = "SpawnInfoPanel"
	_spawn_info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_spawn_info_panel.offset_left = 16.0
	_spawn_info_panel.offset_top = 16.0
	_spawn_info_panel.offset_right = 260.0
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
	spawn_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spawn_info_panel.add_child(spawn_vbox)

	_spawn_hint_label = Label.new()
	_spawn_hint_label.name = "SpawnHintLabel"
	_spawn_hint_label.text = "LMB: Player Spawn\nShift+LMB: Colonist Spawn"
	_spawn_hint_label.add_theme_font_size_override("font_size", 13)
	_spawn_hint_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	_spawn_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_badge.add_child(_mode_label)
	root.add_child(_mode_badge)

	# --- Map Info (Top Right) ---
	var info_panel := PanelContainer.new()
	info_panel.name = "MapInfoPanel"
	info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_panel.offset_left = -340.0
	info_panel.offset_top = 16.0
	info_panel.offset_right = -16.0
	info_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var info_style := StyleBoxFlat.new()
	info_style.bg_color = Color(0.08, 0.1, 0.14, 0.85)
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

	_meta_button = Button.new()
	_meta_button.name = "MetadataButton"
	_meta_button.text = "Metadata"
	_meta_button.tooltip_text = "Toggle map metadata panel"
	_meta_button.add_theme_font_size_override("font_size", 12)
	_meta_button.pressed.connect(toggle_metadata_panel)
	info_hbox.add_child(_meta_button)

	_terrain_button = Button.new()
	_terrain_button.name = "TerrainButton"
	_terrain_button.text = "Terrain"
	_terrain_button.tooltip_text = "Toggle terrain generator drawer"
	_terrain_button.add_theme_font_size_override("font_size", 12)
	_terrain_button.pressed.connect(toggle_terrain_drawer)
	info_hbox.add_child(_terrain_button)

	_map_info_label = Label.new()
	_map_info_label.name = "MapInfoLabel"
	_map_info_label.text = "Map: none"
	_map_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_map_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_info_label.add_theme_font_size_override("font_size", 13)
	_map_info_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	info_hbox.add_child(_map_info_label)

	root.add_child(info_panel)

	# --- Metadata Panel (Top Right, expandable) ---
	_metadata_panel = PanelContainer.new()
	_metadata_panel.name = "MetadataPanel"
	_metadata_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_metadata_panel.offset_left = -340.0
	_metadata_panel.offset_top = 56.0
	_metadata_panel.offset_right = -16.0
	_metadata_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_metadata_panel.visible = false

	var meta_style := StyleBoxFlat.new()
	meta_style.bg_color = Color(0.08, 0.1, 0.14, 0.92)
	meta_style.border_color = Color(0.3, 0.4, 0.55, 0.85)
	meta_style.set_border_width_all(1)
	meta_style.set_corner_radius_all(6)
	meta_style.set_content_margin_all(10)
	_metadata_panel.add_theme_stylebox_override("panel", meta_style)

	var meta_vbox := VBoxContainer.new()
	meta_vbox.name = "MetadataVBox"
	meta_vbox.add_theme_constant_override("separation", 6)
	_metadata_panel.add_child(meta_vbox)

	var meta_title := Label.new()
	meta_title.name = "MetaTitle"
	meta_title.text = "MAP METADATA"
	meta_title.add_theme_font_size_override("font_size", 13)
	meta_title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	meta_vbox.add_child(meta_title)

	# Display Name
	var name_lbl := Label.new()
	name_lbl.text = "Display Name:"
	name_lbl.add_theme_font_size_override("font_size", 11)
	meta_vbox.add_child(name_lbl)

	_meta_display_name_input = LineEdit.new()
	_meta_display_name_input.name = "DisplayNameInput"
	_meta_display_name_input.placeholder_text = "Map Name"
	_meta_display_name_input.add_theme_font_size_override("font_size", 12)
	meta_vbox.add_child(_meta_display_name_input)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = "Description:"
	desc_lbl.add_theme_font_size_override("font_size", 11)
	meta_vbox.add_child(desc_lbl)

	_meta_desc_input = TextEdit.new()
	_meta_desc_input.name = "DescriptionInput"
	_meta_desc_input.placeholder_text = "Map description..."
	_meta_desc_input.custom_minimum_size = Vector2(0, 60)
	_meta_desc_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_meta_desc_input.add_theme_font_size_override("font_size", 11)
	meta_vbox.add_child(_meta_desc_input)

	# Map Type
	var type_lbl := Label.new()
	type_lbl.text = "Map Type:"
	type_lbl.add_theme_font_size_override("font_size", 11)
	meta_vbox.add_child(type_lbl)

	_meta_type_option = OptionButton.new()
	_meta_type_option.name = "MapTypeOption"
	_meta_type_option.add_item("BASE (0)", 0)
	_meta_type_option.add_item("POI (1)", 1)
	_meta_type_option.add_item("BUILDING (2)", 2)
	_meta_type_option.add_item("TOWN (3)", 3)
	_meta_type_option.add_theme_font_size_override("font_size", 11)
	meta_vbox.add_child(_meta_type_option)

	# Difficulty
	var diff_lbl := Label.new()
	diff_lbl.text = "Difficulty (1-10):"
	diff_lbl.add_theme_font_size_override("font_size", 11)
	meta_vbox.add_child(diff_lbl)

	_meta_difficulty_spin = SpinBox.new()
	_meta_difficulty_spin.name = "DifficultySpin"
	_meta_difficulty_spin.min_value = 1
	_meta_difficulty_spin.max_value = 10
	_meta_difficulty_spin.step = 1
	_meta_difficulty_spin.value = 1
	meta_vbox.add_child(_meta_difficulty_spin)

	root.add_child(_metadata_panel)

	# --- Terrain Drawer (Top Right; mutually exclusive with the Metadata panel) ---
	_terrain_drawer = PanelContainer.new()
	_terrain_drawer.name = "TerrainDrawer"
	_terrain_drawer.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_terrain_drawer.offset_left = -340.0
	_terrain_drawer.offset_top = 56.0
	_terrain_drawer.offset_right = -16.0
	_terrain_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	_terrain_drawer.visible = false

	var drawer_style := StyleBoxFlat.new()
	drawer_style.bg_color = Color(0.08, 0.1, 0.14, 0.92)
	drawer_style.border_color = Color(0.3, 0.5, 0.4, 0.85)
	drawer_style.set_border_width_all(1)
	drawer_style.set_corner_radius_all(6)
	drawer_style.set_content_margin_all(10)
	_terrain_drawer.add_theme_stylebox_override("panel", drawer_style)

	var drawer_vbox := VBoxContainer.new()
	drawer_vbox.name = "TerrainDrawerVBox"
	drawer_vbox.add_theme_constant_override("separation", 6)
	_terrain_drawer.add_child(drawer_vbox)

	var drawer_title := Label.new()
	drawer_title.text = "TERRAIN GENERATOR"
	drawer_title.add_theme_font_size_override("font_size", 13)
	drawer_title.add_theme_color_override("font_color", Color(0.7, 0.95, 0.8))
	drawer_vbox.add_child(drawer_title)

	_terrain_mode_label = Label.new()
	_terrain_mode_label.name = "TerrainModeLabel"
	_terrain_mode_label.text = "Mode: —"
	_terrain_mode_label.add_theme_font_size_override("font_size", 12)
	_terrain_mode_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	drawer_vbox.add_child(_terrain_mode_label)

	_terrain_def_label = Label.new()
	_terrain_def_label.name = "TerrainDefLabel"
	_terrain_def_label.text = "Def: —"
	_terrain_def_label.add_theme_font_size_override("font_size", 11)
	_terrain_def_label.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	drawer_vbox.add_child(_terrain_def_label)

	# Heightmap section: minimap + span fields.
	_terrain_heightmap_section = VBoxContainer.new()
	_terrain_heightmap_section.name = "TerrainHeightmapSection"
	_terrain_heightmap_section.add_theme_constant_override("separation", 6)
	drawer_vbox.add_child(_terrain_heightmap_section)

	var preview_hbox := HBoxContainer.new()
	preview_hbox.add_theme_constant_override("separation", 10)
	_terrain_heightmap_section.add_child(preview_hbox)

	_terrain_minimap = TextureRect.new()
	_terrain_minimap.name = "TerrainMinimap"
	_terrain_minimap.custom_minimum_size = Vector2(96, 96)
	_terrain_minimap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_terrain_minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_hbox.add_child(_terrain_minimap)

	var axis_caption := Label.new()
	axis_caption.text = "image +x → world +x\nimage +y → world +z\n(1 px = 1 m)"
	axis_caption.add_theme_font_size_override("font_size", 10)
	axis_caption.add_theme_color_override("font_color", Color(0.55, 0.62, 0.72))
	axis_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	preview_hbox.add_child(axis_caption)

	var span_row := HBoxContainer.new()
	span_row.add_theme_constant_override("separation", 8)
	_terrain_heightmap_section.add_child(span_row)

	var start_lbl := Label.new()
	start_lbl.text = "Start:"
	start_lbl.add_theme_font_size_override("font_size", 11)
	span_row.add_child(start_lbl)

	_terrain_start_spin = SpinBox.new()
	_terrain_start_spin.min_value = -100.0
	_terrain_start_spin.max_value = 100.0
	_terrain_start_spin.step = 0.5
	_terrain_start_spin.value_changed.connect(_update_terrain_span_label)
	span_row.add_child(_terrain_start_spin)

	var range_lbl := Label.new()
	range_lbl.text = "Range:"
	range_lbl.add_theme_font_size_override("font_size", 11)
	span_row.add_child(range_lbl)

	_terrain_range_spin = SpinBox.new()
	_terrain_range_spin.min_value = 1.0
	_terrain_range_spin.max_value = 200.0
	_terrain_range_spin.step = 0.5
	_terrain_range_spin.value_changed.connect(_update_terrain_span_label)
	span_row.add_child(_terrain_range_spin)

	_terrain_span_label = Label.new()
	_terrain_span_label.text = ""
	_terrain_span_label.add_theme_font_size_override("font_size", 11)
	_terrain_span_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	_terrain_heightmap_section.add_child(_terrain_span_label)

	# Noise section: seed + frequency fields.
	_terrain_noise_section = VBoxContainer.new()
	_terrain_noise_section.name = "TerrainNoiseSection"
	_terrain_noise_section.add_theme_constant_override("separation", 6)
	drawer_vbox.add_child(_terrain_noise_section)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	_terrain_noise_section.add_child(seed_row)

	var seed_lbl := Label.new()
	seed_lbl.text = "Seed:"
	seed_lbl.add_theme_font_size_override("font_size", 11)
	seed_row.add_child(seed_lbl)

	_terrain_seed_spin = SpinBox.new()
	_terrain_seed_spin.min_value = 0.0
	_terrain_seed_spin.max_value = 999999.0
	_terrain_seed_spin.step = 1.0
	seed_row.add_child(_terrain_seed_spin)

	var freq_row := HBoxContainer.new()
	freq_row.add_theme_constant_override("separation", 8)
	_terrain_noise_section.add_child(freq_row)

	var freq_lbl := Label.new()
	freq_lbl.text = "Frequency:"
	freq_lbl.add_theme_font_size_override("font_size", 11)
	freq_row.add_child(freq_lbl)

	_terrain_freq_spin = SpinBox.new()
	_terrain_freq_spin.min_value = 0.001
	_terrain_freq_spin.max_value = 0.2
	_terrain_freq_spin.step = 0.001
	_terrain_freq_spin.value = 0.012
	freq_row.add_child(_terrain_freq_spin)

	# Image / removal actions + apply.
	var drawer_buttons := HBoxContainer.new()
	drawer_buttons.add_theme_constant_override("separation", 8)
	drawer_vbox.add_child(drawer_buttons)

	_terrain_pick_button = Button.new()
	_terrain_pick_button.name = "TerrainPickButton"
	_terrain_pick_button.text = "Convert to Heightmap…"
	_terrain_pick_button.tooltip_text = "Pick a grayscale heightmap image"
	_terrain_pick_button.add_theme_font_size_override("font_size", 11)
	_terrain_pick_button.pressed.connect(func() -> void: terrain_pick_image_requested.emit())
	drawer_buttons.add_child(_terrain_pick_button)

	_terrain_remove_button = Button.new()
	_terrain_remove_button.name = "TerrainRemoveButton"
	_terrain_remove_button.text = "Remove Terrain"
	_terrain_remove_button.tooltip_text = "Strip terrain_gen from the map — the smooth grid disappears on apply"
	_terrain_remove_button.add_theme_font_size_override("font_size", 11)
	_terrain_remove_button.pressed.connect(_on_terrain_remove_toggled)
	drawer_buttons.add_child(_terrain_remove_button)

	var terrain_warning := Label.new()
	terrain_warning.text = "Sculpted edits keep their absolute heights — changing the base may float or bury them."
	terrain_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	terrain_warning.add_theme_font_size_override("font_size", 10)
	terrain_warning.add_theme_color_override("font_color", Color(0.9, 0.7, 0.35))
	drawer_vbox.add_child(terrain_warning)

	var apply_btn := Button.new()
	apply_btn.text = "Apply & Reload"
	apply_btn.tooltip_text = "Save the terrain def and reload the map"
	apply_btn.add_theme_font_size_override("font_size", 12)
	apply_btn.pressed.connect(func() -> void: terrain_apply_requested.emit())
	drawer_vbox.add_child(apply_btn)

	root.add_child(_terrain_drawer)

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
	_hotkey_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotkey_panel.add_child(_hotkey_label)
	root.add_child(hotkey_panel)

	# --- Crosshair & Coordinate Readout (Center) ---
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
	h_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.add_child(h_line)

	var v_line := ColorRect.new()
	v_line.name = "VLine"
	v_line.color = Color(1.0, 1.0, 1.0, 0.75)
	v_line.offset_left = -1
	v_line.offset_right = 1
	v_line.offset_top = -6
	v_line.offset_bottom = 6
	v_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.add_child(v_line)

	_coord_label = Label.new()
	_coord_label.name = "CoordLabel"
	_coord_label.set_anchors_preset(Control.PRESET_CENTER)
	_coord_label.offset_top = 16.0
	_coord_label.offset_left = -150.0
	_coord_label.offset_right = 150.0
	_coord_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_coord_label.add_theme_font_size_override("font_size", 11)
	_coord_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 0.75))
	_coord_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coord_label.text = ""
	_crosshair.add_child(_coord_label)

	root.add_child(_crosshair)


# --- Block Palette API ---

func populate_block_library(library: BlockLibrary, selected_idx: int = 6) -> void:
	if library == null or _block_palette == null:
		return
	var items: Array[EditorPalettePanel.Item] = []
	var indices: Array[int] = library.get_base_indices()

	for idx in indices:
		var def: BlockDef = library.get_def_by_index(idx)
		if def == null:
			continue
		var item := EditorPalettePanelClass.Item.new()
		item.index = idx
		item.id = def.id
		item.display_name = def.display_name if not def.display_name.is_empty() else def.id.capitalize()
		item.label = "%s  [#%d]" % [item.display_name, idx]
		item.icon = def.icon if def.icon != null else def.texture
		item.tooltip = "%s (%s)\nVoxel Index: %d\nHP: %d%s" % [
			item.display_name,
			def.id,
			idx,
			def.hp,
			"\nType: Ground/Terrain" if def.is_terrain else "",
		]
		items.append(item)

	_block_palette.populate(items, selected_idx)


func populate_block_list(defs_by_index: Dictionary, selected_idx: int = 6) -> void:
	if _block_palette == null:
		return
	var items: Array[EditorPalettePanel.Item] = []
	var indices: Array = []
	var seen_ids: Dictionary = {}
	for idx in defs_by_index.keys():
		indices.append(idx)
	indices.sort()

	for idx_val in indices:
		var idx: int = int(idx_val)
		var def: BlockDef = defs_by_index.get(idx)
		if def == null or seen_ids.has(def.id):
			continue
		seen_ids[def.id] = true
		var item := EditorPalettePanelClass.Item.new()
		item.index = idx
		item.id = def.id
		item.display_name = def.display_name if not def.display_name.is_empty() else def.id.capitalize()
		item.label = "%s  [#%d]" % [item.display_name, idx]
		item.icon = def.icon if def.icon != null else def.texture
		item.tooltip = "%s (%s)\nVoxel Index: %d\nHP: %d%s" % [
			item.display_name,
			def.id,
			idx,
			def.hp,
			"\nType: Ground/Terrain" if def.is_terrain else "",
		]
		items.append(item)

	_block_palette.populate(items, selected_idx)


func select_block_by_index(global_idx: int) -> void:
	if _block_palette != null:
		_block_palette.select_by_index(global_idx)


func get_filtered_block_indices() -> Array[int]:
	return _block_palette.get_filtered_indices() if _block_palette != null else []


# --- Furniture Palette API ---

func populate_furniture_list(defs: Array[FurnitureDef], selected_idx: int = 0) -> void:
	_furniture_defs = defs
	_selected_global_idx = selected_idx
	if _furniture_palette == null:
		return

	var items: Array[EditorPalettePanel.Item] = []
	for i in range(defs.size()):
		var def := defs[i]
		if def == null:
			continue
		var item := EditorPalettePanelClass.Item.new()
		item.index = i
		item.id = def.id
		item.display_name = def.display_name if not def.display_name.is_empty() else def.id
		item.label = "%s  [%dx%dx%d]" % [item.display_name, def.dimensions.x, def.dimensions.y, def.dimensions.z]
		item.icon = def.icon
		item.tooltip = "%s (%s)\nDimensions: %dx%dx%d" % [
			item.display_name,
			def.id,
			def.dimensions.x,
			def.dimensions.y,
			def.dimensions.z,
		]
		items.append(item)

	_furniture_palette.populate(items, selected_idx)


func _on_furniture_search_changed(new_text: String) -> void:
	if _furniture_palette != null:
		_furniture_palette._on_search_changed(new_text)


func _on_furniture_item_selected(list_idx: int) -> void:
	if _furniture_palette != null:
		_furniture_palette._on_item_selected(list_idx)


func select_furniture_by_index(global_idx: int) -> void:
	_selected_global_idx = global_idx
	if _furniture_palette != null:
		_furniture_palette.select_by_index(global_idx)


func get_filtered_furniture_indices() -> Array[int]:
	return _furniture_palette.get_filtered_indices() if _furniture_palette != null else []


func populate_structure_list(defs: Array[StructureDef], selected_idx: int = 0) -> void:
	if _structure_browser != null:
		_structure_browser.populate(defs, selected_idx)


func select_structure_by_index(global_idx: int) -> void:
	if _structure_browser != null:
		_structure_browser.select_by_index(global_idx)


func get_filtered_structure_indices() -> Array[int]:
	return _structure_browser.get_filtered_indices() if _structure_browser != null else []


func set_structure_info(def: StructureDef) -> void:
	if _structure_browser != null:
		_structure_browser.set_selected_info(def)


# --- Focus and Mode API ---

func is_search_focused() -> bool:
	if _structure_browser != null and _structure_browser.is_search_focused():
		return true
	if _furniture_palette != null and _furniture_palette.is_search_focused():
		return true
	if _block_palette != null and _block_palette.is_search_focused():
		return true
	return false


func unfocus_search() -> void:
	if _structure_browser != null and _structure_browser.is_search_focused():
		_structure_browser.unfocus_search()
	if _furniture_palette != null and _furniture_palette.is_search_focused():
		_furniture_palette.unfocus_search()
	if _block_palette != null and _block_palette.is_search_focused():
		_block_palette.unfocus_search()


func is_metadata_focused() -> bool:
	if _meta_display_name_input != null and _meta_display_name_input.has_focus():
		return true
	if _meta_desc_input != null and _meta_desc_input.has_focus():
		return true
	if _meta_type_option != null and _meta_type_option.has_focus():
		return true
	if _meta_difficulty_spin != null and _meta_difficulty_spin.get_line_edit() != null and _meta_difficulty_spin.get_line_edit().has_focus():
		return true
	return false


func is_any_input_focused() -> bool:
	return is_search_focused() or is_metadata_focused() or is_terrain_drawer_focused()


# --- Information display helpers ---

func set_rotation_info(rot_index: int, axis_name: String = "Y [Yaw]") -> void:
	if _orientation_label != null:
		var b := VoxelBlockEncoder.rot_index_to_basis(rot_index)
		var euler := b.get_euler()
		var yaw_deg := roundi(rad_to_deg(euler.y))
		var pitch_deg := roundi(rad_to_deg(euler.x))
		_orientation_label.text = "Rot: #%d [Y %d°, X %d°] | Axis: %s [R]" % [rot_index, yaw_deg, pitch_deg, axis_name]


func set_block_info(block_name: String, diameter: int, id_str: String = "", voxel_idx: int = -1, rot_idx: int = 0, axis_name: String = "Y [Yaw]") -> void:
	if _block_palette != null:
		var display_id := id_str
		if voxel_idx > 0:
			display_id = "%s (Voxel #%d)" % [id_str if not id_str.is_empty() else "-", voxel_idx]
		_block_palette.set_selected_info(block_name, display_id)
	if _brush_label != null:
		_brush_label.text = "Brush: %dx%dx%d [B+Wheel]" % [diameter, diameter, diameter]
	set_rotation_info(rot_idx, axis_name)


func set_sculpt_info(radius: float) -> void:
	if _terrain_radius_label != null:
		_terrain_radius_label.text = "Radius: %.1f m" % radius


func set_terrain_info(material_name: String, radius: float) -> void:
	if _terrain_material_label != null:
		_terrain_material_label.text = "Material: " + material_name.capitalize()
	set_sculpt_info(radius)


func set_furniture_info(name: String, yaw_quarters: int = 0, dims: Vector3i = Vector3i.ONE, id_str: String = "", axis_name: String = "Y [Yaw]") -> void:
	if _furniture_palette != null:
		_furniture_palette.set_selected_info(name, id_str)
	if _yaw_label != null:
		var deg := (yaw_quarters % 4) * 90
		_yaw_label.text = "Rotation: %d° | Axis: %s [R: Axis, Wheel: Rot]" % [deg, axis_name]
	if _furniture_dims_label != null:
		_furniture_dims_label.text = "Size: %dx%dx%d (WxHxD)" % [dims.x, dims.y, dims.z]


func set_terrain_available(available: bool) -> void:
	if _terrain_warning_label != null:
		_terrain_warning_label.visible = not available


func set_coordinates(pos: Vector3) -> void:
	if _coord_label != null:
		_coord_label.text = "X: %.1f  Y: %.1f  Z: %.1f" % [pos.x, pos.y, pos.z]


func clear_coordinates() -> void:
	if _coord_label != null:
		_coord_label.text = ""


func set_metadata(display_name: String, description: String, map_type: int, difficulty: int) -> void:
	if _meta_display_name_input != null:
		_meta_display_name_input.text = display_name
	if _meta_desc_input != null:
		_meta_desc_input.text = description
	if _meta_type_option != null:
		_meta_type_option.selected = map_type
	if _meta_difficulty_spin != null:
		_meta_difficulty_spin.value = float(difficulty)


func get_metadata_edits() -> Dictionary:
	var out := {}
	if _meta_display_name_input != null:
		out["display_name"] = _meta_display_name_input.text
	if _meta_desc_input != null:
		out["description"] = _meta_desc_input.text
	if _meta_type_option != null:
		out["map_type"] = _meta_type_option.selected
	if _meta_difficulty_spin != null:
		out["difficulty"] = int(_meta_difficulty_spin.value)
	return out


func toggle_metadata_panel() -> void:
	if _metadata_panel != null:
		_metadata_panel.visible = not _metadata_panel.visible
		if _metadata_panel.visible and _terrain_drawer != null:
			_terrain_drawer.visible = false


# --- Terrain drawer API ---------------------------------------------------------

## Refresh the drawer from the map's terrain def; resets any pending image /
## removal state. Called on every map load (and after apply-triggered reloads).
func set_terrain_drawer_state(terrain_def: TerrainGenDef) -> void:
	if _terrain_drawer == null:
		return
	_drawer_has_terrain = terrain_def != null
	_drawer_is_heightmap = terrain_def != null and terrain_def.heightmap != null
	_pending_heightmap = null
	_terrain_remove_pending = false
	_update_remove_button()
	_terrain_mode_label.text = "Mode: " + (
		"Heightmap (image)" if _drawer_is_heightmap
		else ("Procedural (noise)" if _drawer_has_terrain else "None (blocky only)")
	)
	if terrain_def == null:
		_terrain_def_label.text = "Def: —"
	else:
		var def_name := terrain_def.resource_path.get_file()
		_terrain_def_label.text = "Def: " + (def_name if not def_name.is_empty() else terrain_def.id)
	_terrain_heightmap_section.visible = _drawer_is_heightmap
	_terrain_noise_section.visible = _drawer_has_terrain and not _drawer_is_heightmap
	_terrain_pick_button.text = (
		"Replace Image…" if _drawer_is_heightmap
		else ("Convert to Heightmap…" if _drawer_has_terrain else "Add Heightmap…")
	)
	_terrain_remove_button.visible = _drawer_has_terrain
	if _drawer_is_heightmap:
		_terrain_start_spin.value = terrain_def.height_start
		_terrain_range_spin.value = terrain_def.height_range
		_terrain_minimap.texture = _minimap_from_texture(terrain_def.heightmap)
		_update_terrain_span_label()
	elif _drawer_has_terrain:
		_terrain_seed_spin.value = terrain_def.noise_seed
		_terrain_freq_spin.value = terrain_def.noise_frequency
		_terrain_minimap.texture = null


## Minimap preview of a def's heightmap texture — uncompressed L8, mirroring
## what the generator will consume.
func _minimap_from_texture(tex: Texture2D) -> ImageTexture:
	if tex == null:
		return null
	var image := tex.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_L8)
	return ImageTexture.create_from_image(image)


## Current drawer values for the editor's apply handler: span fields, noise
## fields, a picked-but-unapplied image, and the removal toggle.
func get_terrain_drawer_edits() -> Dictionary:
	if _terrain_start_spin == null:
		return {}
	return {
		"height_start": _terrain_start_spin.value,
		"height_range": _terrain_range_spin.value,
		"noise_seed": int(_terrain_seed_spin.value),
		"noise_frequency": _terrain_freq_spin.value,
		"pending_image": _pending_heightmap,
		"remove": _terrain_remove_pending,
	}


## Preview a picked image before Apply commits it: minimap + heightmap fields.
func set_pending_heightmap_image(image: Image) -> void:
	_pending_heightmap = image
	if image != null:
		_terrain_minimap.texture = ImageTexture.create_from_image(image)
	# Picking an image implies heightmap mode on apply; flip the visible section
	# so the span fields match what will be written.
	_drawer_is_heightmap = true
	_terrain_heightmap_section.visible = true
	_terrain_noise_section.visible = false
	_terrain_mode_label.text = "Mode: Heightmap (image)*"
	_terrain_pick_button.text = "Replace Image…"


func is_terrain_drawer_visible() -> bool:
	return _terrain_drawer != null and _terrain_drawer.visible


func toggle_terrain_drawer() -> void:
	if _terrain_drawer == null:
		return
	_terrain_drawer.visible = not _terrain_drawer.visible
	if _terrain_drawer.visible and _metadata_panel != null:
		_metadata_panel.visible = false


func close_terrain_drawer() -> void:
	if _terrain_drawer != null:
		_terrain_drawer.visible = false


func is_terrain_drawer_focused() -> bool:
	for spin: SpinBox in [_terrain_start_spin, _terrain_range_spin, _terrain_seed_spin, _terrain_freq_spin]:
		if spin != null and spin.get_line_edit() != null and spin.get_line_edit().has_focus():
			return true
	return false


func _update_terrain_span_label(_value: float = 0.0) -> void:
	if _terrain_span_label == null or _terrain_start_spin == null:
		return
	var start := _terrain_start_spin.value
	_terrain_span_label.text = "→ %.1f m … %.1f m" % [start, start + _terrain_range_spin.value]


func _on_terrain_remove_toggled() -> void:
	_terrain_remove_pending = not _terrain_remove_pending
	_update_remove_button()


func _update_remove_button() -> void:
	if _terrain_remove_button == null:
		return
	_terrain_remove_button.text = "Keep Terrain (undo)" if _terrain_remove_pending else "Remove Terrain"


func set_mode(mode: int) -> void:
	if mode < 0 or mode >= MODE_NAMES.size():
		return
	var key_num := mode + 1
	_mode_label.text = "[ F%d ] %s" % [key_num, MODE_NAMES[mode]]
	_hotkey_label.text = MODE_HOTKEYS[mode]

	if _block_palette != null:
		_block_palette.visible = (mode == 1) # Mode.BLOCK
	if _terrain_info_panel != null:
		_terrain_info_panel.visible = (mode == 2) # Mode.TERRAIN
	if _furniture_palette != null:
		_furniture_palette.visible = (mode == 3) # Mode.FURNITURE
	if _spawn_info_panel != null:
		_spawn_info_panel.visible = (mode == 4) # Mode.SPAWN
	if _structure_browser != null:
		_structure_browser.visible = (mode == 5) # Mode.STRUCTURE

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
			5: # STRUCTURE
				badge_style.border_color = Color(0.65, 0.4, 0.85, 0.9)


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
