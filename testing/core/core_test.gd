extends Node
## Core skeleton test: verifies autoloads load, day rolls, pause freezes the sim.
##
## Instances main.tscn (which brings the autoloads + a base MapRoot), drops the
## player into the map, and shows live state: current day, paused flag, and a
## hint. Keys:
##   Esc       toggle pause (Core-owned; sim should freeze when paused)
##   M         force midnight (TimeSystem.advance_to_midnight -> day++ + autosave stub)
##   WASD/Shift/Space  player movement (player.gd)

var _main: Node
var _label: Label

func _ready() -> void:
	_main = preload("res://subsystems/core/main.tscn").instantiate()
	add_child(_main)

	# Drop the player into the base MapRoot that main just loaded.
	var map: Node = GameState.map_root
	var player: Node3D = preload("res://subsystems/player/player.tscn").instantiate()
	player.global_position = Vector3(0, 5, 0)
	map.add_child(player)

	# VoxelViewer so terrain streams + collision around the player.
	var viewer := VoxelViewer.new()
	viewer.requires_visuals = true
	if "requires_collision" in viewer:
		viewer.set("requires_collision", true)
	player.add_child(viewer)

	# Live state readout.
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(10, 10)
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(_label)

	GameState.day_changed.connect(_on_day_changed)
	GameState.pause_state_changed.connect(func(_p): pass)

func _process(_delta: float) -> void:
	if _label:
		_label.text = "=== Core skeleton test ===\n" \
			+ "Day: %d   Paused: %s   Scene: %s\n" \
			  % [GameState.current_day, GameState.paused, GameState.current_scene_id] \
			+ "Time of day: %.2f\n" % TimeSystem.get_time_of_day_fraction() \
			+ "Esc: pause   M: force midnight   WASD: move"

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# Core (main.gd) handles pause; this is just a fallback if main isn't in
		# the input chain. Avoids double-toggle by checking source.
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_M:
		TimeSystem.advance_to_midnight()

func _on_day_changed(new_day: int) -> void:
	print("[CoreTest] day_changed -> %d (autosave stub should have warned)" % new_day)
