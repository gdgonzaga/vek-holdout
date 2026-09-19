## Subsystem: AI / Needs
## Manages entity need levels (hunger, rest, recreation) and calculates deficits for Utility AI (ARCH §6).
class_name ColonistNeeds
extends Node

signal need_changed(need_id: StringName, current: float, max_value: float)
signal need_depleted(need_id: StringName)
signal need_replenished(need_id: StringName)
signal depletion_tick_damage(need_id: StringName, amount: int)

static var _cached_need_defs: Dictionary = {}
static var _defs_loaded: bool = false

## Default base need levels (1.0 = satisfied, 0.0 = fully depleted)
var needs: Dictionary = {
	&"hunger": 1.0,
	&"rest": 1.0,
	&"recreation": 1.0
}

## Elapsed timers for periodic depletion damage keyed by need_id.
var _depletion_timers: Dictionary = {}

## Depleted tracking states keyed by need_id.
var _depleted_states: Dictionary = {}

## Toggles need processing (used for testing or pauses).
var _enabled: bool = true


# =================
# Static Cache
# =================

static func _ensure_need_defs_loaded() -> void:
	if _defs_loaded:
		return
	_defs_loaded = true
	var loaded := ContentDirLoader.load_by_id("res://data/needs/", func(res: Variant) -> bool: return res is NeedDef)
	_cached_need_defs.merge(loaded, true)


static func get_need_defs() -> Dictionary:
	_ensure_need_defs_loaded()
	return _cached_need_defs


static func reload() -> void:
	_cached_need_defs.clear()
	_defs_loaded = false
	_ensure_need_defs_loaded()


# =================
# Primary Functions
# =================

func _ready() -> void:
	var defs := get_need_defs()
	for need_id: StringName in defs:
		if not needs.has(need_id):
			needs[need_id] = 1.0
		need_changed.emit(need_id, float(needs[need_id]), 1.0)


func _process(delta: float) -> void:
	if not _enabled:
		return

	var defs := get_need_defs()
	for need_id: StringName in defs:
		var def: NeedDef = defs[need_id] as NeedDef
		if def == null:
			continue

		# 1. Need Decay: Reduces the need value across delta using game-hour rate.
		_decay_need(need_id, def, delta)

		# 2. Depletion Processing: Evaluates depletion state transitions and damage ticks.
		_process_need_depletion(need_id, def, delta)


## Returns current need level between 0.0 (depleted) and 1.0 (satisfied).
func get_need(need_id: StringName) -> float:
	return float(needs.get(need_id, 1.0))


## Sets need level clamped to [0.0, 1.0], emitting need_changed if altered.
func set_need(need_id: StringName, value: float) -> void:
	var clamped := clampf(value, 0.0, 1.0)
	var prev := float(needs.get(need_id, 1.0))
	if not is_equal_approx(prev, clamped):
		needs[need_id] = clamped
		need_changed.emit(need_id, clamped, 1.0)

		# 1. Depletion State Evaluation: Verify state transitions on manual set.
		_sync_depletion_state_on_set(need_id, clamped)


## Restores a need by amount clamped to 1.0.
func restore_need(need_id: StringName, amount: float) -> void:
	if amount <= 0.0:
		return
	var current := get_need(need_id)
	set_need(need_id, current + amount)


## Returns the deficit (0.0 = satisfied, 1.0 = completely depleted)
func get_deficit(need_id: StringName) -> float:
	return clampf(1.0 - get_need(need_id), 0.0, 1.0)


## Returns true if the need is fully depleted (<= 0.0).
func is_depleted(need_id: StringName) -> bool:
	return get_need(need_id) <= 0.0


## Locomotion speed multiplier based on active depleted needs.
func get_speed_multiplier() -> float:
	var mult: float = 1.0
	var defs := get_need_defs()
	for need_id: StringName in needs:
		if is_depleted(need_id) and defs.has(need_id):
			var def: NeedDef = defs[need_id] as NeedDef
			if def != null:
				mult *= def.depletion_speed_mult
	return mult


## Stamina recovery multiplier based on active depleted needs.
func get_stamina_recovery_multiplier() -> float:
	var mult: float = 1.0
	var defs := get_need_defs()
	for need_id: StringName in needs:
		if is_depleted(need_id) and defs.has(need_id):
			var def: NeedDef = defs[need_id] as NeedDef
			if def != null:
				mult *= def.depletion_stamina_mult
	return mult


# --- SaveSystem contract -----------------------------------------------------

func serialize() -> Dictionary:
	var out_needs: Dictionary = {}
	for k in needs.keys():
		out_needs[String(k)] = float(needs[k])

	var out_timers: Dictionary = {}
	for k in _depletion_timers.keys():
		out_timers[String(k)] = float(_depletion_timers[k])

	var out_depleted: Dictionary = {}
	for k in _depleted_states.keys():
		out_depleted[String(k)] = bool(_depleted_states[k])

	return {
		"needs": out_needs,
		"depletion_timers": out_timers,
		"depleted_states": out_depleted
	}


