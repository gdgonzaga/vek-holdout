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
# Labor ids (LaborDef.id in data/labors/), NOT skills. mining/farming above are
# skills; priorities select which Labors a colonist will accept jobs for.
@export var default_labor_priorities: Dictionary = {
	"construction": 1,
	"crafting": 1,
	"hauling": 1,
}
