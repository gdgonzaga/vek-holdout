class_name GroundSafetyGuard
extends Node

## Search length down from actor. Must be long enough to reach terrain from spawn height.
@export var ray_length: float = 25.0
## Collision mask for ground (1 = statics, 2 = blocky terrain, 4 = smooth terrain)
@export_flags_3d_physics var terrain_mask: int = 7

var _body: CharacterBody3D
var _ground_confirmed: bool = false
var _lock_y: float = -99999.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_warning("GroundSafetyGuard: Parent is not a CharacterBody3D")
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if _body == null:
		return

	# If the body has landed naturally on the floor, we are safe
	if _body.is_on_floor():
		_ground_confirmed = true
		_lock_y = -99999.0
		return

	if not _ground_confirmed:
		if _try_snap_to_ground():
			# Ground was found and player snapped onto it
			_ground_confirmed = true
			_lock_y = -99999.0
		else:
			# No ground collision active yet: freeze Y position in place
			if _lock_y == -99999.0:
				_lock_y = _body.global_position.y
			else:
				_body.global_position.y = _lock_y

			# Zero out downward velocity so momentum doesn't build up
			if _body.velocity.y < 0.0:
				_body.velocity.y = 0.0


func _try_snap_to_ground() -> bool:
	var space := _body.get_world_3d().direct_space_state
	if space == null:
		return false

	# Start ray 0.5m above the actor's origin (around knee/hip height)
	var origin := _body.global_position + Vector3(0.0, 0.5, 0.0)
	var target := origin + Vector3.DOWN * ray_length

	var query := PhysicsRayQueryParameters3D.create(origin, target, terrain_mask)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = [_body.get_rid()]

	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return false

	# Snap body directly to ground surface
	_body.global_position.y = hit.position.y + 0.05
	_body.velocity = Vector3.ZERO
	return true


func rearm() -> void:
	_ground_confirmed = false
	_lock_y = -99999.0
