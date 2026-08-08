class_name InteractionComponent
extends Node

var action_options: Array[ActionOption] = []
@export var display_name: String = ""
const _interaction_ui_scene: PackedScene = preload("res://ui/interaction/interaction_ui.tscn")

var _actor: Node = null
var _target: Node = null


func interact(actor: Node) -> void:
	_open_interaction_ui(actor, get_parent(), action_options, self)


func _open_interaction_ui(actor: Node, target: Node, options: Array[ActionOption], component: InteractionComponent) -> void:
	_actor = actor
	_target = target
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var ui: Control = _interaction_ui_scene.instantiate()
	ui.action_selected.connect(_on_action_selected)
	ui.closed.connect(_on_ui_closed)

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
	option.action.execute(_actor, _target)
	close()


func _on_ui_closed() -> void:
	close()


func close() -> void:
	# Re-capture mouse after interaction menu is dismissed.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