func deserialize(data: Dictionary) -> void:
	# 1. Needs Deserialization: Restores need levels from dictionary format.
	_deserialize_needs_dict(data)

	# 2. Timers Deserialization: Restores timers and depleted state maps.
	_deserialize_depletion_state(data)


# ===================
# Auxiliary Functions
# ===================

func _decay_need(need_id: StringName, def: NeedDef, delta: float) -> void:
	## Auxiliary: Applies frame-scaled decay to a need.
	if def.decay_per_game_hour <= 0.0:
		return
	var decay_per_sec := TimeSystem.rate_per_game_hour_to_per_second(def.decay_per_game_hour)
	var current: float = float(needs.get(need_id, 1.0))
	var updated := clampf(current - decay_per_sec * delta, 0.0, 1.0)
	if not is_equal_approx(current, updated):
		needs[need_id] = updated
		need_changed.emit(need_id, updated, 1.0)


func _process_need_depletion(need_id: StringName, def: NeedDef, delta: float) -> void:
	## Auxiliary: Manages depletion transitions and delegates damage accumulation.
	var is_curr_depleted: bool = is_depleted(need_id)
	var was_depleted: bool = bool(_depleted_states.get(need_id, false))

	if is_curr_depleted:
		if not was_depleted:
			_depleted_states[need_id] = true
			_depletion_timers[need_id] = 0.0
			need_depleted.emit(need_id)

		# 1. Damage Tick Processing: Accumulates delta and applies periodic damage.
		_accumulate_depletion_damage(need_id, def, delta)
	else:
		if was_depleted:
			_depleted_states[need_id] = false
			_depletion_timers[need_id] = 0.0
			need_replenished.emit(need_id)


func _accumulate_depletion_damage(need_id: StringName, def: NeedDef, delta: float) -> void:
	## Auxiliary: Advances damage interval timer and dispatches damage events.
	if def.depletion_damage <= 0 or def.depletion_damage_interval <= 0.0:
		return

	var timer: float = float(_depletion_timers.get(need_id, 0.0)) + delta
	if timer >= def.depletion_damage_interval:
		timer -= def.depletion_damage_interval
		depletion_tick_damage.emit(need_id, def.depletion_damage)

		# 1. Direct Entity Damage: Apply damage to parent if it supports take_damage.
		_apply_direct_damage_to_parent(def.depletion_damage)

	_depletion_timers[need_id] = timer


func _apply_direct_damage_to_parent(amount: int) -> void:
	## Auxiliary: Dispatches direct damage to parent entity.
	var parent_node := get_parent()
	if parent_node != null and parent_node.has_method("take_damage"):
		parent_node.take_damage(amount, self)


func _sync_depletion_state_on_set(need_id: StringName, new_value: float) -> void:
	## Auxiliary: Updates depleted state flag and emits signals when set_need changes threshold.
	var was_depleted: bool = bool(_depleted_states.get(need_id, false))
	if new_value <= 0.0 and not was_depleted:
		_depleted_states[need_id] = true
		_depletion_timers[need_id] = 0.0
		need_depleted.emit(need_id)
	elif new_value > 0.0 and was_depleted:
		_depleted_states[need_id] = false
		_depletion_timers[need_id] = 0.0
		need_replenished.emit(need_id)


func _deserialize_needs_dict(data: Dictionary) -> void:
	## Auxiliary: Restores need values from either nested 'needs' key or flat dictionary.
	var source: Dictionary = data.get("needs", data) if data.has("needs") else data
	for k in source.keys():
		var key_str := String(k)
		if key_str == "needs" or key_str == "depletion_timers" or key_str == "depleted_states":
			continue
		var need_key: StringName = &"hunger" if key_str == "current_hunger" else StringName(key_str)
		var val := float(source[k])
		set_need(need_key, val)


func _deserialize_depletion_state(data: Dictionary) -> void:
	## Auxiliary: Restores depletion timers and states from serialized maps.
	if data.has("depletion_timers") and data["depletion_timers"] is Dictionary:
		var timers_dict: Dictionary = data["depletion_timers"]
		for k in timers_dict.keys():
			_depletion_timers[StringName(k)] = float(timers_dict[k])

	if data.has("depleted_states") and data["depleted_states"] is Dictionary:
		var states_dict: Dictionary = data["depleted_states"]
		for k in states_dict.keys():
			_depleted_states[StringName(k)] = bool(states_dict[k])
	elif data.has("is_starving"):
		_depleted_states[&"hunger"] = bool(data["is_starving"])
