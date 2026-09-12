## Subsystem: AI / Needs
## Manages colonist need levels (hunger, rest, recreation) and calculates deficits for Utility AI (ARCH §6).
class_name ColonistNeeds
extends Node

static var _cached_need_defs: Dictionary = {}
static var _defs_loaded: bool = false

## Default base need levels (1.0 = satisfied, 0.0 = fully depleted)
var needs: Dictionary = {
	&"hunger": 1.0,
	&"rest": 1.0,
	&"recreation": 1.0
}


static func _ensure_need_defs_loaded() -> void:
	if _defs_loaded:
		return
	_defs_loaded = true
	var dir_path := "res://data/needs/"
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res := load(dir_path + fname)
			if res != null and "id" in res and res.id != &"":
				_cached_need_defs[res.id] = res
		fname = dir.get_next()


static func get_need_defs() -> Dictionary:
	_ensure_need_defs_loaded()
	return _cached_need_defs


static func reload() -> void:
	_cached_need_defs.clear()
	_defs_loaded = false
	_ensure_need_defs_loaded()


var _hunger_comp: HungerComponent = null


func _ready() -> void:
	var defs := get_need_defs()
	for need_id in defs:
		if not needs.has(need_id):
			needs[need_id] = 1.0


func _process(delta: float) -> void:
	var defs := get_need_defs()
	var hunger_comp := _resolve_hunger_component()

	for need_id in defs:
		if need_id == &"hunger" and hunger_comp != null:
			# 1. Hunger Synchronization: Pull updated ratio from HungerComponent to prevent duplicate decay.
			needs[&"hunger"] = hunger_comp.get_hunger_ratio()
			continue

		var def: Resource = defs[need_id]
		var decay_per_hour: float = def.decay_per_game_hour
		var decay_per_sec: float = TimeSystem.rate_per_game_hour_to_per_second(decay_per_hour)
		var current: float = float(needs.get(need_id, 1.0))
		needs[need_id] = clampf(current - decay_per_sec * delta, 0.0, 1.0)


## Returns the deficit (0.0 = satisfied, 1.0 = completely depleted)
func get_deficit(need_id: StringName) -> float:
	var current: float = get_need(need_id)
	return clampf(1.0 - current, 0.0, 1.0)


func get_need(need_id: StringName) -> float:
	if need_id == &"hunger":
		# 1. Component Resolution: Query live hunger ratio if HungerComponent is attached.
		var hunger_comp := _resolve_hunger_component()
		if hunger_comp != null:
			return hunger_comp.get_hunger_ratio()
	return float(needs.get(need_id, 1.0))


func set_need(need_id: StringName, value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	needs[need_id] = clamped
	if need_id == &"hunger":
		# 1. Component Assignment: Propagate value change directly into HungerComponent.
		var hunger_comp := _resolve_hunger_component()
		if hunger_comp != null:
			hunger_comp.current_hunger = clamped


# --- SaveSystem contract -----------------------------------------------------

func serialize() -> Dictionary:
	var out: Dictionary = {}
	for k in needs.keys():
		out[String(k)] = get_need(k)
	return out


func deserialize(data: Dictionary) -> void:
	for k in data.keys():
		var need_key := StringName(k)
		var val := float(data[k])
		set_need(need_key, val)


# ===================
# Auxiliary Functions
# ===================

func _resolve_hunger_component() -> HungerComponent:
	## Auxiliary: Resolves cached HungerComponent from parent node if valid.
	if _hunger_comp != null and is_instance_valid(_hunger_comp):
		return _hunger_comp
	var parent_node := get_parent()
	if parent_node != null:
		_hunger_comp = parent_node.get_node_or_null("HungerComponent") as HungerComponent
	return _hunger_comp
