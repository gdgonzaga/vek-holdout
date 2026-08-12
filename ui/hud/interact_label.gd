extends VBoxContainer
## Displays the targeted interactable's name and default action hint below the
## crosshair. Self-contained: hud.gd calls update_display() on interactable
## changes, this node handles visibility and label content.

const _GREEN := Color("#7dff7d")
const _RED := Color("#ff7d7d")

@onready var _name_label: Label = $NameLabel
@onready var _action_label: Label = $ActionLabel
@onready var _info_label: Label = $InfoLabel


func _ready() -> void:
	visible = false


## Called by hud.gd when the targeted interactable changes.
## Pass null to hide everything.
func update_display(component: InteractionComponent, player: Player) -> void:
	if component == null:
		visible = false
		return

	visible = true
	var target: Node = component.get_parent()

	# Name: label > display_name > node name.
	var tlabel = target.get("label")
	if tlabel != null and tlabel != "":
		_name_label.text = str(tlabel)
	elif component.display_name != "":
		_name_label.text = component.display_name
	else:
		_name_label.text = target.name

	# Live status line the furniture sets on the component (e.g. "Plank 3/15").
	# Populated before the action early-return so it shows even with no options.
	if component.info_text != "":
		_info_label.text = component.info_text
		_info_label.visible = true
	else:
		_info_label.visible = false

	# Action hint from first option.
	if component.action_options.is_empty():
		_action_label.visible = false
		return

	var option: ActionOption = component.action_options[0]
	if option.action == null:
		_action_label.visible = false
		return

	_action_label.visible = true
	_action_label.text = "[E] %s  ·  [hold E] more" % option.action.label

	var available := option.is_available(player, target)
	_action_label.add_theme_color_override("font_color", _GREEN if available else _RED)
