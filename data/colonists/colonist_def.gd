extends Resource
class_name ColonistDef

@export var max_hp: int = 100
@export var base_move_speed: float = 3.5
@export var sprint_multiplier: float = 1.5
@export var stamina_drain_rate: float = 1.0
@export var breath_costs: Dictionary = {
	"sprint": 1.0,
	"jump": 1.0,
}
@export var starting_skills: Dictionary = {
	"mining": {
		"xp": 0,
		"level": 1,
	},
	"farming": {
		"xp": 0,
		"level": 1,
	},
}
@export var default_labor_priorities: Dictionary = {
	"mining": 1,
	"farming": 1,
}
