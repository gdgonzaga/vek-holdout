extends Node
class_name ColonistAI

var state_machine: ColonistAIStateMachine

@onready var _colonist: Colonist = get_parent()

var _pathfinder: VoxelPathfinder
var _current_path: Array[Vector3i]
var _work_timer: float


func _ready() -> void:
	pass