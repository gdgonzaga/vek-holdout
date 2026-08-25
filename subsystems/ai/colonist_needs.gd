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


func _ready() -> void:
	var defs := get_need_defs()
	for need_id in defs:
		if not needs.has(need_id):
			needs[need_id] = 1.0


func _process(delta: float) -> void:
	var defs := get_need_defs()
	for need_id in defs:
		var def: Resource = defs[need_id]
		var decay: float = def.decay_per_second
		var current: float = float(needs.get(need_id, 1.0))
		needs[need_id] = clampf(current - decay * delta, 0.0, 1.0)


## Returns the deficit (0.0 = satisfied, 1.0 = completely depleted)
func get_deficit(need_id: StringName) -> float:
	var current: float = float(needs.get(need_id, 1.0))
	return clampf(1.0 - current, 0.0, 1.0)


func get_need(need_id: StringName) -> float:
	return float(needs.get(need_id, 1.0))


func set_need(need_id: StringName, value: float) -> void:
	needs[need_id] = clampf(value, 0.0, 1.0)


# --- SaveSystem contract -----------------------------------------------------

func serialize() -> Dictionary:
	var out: Dictionary = {}
	for k in needs.keys():
		out[String(k)] = needs[k]
	return out


func deserialize(data: Dictionary) -> void:
	for k in data.keys():
		needs[StringName(k)] = float(data[k])
