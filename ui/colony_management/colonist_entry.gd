extends Button
class_name ColonistEntry
## Entry button representing a single colonist in the roster list.
## Emits selected(colonist) when pressed.

signal selected(colonist: Colonist)

var _colonist: Colonist = null

@onready var _name_label: Label = %NameLabel
@onready var _hp_label: Label = %HpLabel
@onready var _rest_label: Label = %RestLabel
@onready var _hunger_label: Label = %HungerLabel
@onready var _activity_label: Label = %ActivityLabel
@onready var _moodlet_container: HBoxContainer = %MoodletContainer


func setup(colonist: Colonist) -> void:
	_colonist = colonist
	if not is_node_ready():
		await ready
	refresh()


func get_colonist() -> Colonist:
	return _colonist


## Re-renders name, health, needs, moodlets and activity from live colonist state.
func refresh() -> void:
	if _colonist == null or not is_instance_valid(_colonist):
		return
	_name_label.text = _colonist.display_name
	_hp_label.text = "HP: %d/%d" % [_colonist.get_hp(), _colonist.get_max_hp()]
	if _colonist.needs != null:
		var hunger: int = int(round(_colonist.needs.get_need(&"hunger") * 100.0))
		var rest: int = int(round(_colonist.needs.get_need(&"rest") * 100.0))
		_rest_label.text = "Rest: %d%%" % rest
		_hunger_label.text = "Hunger: %d%%" % hunger
	else:
		_rest_label.text = "Rest: n/a"
		_hunger_label.text = "Hunger: n/a"
	
	# 1. Moodlet Display: Populate active moodlet icon indicators.
	_update_moodlets()

	var act: String = "Idle"
	var bt: BTPlayer = _colonist.get_node_or_null("BTPlayer") as BTPlayer
	if bt != null and bt.blackboard != null and bt.blackboard.has_var(&"active_job"):
		var job = bt.blackboard.get_var(&"active_job")
		if job != null:
			var t: String = str(job.title) if "title" in job else ""
			act = t if t != "" else str(job.get("labor_id", "Work")).capitalize()
	elif _colonist.current_job != null and is_instance_valid(_colonist.current_job):
		var t: String = _colonist.current_job.title
		act = t if t != "" else _colonist.current_job.labor_id.capitalize()
	elif bt != null and bt.blackboard != null and bt.blackboard.has_var(&"current_goal"):
		var g: StringName = bt.blackboard.get_var(&"current_goal")
		if g != &"none":
			act = String(g).capitalize()
	_activity_label.text = "Act: %s" % act


func _update_moodlets() -> void:
	## Auxiliary: Clears and instantiates TextureRect icons for all active colonist moodlets.
	if _moodlet_container == null or _colonist == null:
		return
	
	for child in _moodlet_container.get_children():
		child.queue_free()
	
	var active_moodlets: Array[Dictionary] = _colonist.get_active_moodlets()
	for moodlet in active_moodlets:
		var tex: Texture2D = moodlet.get("texture", null)
		if tex == null:
			continue
		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(18, 18)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.texture = tex
		icon_rect.mouse_filter = Control.MOUSE_FILTER_PASS
		var m_name: String = str(moodlet.get("name", ""))
		if not m_name.is_empty():
			icon_rect.tooltip_text = m_name
		_moodlet_container.add_child(icon_rect)


func _pressed() -> void:
	if _colonist != null and is_instance_valid(_colonist):
		selected.emit(_colonist)

