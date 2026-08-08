extends Control
## Pop-up interaction menu. Lists available action buttons from an
## InteractionComponent; each button calls GameAction.execute on press.
##
## Lifecycle:
##   instantiated by InteractionComponent.interact(actor, target)
##   mounted on a CanvasLayer, destroyed on close / action taken.

signal closed()
signal action_selected(option: ActionOption)

@onready var _list: VBoxContainer = $Panel/VBox/List
@onready var _label: Label = $Panel/VBox/Label

var _actor: Node = null
var _target: Node = null


## Populate the button list from the target's action options.
func setup(actor: Node, target: Node, options: Array[ActionOption], component: InteractionComponent) -> void:
	_actor = actor
	_target = target

	for child in _list.get_children():
		child.queue_free()

	_label.text = component.display_name if component.display_name != "" else target.name

	for option in options:
		var btn := Button.new()
		btn.text = option.action.label
		btn.disabled = not option.is_available(actor, target)
		btn.pressed.connect(_on_option_pressed.bind(option))
		_list.add_child(btn)

	# Nothing to show — close immediately.
	if _list.get_child_count() == 0:
		queue_free()


func _on_option_pressed(option: ActionOption) -> void:
	action_selected.emit(option)
	close()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
