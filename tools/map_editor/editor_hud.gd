class_name EditorHUD
extends CanvasLayer
## In-editor HUD overlay providing mode indicator, map info, crosshair, and hotkeys.
##
## Owned by MapEditor. Built procedurally in code.

var _mode_badge: PanelContainer
var _mode_label: Label
var _map_info_label: Label
var _hotkey_label: Label
var _crosshair: Control

const MODE_NAMES: Array[String] = [
	"NAVIGATE",
	"BLOCK",
	"TERRAIN",
	"FURNITURE",
	"SPAWN",
]

const MODE_HOTKEYS: Array[String] = [
	"[LMB] Look   [WASD/Space/C] Fly   [Shift] Fast   [Esc] Release Mouse / Menu   [F1-F5] Modes",
	"[LMB] Paint   [Shift+LMB] Erase   [[/]] Block   [B+Scroll] Radius   [Ctrl+S] Save   [F1-F5] Modes",
	"[LMB] Add   [Shift+LMB] Carve   [[/]] Radius   [Ctrl+S] Save   [F1-F5] Modes",
	"[LMB] Place   [Shift+LMB] Remove   [Tab] Cycle   [R] Rotate   [Ctrl+S] Save   [F1-F5] Modes",
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
	info_panel.offset_left = -260.0
	info_panel.offset_top = 16.0
	info_panel.offset_right = -16.0
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var info_style := StyleBoxFlat.new()
	info_style.bg_color = Color(0.08, 0.1, 0.14, 0.8)
	info_style.border_color = Color(0.2, 0.25, 0.35, 0.8)
	info_style.set_border_width_all(1)
	info_style.set_corner_radius_all(4)
	info_style.set_content_margin_all(8)
	info_panel.add_theme_stylebox_override("panel", info_style)

	_map_info_label = Label.new()
	_map_info_label.name = "MapInfoLabel"
	_map_info_label.text = "Map: none"
	_map_info_label.add_theme_font_size_override("font_size", 13)
	_map_info_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.95))
	info_panel.add_child(_map_info_label)
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


func set_mode(mode: int) -> void:
	if mode < 0 or mode >= MODE_NAMES.size():
		return
	var key_num := mode + 1
	_mode_label.text = "[ F%d ] %s" % [key_num, MODE_NAMES[mode]]
	_hotkey_label.text = MODE_HOTKEYS[mode]

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
