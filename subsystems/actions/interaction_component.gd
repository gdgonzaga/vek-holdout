class_name InteractionComponent
extends Node

var action_options: Array[ActionOption] = []
@export var display_name: String = ""

## Optional live status line the parent furniture sets at runtime (e.g. a
## blueprint's "Plank 3/15"). InteractLabel shows it under the action hint.
## Empty by default so it stays hidden.
var info_text: String = ""

const _interaction_ui_scene: PackedScene = preload("res://ui/interaction/interaction_ui.tscn")

var _actor: Node = null
var _target: Node = null


func interact(actor: Node) -> void:
	_open_interaction_ui(actor, get_parent(), action_options, self)


func _open_interaction_ui(actor: Node, target: Node, options: Array[ActionOption], component: InteractionComponent) -> void:
	_actor = actor
	_target = target
	var ui: Control = _interaction_ui_scene.instantiate()
	ui.action_selected.connect(_on_action_selected)

	# Mount on a CanvasLayer first so @onready nodes resolve before setup().
	var layer := get_tree().get_first_node_in_group("hud_layer") as CanvasLayer
	if layer == null:
		layer = get_tree().get_first_node_in_group("ui_layer") as CanvasLayer
	if layer == null:
		push_warning("InteractionComponent: no CanvasLayer found, adding child to parent")
		target.add_child(ui)
	else:
		layer.add_child(ui)
	ui.setup(actor, target, options, component)


func _on_action_selected(option: ActionOption) -> void:
	# The UI frees itself after emitting; the cursor round-trip is owned by
	# UiGate (the action may open another panel, e.g. storage).
	option.action.execute(_actor, _target)
