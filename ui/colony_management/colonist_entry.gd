extends Button
class_name ColonistEntry
## Entry button representing a single colonist in the roster list.
## Emits selected(colonist) when pressed.

signal selected(colonist: Colonist)

var _colonist: Colonist = null

@onready var _name_label: Label = %NameLabel
@onready var _hp_label: Label = %HpLabel
@onready var _stamina_label: Label = %StaminaLabel
@onready var _mood_label: Label = %MoodLabel
@onready var _activity_label: Label = %ActivityLabel


func setup(colonist: Colonist) -> void:
	_colonist = colonist
	if not is_node_ready():
		await ready
	_update_display()


func get_colonist() -> Colonist:
	return _colonist


func _update_display() -> void:
	if _colonist == null or not is_instance_valid(_colonist):
		return
	_name_label.text = _colonist.display_name
	_hp_label.text = "HP: %d/%d" % [_colonist.get_hp(), _colonist.get_max_hp()]
	_stamina_label.text = "Stam: 100/100 (Stub)"
	_mood_label.text = "Mood: Neutral (Stub)"
	
	var act: String = "Idle"
	if _colonist.current_job != null and is_instance_valid(_colonist.current_job):
		var t: String = _colonist.current_job.title
		act = t if t != "" else _colonist.current_job.labor_id.capitalize()
	_activity_label.text = "Act: %s" % act


func _pressed() -> void:
	if _colonist != null and is_instance_valid(_colonist):
		selected.emit(_colonist)
