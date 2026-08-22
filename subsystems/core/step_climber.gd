class_name StepClimber
extends Node

## Stair-step / hop locomotion assist shared by Player and Colonist (ARCH
## "Subsystem: Player" / "Subsystem: Colonists").
##
## Ticks in _physics_process after the parent CharacterBody3D's move_and_slide().
## Children process after parents, so this node sees the post-move collision
## state (is_on_wall, wall normal) and requires zero movement hooks in the
## parent body. When the body presses against an obstacle, probes forward and
## up: if the obstacle top is walkable, climbs it.
##
## Two climb modes:
##   - STEP (<= step_height): instant teleport onto the lip + floor snap, so
##     is_on_floor() never drops false for a frame. Designed for low lips /
##     stairs (e.g. 0.35-0.5 m). Used by Player and Colonist alike.
##   - HOP (<= hop_height): vertical takeoff impulse solved so the body's arc
##     reaches lip + clearance at apex. Used by Colonist (hop_height = 1.05) to
##     negotiate full 1 m voxel blocks without a manual Space-jump action;
##     remains 0 on Player (the human jump stays manual).
##
## Both modes sweep the parent body's own CollisionShape3D (via direct space
## state queries) so obstacle validation matches the body's real physics shape.
## The pathfinder knows nothing of this component — walkability stays a pure
## graph question, and this component makes the physical hops succeed.

@export var step_height := 0.5
@export var hop_height := 0.0
@export var hop_gravity := 9.8
@export var hop_cooldown := 0.25

# Probe heights exceed the accept threshold so the forward sweep clears the
# obstacle's lip with margin for query precision; hop gets more because the
# impulse must visibly clear the block mid-flight, not just touch it.
const _STEP_PROBE_CLEARANCE := 0.1
const _HOP_PROBE_CLEARANCE := 0.25
const _HOP_APEX_CLEARANCE := 0.25
const _DROP_SLACK := 0.1
const _MIN_ACCEPTED_RISE := 0.05
const _FORWARD_MARGIN := 0.05
const _DEFAULT_FORWARD := 0.35
const _DEFAULT_PROBE_LENGTH := 0.95

var _body: CharacterBody3D
var _shape: Shape3D
var _shape_offset := Vector3.ZERO
var _hop_ready_at := 0.0

# Telemetry / Diagnostics
var last_probe_status: String = "IDLE"
var last_probe_time: float = 0.0
var last_probe_dir: Vector3 = Vector3.ZERO
var last_probe_height: float = 0.0
var last_probe_rise: float = 0.0
var last_raised_origin: Vector3 = Vector3.ZERO
var last_landing_origin: Vector3 = Vector3.ZERO
var last_over_origin: Vector3 = Vector3.ZERO
var last_shape_radius: float = 0.3
var last_shape_height: float = 1.6


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		push_warning("StepClimber: parent is not a CharacterBody3D — disabled")
		set_physics_process(false)
		return
	_cache_shape()


## Read the body's first shape (and its local offset) from the shape owners so
## both scenes work despite differently-named CollisionShape3D nodes. Sibling
## CollisionShape3D nodes register before this node's _ready runs (children
## are ready left-to-right, parents last), so the owner exists by now.
func _cache_shape() -> void:
	for owner_id: int in _body.get_shape_owners():
		if _body.shape_owner_get_shape_count(owner_id) > 0:
			_shape = _body.shape_owner_get_shape(owner_id, 0)
			_shape_offset = _body.shape_owner_get_transform(owner_id).origin
			if _shape is CapsuleShape3D:
				var cap := _shape as CapsuleShape3D
				last_shape_radius = cap.radius
				last_shape_height = cap.height
			return
	if _shape == null:
		push_warning("StepClimber: body has no collision shape — disabled")
		set_physics_process(false)


func _physics_process(_delta: float) -> void:
	if _body == null or not _body.is_on_floor() or not _body.is_on_wall():
		return
	# Direction comes from the wall normal, not velocity: move_and_slide has
	# already zeroed the horizontal velocity against the wall face by now, and
	# is_on_wall() itself only turns true when the body moved INTO the wall
	# this frame (idle bodies don't generate wall contacts, so no explicit
	# push-speed gate is needed).
	var dir := -_body.get_wall_normal()
	dir.y = 0.0
	if dir.length() < 0.5:
		return # normal is near-vertical — a floor contact, not a steppable face
	dir = dir.normalized()
	if _try_step(dir):
		return
	_try_hop(dir)


## Teleport the body onto the obstacle's top and snap so is_on_floor() stays
## coherent for the body's next tick — a single spurious airborne frame would
## trip the Player's frozen-momentum air logic and the colonist gravity branch
## alike. Returns false when the obstacle isn't steppable.
func _try_step(dir: Vector3) -> bool:
	var landing := _probe_landing(dir, step_height + _STEP_PROBE_CLEARANCE, step_height)
	if landing.is_empty():
		return false
	var origin: Vector3 = landing["origin"]
	_body.global_position = origin - _body.global_transform.basis * _shape_offset
	_body.velocity.y = 0.0
	_body.apply_floor_snap()
	last_probe_status = "STEP_OK (rise: %.2fm)" % float(landing["rise"])
	return true


