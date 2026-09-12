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

@export var show_damage_particles: bool = true

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

	# 1. Damage Visuals: Spawning big red particle burst on damage impact.
	_spawn_big_red_hit_effect(false)

	# 1. Durability Resolution: Deplete durability before HP per GDD §6.11.
	var remaining_damage := DamageResolver.resolve_overflow(amount, current_durability)

	if current_durability > 0:
		current_durability = DamageResolver.resolve_durability(amount, current_durability)
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

	# 1. Death Visuals: Spawning big red particle explosion on entity death.
	_spawn_big_red_hit_effect(true)

	entity_died.emit(owner if owner != null else self)


## Auxiliary: Spawns big red particle visual effect at entity location on taking damage or dying
func _spawn_big_red_hit_effect(is_death: bool = false) -> void:
	if not show_damage_particles or get_tree() == null:
		return

	var parent_node3d: Node3D = get_parent() as Node3D
	if parent_node3d == null or not parent_node3d.is_inside_tree():
		return

	var tree := get_tree()
	var scene_root: Node = tree.current_scene if tree.current_scene != null else parent_node3d.get_parent()
	if scene_root == null:
		return

	var particles := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 180.0 if is_death else 60.0
	mat.initial_velocity_min = 4.0 if is_death else 2.5
	mat.initial_velocity_max = 8.0 if is_death else 5.5
	mat.gravity = Vector3(0, -9.8, 0)
	mat.scale_min = 0.15 if is_death else 0.12
	mat.scale_max = 0.35 if is_death else 0.25
	mat.color = Color(0.95, 0.05, 0.05)

	var draw_mesh := BoxMesh.new()
	var mesh_size: float = 0.18 if is_death else 0.12
	draw_mesh.size = Vector3(mesh_size, mesh_size, mesh_size)

	var draw_mat := StandardMaterial3D.new()
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.albedo_color = Color(0.95, 0.05, 0.05)
	draw_mesh.material = draw_mat

	particles.process_material = mat
	particles.draw_pass_1 = draw_mesh
	particles.amount = 24 if is_death else 14
	particles.lifetime = 0.35
	particles.one_shot = true
	particles.explosiveness = 1.0

	scene_root.add_child(particles)
	var spawn_pos := parent_node3d.global_position + Vector3(0, 1.0, 0)
	particles.global_position = spawn_pos
	particles.emitting = true

	var timer := tree.create_timer(0.4)
	timer.timeout.connect(particles.queue_free)



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
