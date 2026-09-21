class_name PlayerMotor
extends Node
## Player locomotion: gravity, walk/sprint, jump, and the frozen air momentum
## (ARCH "Subsystem: Player"). A child of the Player CharacterBody3D that the Player
## ticks explicitly from its own _physics_process, so the order against the body's other
## children (StepClimber ticks after move_and_slide) stays exactly as it was when this
## logic lived in player.gd. It has no _physics_process of its own for the same reason.
##
## What it does NOT know: needs, water, death, busy. The Player folds those into the two
## values it hands to tick() (a lock flag and one speed multiplier), which keeps this
## component free of stat and combat coupling. It also does not own the movement state
## (IDLE/WALK/...): tick() returns the horizontal wish so the Player can derive it.
##
## Air momentum (the design this component protects): at takeoff (jump or ledge exit) the
## horizontal direction and speed are frozen. Mid-air keys only BRAKE or NUDGE that momentum
## per axis (see resolve_air_axis); they never re-project it, so rotating the camera in the
## air cannot curve the trajectory.
##
## TODO when CharacterDef lands: source the speeds and gravity from
## data/characters/player.tres instead of these exports (ARCH: no hardcoded content values).
## Exported for now so they're editor-tunable.

@export var walk_speed := 3.5
@export var sprint_speed := 7.0
@export var gravity := 9.8
@export var jump_force := 5.0
## Mid-air nudge speed when a key is held against (or without) the frozen momentum.
@export var jump_move_speed := 0.5

var _body: CharacterBody3D
var _input: InputComponent
var _rig: CameraRig

## Horizontal world-velocity direction frozen at takeoff (y=0).
var _velocity_on_jump := Vector3.ZERO

## Ground speed (walk or sprint, with the owner's penalties) frozen at takeoff.
var _speed_on_jump := 0.0

## Last tick's floor contact, to detect stepping off a ledge without jumping.
var _was_on_floor := true


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	set_physics_process(false)


## Wires the collaborators the Player owns. Called by Player._ready.
func setup(input: InputComponent, rig: CameraRig) -> void:
	_input = input
	_rig = rig


# =================
# Primary Functions
# =================

## Advances one physics tick: gravity and ledge capture, the jump check, horizontal velocity
## from the keys, then move_and_slide. Returns this tick's horizontal wish vector (world
## space, zero while locked) so the owner can derive its movement state.
##
## `locked`: the owner can't act (busy or dead) — no wish, no jump, gravity still applies.
## `speed_multiplier`: the owner's penalties (needs, wading) applied to ground speed and
## frozen into takeoff speed, so momentum in the air can't shed a slowdown walking keeps.
func tick(delta: float, locked: bool, speed_multiplier: float) -> Vector3:
	var grounded := _body.is_on_floor()

	# 1. Gravity And Ledge Capture: Applies gravity while airborne and freezes momentum if the player just stepped off an edge.
	_apply_gravity_and_ledge_capture(delta, grounded, speed_multiplier)

	# 2. Jump: Takes off from the floor state seen at the start of the tick, so the impulse is applied by this tick's move_and_slide instead of sitting unused for a frame.
	_try_jump(locked, grounded, speed_multiplier)

	# 3. Wish Resolution: Horizontal world-space direction for this tick (zero while locked).
	var wish := _resolve_wish(locked, grounded)

	# 4. Speed Selection: Live ground speed on the floor, the speed frozen at takeoff in the air.
	var speed := _ground_speed(speed_multiplier) if grounded else _speed_on_jump
	_body.velocity.x = wish.x * speed
	_body.velocity.z = wish.z * speed

	_body.move_and_slide()
	return wish


## Clears velocity and frozen momentum. Called on load so a restored player doesn't
## inherit the previous run's motion.
func reset() -> void:
	_body.velocity = Vector3.ZERO
	_velocity_on_jump = Vector3.ZERO
	_speed_on_jump = 0.0
	_was_on_floor = true


## Resolve ONE mid-air cardinal axis to a signed scalar (pure; static so it is testable alone).
## - `neg_held`: is the key driving this axis negative held? (backward / left)
## - `pos_held`: is the key driving this axis positive held? (forward / right)
## - `momentum`: this axis's captured world-momentum component (sign = direction)
## - `nudge_speed`: the brake/nudge magnitude when a key opposes or lacks momentum
## Returns a positive value toward the positive key, negative toward the negative.
##
## Per-axis rule (axes are independent):
##   both keys held            -> 0      (cancel)
##   pos held, momentum > 0    -> momentum (preserve — you jumped that way)
##   pos held, momentum <= 0   -> +nudge_speed (nudge / brake toward pos)
##   neg held, momentum < 0    -> momentum (preserve)
##   neg held, momentum >= 0   -> -nudge_speed (nudge / brake toward neg)
##   neither held              -> 0      (snap stop on this axis, no coasting)
static func resolve_air_axis(neg_held: bool, pos_held: bool, momentum: float, nudge_speed: float) -> float:
	if neg_held and pos_held:
		return 0.0 # conflicting input cancels the axis
	if pos_held:
		return momentum if momentum > 0.0 else nudge_speed
	if neg_held:
		return momentum if momentum < 0.0 else -nudge_speed
	return 0.0 # released -> axis stops dead


