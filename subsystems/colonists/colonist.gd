extends CharacterBody3D
class_name Colonist

@export var colonist_def: ColonistDef = preload("res://data/colonists/default_colonist.tres")
@export var gravity: float = 9.8
var colonist_id: String
var display_name: String
var labor_priorities: Dictionary
var raid_stance: int
var current_job: Job
var skill_set: SkillSet
var stamina_component: StaminaComponent
var pathfinder: VoxelPathfinder
## Carry inventory (materials hauled to blueprints, etc.). Created in _ready so
## Blueprint.deposit_from(self) works unchanged — it calls actor.remove_item,
## which the Player has via the same CharacterInventory pattern (player.gd).
var inventory: CharacterInventory

# Path-following locomotion. Waypoints are fed by VoxelPathfinder (Phase 3) /
# ColonistAI (Phase 4); until then set_path() can be driven manually to verify
# movement. Mirrors Player's gravity + move_and_slide kernel.
const _ARRIVAL_THRESHOLD: float = 0.2
const _STEP_ARRIVAL_THRESHOLD: float = 0.08
var _path: Array[Vector3] = []
var _path_index: int = 0

var _stuck_timer: float = 0.0
var _wiggle_timer: float = 0.0
var _wiggle_dir: Vector3 = Vector3.ZERO

var _current_hp: int = 100
var _is_dead: bool = false

func _ready() -> void:
	colonist_id = Tools.generate_uuid()
	display_name = colonist_def.display_name
	labor_priorities = colonist_def.default_labor_priorities
	raid_stance = colonist_def.default_raid_stance
	current_job = null
	skill_set = $SkillSet
	skill_set.seed(colonist_def.starting_skills)
	stamina_component = $StaminaComponent
	pathfinder = $VoxelPathfinder
	# Carry inventory: code-created (mirrors Player's scene-placed CharacterInventory)
	# so this stays a script-only change. CharacterInventory._ready recalc's capacity
	# on enter-tree, so add_child before any hauler reads it.
	var inv := CharacterInventory.new()
	inv.name = "Inventory"
	add_child(inv)
	inventory = inv
	_current_hp = colonist_def.max_hp
	floor_max_angle = deg_to_rad(60.0)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	_follow_path(delta)
	move_and_slide()


## Feed a world-space waypoint path (from VoxelPathfinder, Phase 3). Resets any
## in-progress path. An empty path leaves the colonist standing.
func set_path(path: Array) -> void:
	# assign() copies elements into the typed Array[Vector3] with per-element
	# checks; a bare duplicate() returns an untyped Array, which 4.7 won't assign
	# to a typed var.
	_path.assign(path)
	_path_index = 0
	_stuck_timer = 0.0
	_wiggle_timer = 0.0


## True when every waypoint has been consumed (or no path was set).
func has_arrived() -> bool:
	return _path_index >= _path.size()


func _follow_path(delta: float) -> void:
	if _path_index >= _path.size():
		velocity.x = 0.0
		velocity.z = 0.0
		_stuck_timer = 0.0
		_wiggle_timer = 0.0
		return
	var to_target: Vector3 = _path[_path_index] - global_position
	to_target.y = 0.0  # navigate on the horizontal plane

	# Enforce tight arrival threshold on vertical steps and ramp transitions
	# so the colonist capsule (radius 0.3m) reaches the cell center and fully
	# clears the opening/riser before turning toward subsequent waypoints.
	var threshold := _ARRIVAL_THRESHOLD
	var has_prev_step := _path_index > 0 and absf(_path[_path_index].y - _path[_path_index - 1].y) > 0.2
	var has_next_step := _path_index + 1 < _path.size() and absf(_path[_path_index + 1].y - _path[_path_index].y) > 0.2
	if has_prev_step or has_next_step:
		threshold = _STEP_ARRIVAL_THRESHOLD

	if to_target.length() <= threshold:
		_path_index += 1
		velocity.x = 0.0
		velocity.z = 0.0
		_stuck_timer = 0.0
		_wiggle_timer = 0.0
		return
	var dir: Vector3 = to_target.normalized()
	var speed: float = colonist_def.base_move_speed
	
	if _wiggle_timer > 0.0:
		_wiggle_timer -= delta
		dir = _wiggle_dir
	else:
		var horiz_vel := Vector2(velocity.x, velocity.z)
		if is_on_wall() and horiz_vel.length_squared() < (speed * 0.1) ** 2:
			_stuck_timer += delta
			if _stuck_timer > 0.3:
				_stuck_timer = 0.0
				_wiggle_timer = 0.4 + randf() * 0.2
				var wall_normal := get_wall_normal()
				wall_normal.y = 0.0
				if wall_normal.length_squared() > 0.01:
					wall_normal = wall_normal.normalized()
					var tangent := Vector3(wall_normal.z, 0, -wall_normal.x)
					if tangent.dot(dir) < 0:
						tangent = -tangent
					_wiggle_dir = (tangent + wall_normal * 0.5).normalized()
				else:
					var angle := randf() * TAU
					_wiggle_dir = Vector3(cos(angle), 0, sin(angle))
		else:
			_stuck_timer = maxf(0.0, _stuck_timer - delta)

	velocity.x = dir.x * speed
	velocity.z = dir.z * speed


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


func get_hp() -> int:
	return _current_hp


func get_max_hp() -> int:
	return colonist_def.max_hp if colonist_def != null else 100


func _die() -> void:
	_is_dead = true
	EventBus.colonist_died.emit(colonist_id)


func set_labor_priority(labor_id: String, priority: int) -> void:
	labor_priorities[labor_id] = clampi(priority, 0, 5)


func set_raid_stance(stance: int) -> void:
	# TODO: Add a guard vs configured min/max values
	raid_stance = stance


# --- Carry inventory wrappers ------------------------------------------------
# Mirror Player's inventory helpers so a colonist can stand in for `actor` in
# Blueprint.deposit_from (which calls actor.remove_item) and HaulingJobDef can
# move items between a crate's StorageInventory and the colonist via transfer_to.

func add_item(item_id: String, count: int) -> int:
	return inventory.add(item_id, count)


func remove_item(item_id: String, count: int) -> int:
	return inventory.remove(item_id, count)


func has_item(item_id: String, count: int) -> bool:
	return inventory.has_item(item_id, count)


func can_carry(item_id: String, count: int) -> bool:
	return inventory.can_add(item_id, count)


## Free weight left in the carry inventory (capacity − current_weight). Not
## exercised by the haul loop yet (transfer_to enforces capacity at fetch) —
## kept for future capacity-aware assignment.
func remaining_capacity() -> float:
	return inventory.capacity - inventory.current_weight()


# --- SaveSystem contract -----------------------------------------------------
# Owned scalar/dict state + world position + skill state. Component sub-state
# (StaminaComponent, VoxelPathfinder) and current_job are excluded — they are
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
		"skills": skill_set.serialize() if skill_set != null else {},
		"pos": [global_position.x, global_position.y, global_position.z],
	}


func deserialize(data: Dictionary) -> void:
	colonist_id = data.get("colonist_id", colonist_id)
	display_name = data.get("display_name", display_name)
	labor_priorities = data.get("labor_priorities", {}).duplicate(true)
	raid_stance = int(data.get("raid_stance", raid_stance))
	_current_hp = int(data.get("hp", _current_hp))
	_is_dead = bool(data.get("is_dead", false))
	if skill_set != null and data.has("skills"):
		skill_set.deserialize(data["skills"])
	var p: Array = data.get("pos", [global_position.x, global_position.y, global_position.z])
	global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
