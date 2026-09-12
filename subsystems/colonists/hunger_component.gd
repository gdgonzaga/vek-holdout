class_name HungerComponent
extends Node
## Component managing hunger, satiety decay, and starvation mechanics (ARCH colonists.md, GDD §7).
## Attached to Colonists and Player. Decouples physiological starvation debuffs,
## damage tick timers, and speed/stamina multipliers from core entity locomotion.

signal hunger_changed(current: float, max_value: float)
signal starvation_started
signal starvation_ended
signal starvation_tick_damage(amount: int)

@export var max_hunger: float = 1.0
@export var current_hunger: float = 1.0:
	set(value):
		var clamped_val := clampf(value, 0.0, max_hunger)
		if not is_equal_approx(current_hunger, clamped_val):
			current_hunger = clamped_val
			hunger_changed.emit(current_hunger, max_hunger)

## Satiety drained per in-game hour during simulation.
@export var decay_per_game_hour: float = 3.75

## Seconds between periodic starvation damage ticks when current_hunger is 0.0.
@export var starvation_damage_interval: float = 5.0

## Amount of direct HP damage dealt on each starvation damage tick.
@export var starvation_damage: int = 2

## Movement speed multiplier applied while starving (0.0 hunger).
@export var starvation_speed_mult: float = 0.80

## Stamina recovery multiplier applied while starving (0.0 hunger).
@export var starvation_stamina_mult: float = 0.50

var _starvation_timer: float = 0.0
var _is_starving: bool = false
var _enabled: bool = true


# =================
# Primary Functions
# =================

func _ready() -> void:
	hunger_changed.emit(current_hunger, max_hunger)


func _process(delta: float) -> void:
	if not _enabled:
		return

	# 1. Decay Step: Reduce hunger value over time.
	_advance_hunger_decay(delta)

	# 2. Starvation Evaluation: Monitor threshold transitions and process damage ticks.
	_process_starvation_state(delta)


## Restores hunger by a given amount, clamped to max_hunger.
func restore_hunger(amount: float) -> void:
	if amount <= 0.0:
		return
	current_hunger += amount


## Returns current hunger ratio normalized between 0.0 (starving) and 1.0 (satisfied).
func get_hunger_ratio() -> float:
	if max_hunger <= 0.0:
		return 0.0
	return current_hunger / max_hunger


## True when hunger has completely depleted.
func is_starving() -> bool:
	return current_hunger <= 0.0


## Movement speed multiplier based on starvation state.
func get_speed_multiplier() -> float:
	if is_starving():
		return starvation_speed_mult
	return 1.0


## Stamina recovery multiplier based on starvation state.
func get_stamina_recovery_multiplier() -> float:
	if is_starving():
		return starvation_stamina_mult
	return 1.0


## Returns actor's existing HungerComponent child, or creates and adds one.
## Shared by Player and Colonist _ready.
static func ensure_on(actor: Node) -> HungerComponent:
	var existing := actor.get_node_or_null("HungerComponent") as HungerComponent
	if existing != null:
		return existing
	var created := HungerComponent.new()
	created.name = "HungerComponent"
	actor.add_child(created)
	return created


# --- SaveSystem contract -----------------------------------------------------

func serialize() -> Dictionary:
	return {
		"current_hunger": current_hunger,
		"max_hunger": max_hunger,
		"starvation_timer": _starvation_timer,
		"is_starving": _is_starving,
		"decay_per_game_hour": decay_per_game_hour
	}


func deserialize(data: Dictionary) -> void:
	max_hunger = float(data.get("max_hunger", 1.0))
	current_hunger = float(data.get("current_hunger", max_hunger))
	_starvation_timer = float(data.get("starvation_timer", 0.0))
	_is_starving = bool(data.get("is_starving", false))
	decay_per_game_hour = float(data.get("decay_per_game_hour", decay_per_game_hour))
	hunger_changed.emit(current_hunger, max_hunger)


# ===================
# Auxiliary Functions
# ===================

func _advance_hunger_decay(delta: float) -> void:
	## Auxiliary: Applies frame-scaled decay to current hunger level.
	if decay_per_game_hour <= 0.0:
		return
	var decay_per_sec = TimeSystem.rate_per_game_hour_to_per_second(decay_per_game_hour)
	current_hunger -= decay_per_sec * delta


func _process_starvation_state(delta: float) -> void:
	## Auxiliary: Evaluates starvation transitions and damage intervals.
	if is_starving():
		if not _is_starving:
			_is_starving = true
			_starvation_timer = 0.0
			starvation_started.emit()

		# 1. Damage Tick Processing: Accumulates delta and fires damage when interval is reached.
		_accumulate_starvation_damage(delta)
	else:
		if _is_starving:
			_is_starving = false
			_starvation_timer = 0.0
			starvation_ended.emit()


func _accumulate_starvation_damage(delta: float) -> void:
	## Auxiliary: Advances damage interval timer and dispatches damage events.
	_starvation_timer += delta
	if _starvation_timer >= starvation_damage_interval:
		_starvation_timer -= starvation_damage_interval
		starvation_tick_damage.emit(starvation_damage)

		# 1. Direct Entity Damage: Apply damage to parent if it supports take_damage.
		_apply_direct_damage_to_parent(starvation_damage)


func _apply_direct_damage_to_parent(amount: int) -> void:
	## Auxiliary: Dispatches direct damage to parent entity.
	var parent_node := get_parent()
	if parent_node == null:
		return

	if parent_node.has_method("take_damage"):
		parent_node.take_damage(amount, self)
