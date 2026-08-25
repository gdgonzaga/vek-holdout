## Subsystem: AI / Needs
## Manages colonist need levels (hunger, rest, recreation) and calculates deficits for Utility AI.
class_name ColonistNeeds
extends Node

## Default base need levels (1.0 = satisfied, 0.0 = fully depleted)
var needs: Dictionary = {
	&"hunger": 1.0,
	&"rest": 1.0,
	&"recreation": 1.0
}


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
