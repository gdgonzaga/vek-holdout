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
var _path: Array[Vector3] = []
var _path_index: int = 0

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
	# Carry inventory: code-created (mirrors Player's scene-placed CharacterInventory)
	# so this stays a script-only change. CharacterInventory._ready recalc's capacity
	# on enter-tree, so add_child before any hauler reads it.
	var inv := CharacterInventory.new()
	inv.name = "Inventory"
	add_child(inv)
	inventory = inv
	_current_hp = colonist_def.max_hp


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	_follow_path()
	move_and_slide()


## Feed a world-space waypoint path (from VoxelPathfinder, Phase 3). Resets any
## in-progress path. An empty path leaves the colonist standing.
func set_path(path: Array) -> void:
	# assign() copies elements into the typed Array[Vector3] with per-element
	# checks; a bare duplicate() returns an untyped Array, which 4.7 won't assign
	# to a typed var.
	_path.assign(path)
	_path_index = 0


## True when every waypoint has been consumed (or no path was set).
func has_arrived() -> bool:
	return _path_index >= _path.size()


func _follow_path() -> void:
	if _path_index >= _path.size():
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var to_target: Vector3 = _path[_path_index] - global_position
	to_target.y = 0.0  # navigate on the horizontal plane
	if to_target.length() <= _ARRIVAL_THRESHOLD:
		_path_index += 1
		velocity.x = 0.0
		velocity.z = 0.0
		return
	var dir: Vector3 = to_target.normalized()
	var speed: float = colonist_def.base_move_speed
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


func _die() -> void:
	_is_dead = true
	EventBus.colonist_died.emit(colonist_id)


func set_labor_priority(labord_id: String, priority: int) -> void:
	# TODO: Add a guard vs configured min/max values
	labor_priorities[labord_id] = priority


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
