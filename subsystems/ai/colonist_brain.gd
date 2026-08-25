## Subsystem: AI / Brain
## Utility AI goal arbitration component that evaluates needs and sets blackboard goals.
class_name ColonistBrain
extends Node

@export var bt_player: BTPlayer

var _needs: ColonistNeeds
var _poll_timer: float = 0.0
const EVAL_INTERVAL: float = 1.5


func _ready() -> void:
	var colonist := get_parent()
	if colonist:
		_needs = colonist.get_node_or_null("ColonistNeeds") as ColonistNeeds
		if not bt_player:
			bt_player = colonist.get_node_or_null("BTPlayer") as BTPlayer


func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= EVAL_INTERVAL:
		_poll_timer = 0.0
		evaluate_goals()


## Evaluates current desires and writes winning goal to LimboAI Blackboard
func evaluate_goals() -> void:
	if not bt_player or not bt_player.blackboard:
		return
		
	# Phase 1 stub: Defaults to &"work" to drive the primary job execution branch
	bt_player.blackboard.set_var(&"current_goal", &"work")
