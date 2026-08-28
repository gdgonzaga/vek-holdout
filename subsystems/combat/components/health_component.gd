class_name HealthComponent
extends Node
## Reusable component managing HP and Durability.
## Attached to Player, Colonists, and Enemies.
## Handles Durability-before-HP damage resolution per GDD §6.11 and ARCH combat.md.

signal entity_died(entity: Node)
signal health_changed(current_hp: int, max_hp: int)
signal durability_changed(current_durability: int, max_durability: int)
signal damaged(amount: int, source: Node)
signal healed(amount: int)

@export var max_hp: int = 100:
	set(value):
		max_hp = value
		if not _initialized:
			current_hp = max_hp

@export var max_durability: int = 0:
	set(value):
		max_durability = value
		if not _initialized:
			current_durability = max_durability

var current_hp: int = 100
var current_durability: int = 0
var is_dead: bool = false
var _initialized: bool = false


func _ready() -> void:
	if not _initialized:
		current_hp = max_hp
		current_durability = max_durability
		_initialized = true
	health_changed.emit(current_hp, max_hp)
	durability_changed.emit(current_durability, max_durability)


func _ensure_initialized() -> void:
	if not _initialized:
		current_hp = max_hp
		current_durability = max_durability
		_initialized = true


## Applies damage, depleting durability before HP per GDD §6.11.
## Compatible with colonist.gd and player.gd damage handling.
func take_damage(amount: int, source: Node = null) -> void:
	_ensure_initialized()
	if is_dead or amount <= 0:
		return

	var remaining_damage := amount

	if current_durability > 0:
		if current_durability >= remaining_damage:
			current_durability -= remaining_damage
			remaining_damage = 0
		else:
			remaining_damage -= current_durability
			current_durability = 0
		durability_changed.emit(current_durability, max_durability)

	if remaining_damage > 0:
		current_hp -= remaining_damage
		if current_hp <= 0:
			current_hp = 0
			health_changed.emit(current_hp, max_hp)
		damaged.emit(amount, source)
		if current_hp == 0:
			_die()
		else:
			health_changed.emit(current_hp, max_hp)
	else:
		damaged.emit(amount, source)


## Heals HP up to max_hp. Does not repair durability or revive dead entities.
func heal(amount: int) -> void:
	_ensure_initialized()
	if is_dead or amount <= 0:
		return

	var prev_hp := current_hp
	current_hp = mini(current_hp + amount, max_hp)
	if current_hp != prev_hp:
		healed.emit(amount)
		health_changed.emit(current_hp, max_hp)


## Repairs durability up to max_durability.
func repair_durability(amount: int) -> void:
	_ensure_initialized()
	if is_dead or amount <= 0:
		return

	var prev_dur := current_durability
	current_durability = mini(current_durability + amount, max_durability)
	if current_durability != prev_dur:
		durability_changed.emit(current_durability, max_durability)


## Resets or reconfigures maximum HP and durability.
func setup(new_max_hp: int, new_max_durability: int = 0) -> void:
	max_hp = new_max_hp
	max_durability = new_max_durability
	current_hp = max_hp
	current_durability = max_durability
	is_dead = false
	_initialized = true
	health_changed.emit(current_hp, max_hp)
	durability_changed.emit(current_durability, max_durability)


func _die() -> void:
	is_dead = true
	entity_died.emit(owner if owner != null else self)


## Persistence for SaveSystem (INV-1).
func serialize() -> Dictionary:
	_ensure_initialized()
	return {
		"max_hp": max_hp,
		"max_durability": max_durability,
		"current_hp": current_hp,
		"current_durability": current_durability,
		"is_dead": is_dead,
	}


func deserialize(data: Dictionary) -> void:
	max_hp = int(data.get("max_hp", 100))
	max_durability = int(data.get("max_durability", 0))
	current_hp = int(data.get("current_hp", max_hp))
	current_durability = int(data.get("current_durability", max_durability))
	is_dead = bool(data.get("is_dead", false))
	_initialized = true
	health_changed.emit(current_hp, max_hp)
	durability_changed.emit(current_durability, max_durability)
