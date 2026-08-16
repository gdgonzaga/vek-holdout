extends Button
class_name LaborCell
## A single cell in the Work Priority Matrix representing a colonist's priority for a labor.
## Displays priority number (0..5), color-coded from gray (0) to bright green (5).
## Left-click increments, right-click decrements (clamped at 0 and 5).

signal priority_changed(colonist: Colonist, labor_id: String, new_priority: int)

const MIN_PRIORITY := 0
const MAX_PRIORITY := 5

const PRIORITY_COLORS := [
	Color(0.5, 0.5, 0.5, 1.0),      # 0: Gray (Disabled)
	Color(0.4, 0.75, 0.85, 1.0),    # 1: Soft Teal/Cyan
	Color(0.55, 0.85, 0.45, 1.0),   # 2: Soft Light Green
	Color(0.35, 0.9, 0.35, 1.0),    # 3: Green
	Color(0.15, 0.95, 0.25, 1.0),   # 4: Vivid Green
	Color(0.0, 1.0, 0.35, 1.0),     # 5: Bright Green (Highest)
]

var _colonist: Colonist = null
var _labor_id: String = ""
var _labor_name: String = ""


func setup(colonist: Colonist, labor_id: String, labor_name: String) -> void:
	_colonist = colonist
	_labor_id = labor_id
	_labor_name = labor_name
	_update_display()


func get_colonist() -> Colonist:
	return _colonist


func get_labor_id() -> String:
	return _labor_id


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_change_priority(1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_change_priority(-1)
			accept_event()


func _change_priority(delta: int) -> void:
	if _colonist == null or not is_instance_valid(_colonist):
		return
	var current: int = int(_colonist.labor_priorities.get(_labor_id, 0))
	var new_priority: int = clampi(current + delta, MIN_PRIORITY, MAX_PRIORITY)
	if new_priority != current:
		_colonist.set_labor_priority(_labor_id, new_priority)
		_update_display()
		priority_changed.emit(_colonist, _labor_id, new_priority)


func _update_display() -> void:
	if _colonist == null or not is_instance_valid(_colonist):
		text = "0"
		return

	var prio: int = clampi(int(_colonist.labor_priorities.get(_labor_id, 0)), MIN_PRIORITY, MAX_PRIORITY)
	text = str(prio)

	var color: Color = PRIORITY_COLORS[prio]
	add_theme_color_override("font_color", color)
	add_theme_color_override("font_hover_color", color.lightened(0.15))
	add_theme_color_override("font_pressed_color", color.darkened(0.15))

	tooltip_text = "%s — %s\nPriority: %d (Left-click: +1, Right-click: -1)" % [
		_colonist.display_name,
		_labor_name if _labor_name != "" else _labor_id.capitalize(),
		prio
	]
