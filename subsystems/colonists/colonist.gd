extends CharacterBody3D
class_name Colonist

@export var colonist_def: ColonistDef = preload("res://data/colonists/default_colonist.tres")
var colonist_id: String
var display_name: String
var labor_priorities: Dictionary
var raid_stance: int
var current_job: Job
var skill_set: SkillSet
var stamina_component: StaminaComponent
var pathfinder: VoxelPathfinder

var _current_hp: int = 100
var _is_dead: bool = false

func _ready() -> void:
	colonist_id = Tools.generate_uuid()
	display_name = colonist_def.display_name
	labor_priorities = colonist_def.default_labor_priorities
	raid_stance = colonist_def.default_raid_stance
	current_job = null
	skill_set = $SkillSet
	stamina_component = $StaminaComponent
	pathfinder = $VoxelPathfinder
	_current_hp = colonist_def.max_hp


func take_damage(amount: int, source: Node) -> void:
	if _is_dead:
		return
	_current_hp -= amount
	if _current_hp <= 0:
		_current_hp = 0
		_die()


func heal(amount: int) -> void:
	if _is_dead:
		return
	_current_hp = clamp(_current_hp + amount, 0, colonist_def.max_hp)


func _die() -> void:
	_is_dead = true
	EventBus.colonist_died.emit(colonist_id)


func set_labor_priority(labord_id: String, priority: int) -> void:
	# TODO: Add a guard vs configured min/max values
	labor_priorities[labord_id] = priority


func set_raid_stance(stance: int) -> void:
	# TODO: Add a guard vs configured min/max values
	raid_stance = stance


# --- SaveSystem contract -----------------------------------------------------
# Owned scalar/dict state + world position. Component sub-state (SkillSet,
# StaminaComponent, VoxelPathfinder) and current_job are excluded — they are
# stubs / not yet live. ColonistDef is static data (re-resolved from the def at
# spawn), not persisted here. NOTE: colonists are not yet spawned by Colony
# (roster is a stub), so this is future-ready plumbing.

func serialize() -> Dictionary:
	return {
		"colonist_id": colonist_id,
		"display_name": display_name,
		"labor_priorities": labor_priorities.duplicate(true),
		"raid_stance": raid_stance,
		"hp": _current_hp,
		"is_dead": _is_dead,
		"pos": [global_position.x, global_position.y, global_position.z],
	}


func deserialize(data: Dictionary) -> void:
	colonist_id = data.get("colonist_id", colonist_id)
	display_name = data.get("display_name", display_name)
	labor_priorities = data.get("labor_priorities", {}).duplicate(true)
	raid_stance = int(data.get("raid_stance", raid_stance))
	_current_hp = int(data.get("hp", _current_hp))
	_is_dead = bool(data.get("is_dead", false))
	var p: Array = data.get("pos", [global_position.x, global_position.y, global_position.z])
	global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