## Give the body a takeoff impulse instead of teleporting: solve the speed
## that arcs it rise + clearance high so the capsule clears the lip mid-flight.
## Horizontal steering (Player wish / Colonist._follow_path) is already
## pressing toward the obstacle and carries the body over. The cooldown stops
## pogo-style repeated impulses against obstacles that didn't clear.
func _try_hop(dir: Vector3) -> void:
	if hop_height <= 0.0:
		return
	var now := float(Time.get_ticks_msec()) * 0.001
	if now < _hop_ready_at:
		return
	var landing := _probe_landing(dir, hop_height + _HOP_PROBE_CLEARANCE, hop_height)
	if landing.is_empty():
		return
	var rise: float = landing["rise"]
	_body.velocity.y = sqrt(2.0 * hop_gravity * (rise + _HOP_APEX_CLEARANCE))
	_hop_ready_at = now + hop_cooldown
	last_probe_status = "HOP_OK (rise: %.2fm, vel_y: %.2fm/s)" % [rise, _body.velocity.y]


## Lift the body's capsule to probe height, sweep forward past the obstacle's
## lip, then sweep down to a standing spot. `probe_height` must exceed
## `climb_max` by enough clearance for the forward sweep to pass the lip; the
## landing is accepted only when its rise lands in (0, climb_max] and is a
## floor by the body's own floor_max_angle. Returns {"origin": world shape
## origin, "rise": float} or {} when the obstacle isn't climbable at this
## height. The lift is an endpoint overlap probe rather than a sweep: a sweep
## from the resting position counts the floor the body stands on as an initial
## collision and always reports blocked.
func _probe_landing(dir: Vector3, probe_height: float, climb_max: float) -> Dictionary:
	var space := _body.get_world_3d().direct_space_state
	var query := _make_query()
	var base := _shape_transform()
	var raised := Transform3D(base.basis, base.origin + Vector3.UP * probe_height)
	query.transform = raised

	last_probe_time = float(Time.get_ticks_msec()) * 0.001
	last_probe_dir = dir
	last_probe_height = probe_height
	last_raised_origin = raised.origin
	last_landing_origin = Vector3.ZERO

	if not space.intersect_shape(query).is_empty():
		last_probe_status = "FAIL_OVERHANG (ceiling collision at Y+%.2f)" % probe_height
		return {} # overhang above — no room to lift the capsule

	query.transform = raised
	if _sweep_fraction(space, query, dir * _forward_distance()) < 0.999:
		last_probe_status = "FAIL_OBSTACLE_TOO_HIGH (wall > %.2fm)" % climb_max
		return {} # obstacle reaches up to (or past) the probe height

	var over := Transform3D(raised.basis, raised.origin + dir * _forward_distance())
	last_over_origin = over.origin
	query.transform = over
	var drop := Vector3.DOWN * (probe_height + _DROP_SLACK)
	var fraction := _sweep_fraction(space, query, drop)
	if fraction >= 0.999:
		last_probe_status = "FAIL_OUT_OF_CLIMB_RANGE (no floor within reach)"
		return {} # surface deeper than the probe — out of climb range

	var landing := Transform3D(over.basis, over.origin + drop * fraction)
	last_landing_origin = landing.origin
	var rise := landing.origin.y - base.origin.y
	last_probe_rise = rise

	if rise < _MIN_ACCEPTED_RISE or rise > climb_max:
		last_probe_status = "FAIL_RISE_BOUNDS (rise %.2fm outside [%.2f, %.2f])" % [rise, _MIN_ACCEPTED_RISE, climb_max]
		return {}

	if not _landing_is_floor(landing.origin):
		last_probe_status = "FAIL_NOT_FLOOR (slope exceeds floor_max_angle)"
		return {}

	last_probe_status = "PROBE_OK (rise: %.2fm)" % rise
	return {"origin": landing.origin, "rise": rise}


## Fraction of `motion` travelled before the swept shape touches anything
## (1.0 = fully clear). cast_motion returns [safe, unsafe]; the unsafe value
## is where contact begins — the resting point. This Godot build takes the
## motion on the query object (cast_motion(query)), and some builds return an
## empty array on a clean sweep, so default to clear.
func _sweep_fraction(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D, motion: Vector3) -> float:
	query.motion = motion
	var fractions := space.cast_motion(query)
	if fractions.is_empty():
		return 1.0
	return float(fractions[1])


## The landing spot must be a standable slope by the body's own floor setting
## — a near-vertical remnant face would just re-trigger the wall next tick.
func _landing_is_floor(origin: Vector3) -> bool:
	var space := _body.get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * _probe_length())
	params.collision_mask = _body.collision_mask
	params.exclude = [_body.get_rid()]
	var hit := space.intersect_ray(params)
	if hit.is_empty():
		return false
	var normal: Vector3 = hit["normal"]
	return normal.angle_to(Vector3.UP) <= _body.floor_max_angle + 0.01


func _make_query() -> PhysicsShapeQueryParameters3D:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _shape
	query.collision_mask = _body.collision_mask
	query.exclude = [_body.get_rid()]
	# Margin 0 on purpose: an inflated shape counts the floor the body is
	# resting on as an initial overlap and zeroes every up-sweep.
	query.margin = 0.0
	return query


## World transform of the cached collision shape (body transform plus the
## shape's local offset). Neither body rotates (capsules; only the mesh node
## faces movement direction), so the offset stays axis-aligned.
func _shape_transform() -> Transform3D:
	var t := _body.global_transform
	t.origin += t.basis * _shape_offset
	return t


## Horizontal sweep distance: just far enough past the obstacle's lip that
## the down-sweep finds its top surface under the capsule's lowest point.
func _forward_distance() -> float:
	if _shape is CapsuleShape3D:
		return (_shape as CapsuleShape3D).radius + _FORWARD_MARGIN
	return _DEFAULT_FORWARD


## Length of the floor-validation ray: capsule centre down to its tip.
func _probe_length() -> float:
	if _shape is CapsuleShape3D:
		return (_shape as CapsuleShape3D).height * 0.5 + _DROP_SLACK
	return _DEFAULT_PROBE_LENGTH