# ===================
# Auxiliary Functions
# ===================

func _apply_gravity_and_ledge_capture(delta: float, grounded: bool, speed_multiplier: float) -> void:
	## Auxiliary: Gravity while airborne. On the first airborne tick without a jump (walking down
	## stairs / stepping off a ledge) it also freezes the ground momentum, so walking off an edge
	## preserves walking speed instead of stopping dead.
	if not grounded:
		_body.velocity.y -= gravity * delta
		if _was_on_floor and not _input.wants_jump():
			# 1. Camera-Relative Direction: The held keys as a world-space direction at the ledge.
			_velocity_on_jump = _camera_relative_wish(_input.get_movement_input())
			# 2. Ledge Speed Capture: Freezes the current ground speed, penalties included.
			_speed_on_jump = _ground_speed(speed_multiplier)
	_was_on_floor = grounded


func _resolve_wish(locked: bool, grounded: bool) -> Vector3:
	## Auxiliary: Horizontal wish in WORLD space. A locked player can't drive movement, so the wish
	## stays zero and velocity is wiped (gravity still applies so they stay planted).
	## Ground: fresh each frame from camera-relative WASD. Mid-air: the frozen momentum, braked
	## per axis by the held keys.
	if locked:
		return Vector3.ZERO
	var move_input := _input.get_movement_input()
	if grounded:
		# 1. Ground Wish: Camera-relative WASD, normalized, projected to world.
		return _camera_relative_wish(move_input)
	# 2. Air Wish: Frozen momentum resolved per axis against the live camera directions.
	return _resolve_air_wish(move_input)


func _resolve_air_wish(air_input: Vector2) -> Vector3:
	## Auxiliary: The two cardinal axes (forward/back, strafe) are resolved INDEPENDENTLY, each against
	## the captured world-momentum projected onto the live camera directions. Keys are read relative
	## to the live camera (W = away from where you look now); momentum stays world-locked, so rotating
	## the camera mid-air can't curve movement. Each axis is a signed scalar (positive = forward / right).
	var cam_forward := _rig.get_forward_horizontal()
	var cam_right := _rig.get_right_horizontal()
	var forward_scalar := resolve_air_axis(
		air_input.y > 0.0, # backward component
		air_input.y < 0.0, # forward component
		_velocity_on_jump.dot(cam_forward),
		jump_move_speed
	)
	var strafe_scalar := resolve_air_axis(
		air_input.x < 0.0, # left component
		air_input.x > 0.0, # right component
		_velocity_on_jump.dot(cam_right),
		jump_move_speed
	)
	return cam_forward * forward_scalar + cam_right * strafe_scalar


func _try_jump(locked: bool, grounded: bool, speed_multiplier: float) -> void:
	## Auxiliary: Takes off when unlocked, on the floor and the jump key is held. The horizontal
	## direction is frozen in WORLD space at this instant for the whole jump: mid-air keys only brake
	## it, never re-project it. The takeoff speed is frozen too, so a sprint-jump carries sprint-scale
	## momentum (mid-air Shift can't change it) and a jump can't shed a slowdown walking would keep.
	if locked or not grounded:
		return
	if not _input.wants_jump():
		return
	_body.velocity.y = jump_force
	# 1. Camera-Relative Direction: The held keys as a world-space direction at takeoff.
	_velocity_on_jump = _camera_relative_wish(_input.get_movement_input())
	# 2. Takeoff Speed: Ground speed with the owner's penalties.
	_speed_on_jump = _ground_speed(speed_multiplier)
	# The takeoff is this tick's departure from the floor, so the next airborne tick must not read it as a ledge exit and overwrite the frozen momentum with the keys as they are then.
	_was_on_floor = false


func _ground_speed(speed_multiplier: float) -> float:
	## Auxiliary: Walk or sprint speed (live sprint key) scaled by the owner's penalty multiplier.
	var base_speed := sprint_speed if _input.wants_sprint() else walk_speed
	return base_speed * speed_multiplier


func _camera_relative_wish(move_input: Vector2) -> Vector3:
	## Auxiliary: Projects a camera-relative input Vector2 to a horizontal WORLD wish vector. Shared by
	## ground movement and the momentum captures so they use one camera-basis source.
	## Sign convention: input.y < 0 = forward, input.y > 0 = backward, input.x = strafe (right +).
	return _rig.get_forward_horizontal() * -move_input.y + _rig.get_right_horizontal() * move_input.x
