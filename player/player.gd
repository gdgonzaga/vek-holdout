class_name Player
extends CharacterBody3D
## Minimal third-person controller (ARCH "Subsystem: Player").
##
## This build covers only walk + gravity + mouse-look. The Mode/State enums and
## the full state set are defined now so later features (sprint, attack, build
## mode...) fill in without restructuring. Movement references no stat components
## yet — Breath/Stamina/Health attach later as child nodes the code can opt into.
##
## TODO when CharacterDef lands: source move_speed/gravity from
## data/characters/player.tres instead of these exports (ARCH: no hardcoded
## content values). Exported for now so they're editor-tunable.

enum Mode { NORMAL, BLUEPRINT }
enum State { IDLE, WALK, SPRINT, ATTACK, INTERACT, SLEEP, DEAD }

@export var walk_speed := 3.5
@export var sprint_speed := 7
@export var gravity := 9.8
@export var jump_force := 5.0
@export var jump_move_speed := 0.5

var mode := Mode.NORMAL
var state := State.IDLE

@onready var _rig: CameraRig = $CameraRig
@onready var _mesh: MeshInstance3D = $MeshInstance3D

var _velocity_on_jump := Vector3.ZERO  # horizontal world-velocity frozen at jump (y=0)
var _speed_on_jump := 0.0              # walk_speed or sprint_speed, frozen at takeoff
var _is_sprinting_on_jump := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# Esc/pause is owned by Core (main.gd -> GameState.set_paused). Player does
	# NOT consume ui_cancel so it bubbles up. The pause menu (when it lands) will
	# release the cursor; for now the mouse stays captured during pause.
	# Click to recapture the mouse if it was released (e.g. alt-tab).
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	_handle_move_keys(delta)
	_handle_jump()

func _handle_move_keys(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Horizontal wish-velocity in WORLD space.
	# Ground: fresh each frame from camera-relative WASD.
	# Mid-air: starts from the frozen jump velocity; keys only BRAKE it (remove the
	# component opposing the held direction) — they never re-project the stored
	# vector, so rotating the camera mid-air can't curve movement. Keys are still
	# read relative to the live camera (W still means "away from where I look"),
	# but only to decide which component of the world-velocity to kill.
	var wish := Vector3.ZERO

	if is_on_floor():
		# Ground: camera-relative WASD, normalized, projected to world.
		var input := Vector2.ZERO
		if Input.is_action_pressed("move_forward"): input += Vector2.UP
		if Input.is_action_pressed("move_backward"): input += Vector2.DOWN
		if Input.is_action_pressed("move_right"): input += Vector2.RIGHT
		if Input.is_action_pressed("move_left"): input += Vector2.LEFT
		wish = _camera_relative_wish(input.normalized())

	else:
		# Mid-air: the two cardinal axes (forward/back, strafe) are resolved
		# INDEPENDENTLY, each against the captured world-momentum projected onto
		# the live camera directions. Keys are read relative to the live camera
		# (W = away from where you look now); momentum stays world-locked, so
		# rotating the camera mid-air can't curve movement.
		var basis := _rig.global_transform.basis
		var cam_fwd := (-basis.z)
		cam_fwd.y = 0.0
		cam_fwd = cam_fwd.normalized()
		var cam_right := basis.x
		cam_right.y = 0.0
		cam_right = cam_right.normalized()

		# Resolve each axis to a signed scalar (positive = cam_fwd / cam_right).
		var fwd := _resolve_air_axis(
			Input.is_action_pressed("move_backward"),
			Input.is_action_pressed("move_forward"),
			_velocity_on_jump.dot(cam_fwd)
		)
		var strafe := _resolve_air_axis(
			Input.is_action_pressed("move_left"),
			Input.is_action_pressed("move_right"),
			_velocity_on_jump.dot(cam_right)
		)
		wish = cam_fwd * fwd + cam_right * strafe

	# Speed scalar: ground uses the live sprint key; air uses the speed frozen at
	# takeoff so holding/releasing Shift mid-air can't rescale preserved momentum.
	var speed: float
	if is_on_floor():
		speed = sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	else:
		speed = _speed_on_jump
hgi
	velocity.x = wish.x * speed
	velocity.z = wish.z * speed

	move_and_slide()

	# Movement state + visual facing (CharacterBody3D itself never rotates, so the
	# camera rig's orbit is decoupled from where the avatar looks).
	if wish.length_squared() > 0.001:
		# SPRINT only while grounded + sprinting; mid-air carries momentum but
		# isn't "sprinting" (state reflects what the avatar is doing, not what it
		# did at takeoff).
		var sprinting := is_on_floor() and Input.is_action_pressed("sprint")
		state = State.SPRINT if sprinting else State.WALK
		_mesh.look_at(_mesh.global_position + wish, Vector3.UP)
	else:
		state = State.IDLE


func _handle_jump() -> void:
	if not is_on_floor():
		return

	if Input.is_action_pressed("jump"):
		velocity.y = jump_force

		# Capture horizontal wish-velocity in WORLD space at the jump instant. This
		# is frozen for the whole jump — mid-air keys only brake it, never
		# re-project it, so rotating the camera mid-air can't curve movement.
		var input := Vector2.ZERO
		if Input.is_action_pressed("move_forward"): input += Vector2.UP
		if Input.is_action_pressed("move_backward"): input += Vector2.DOWN
		if Input.is_action_pressed("move_right"): input += Vector2.RIGHT
		if Input.is_action_pressed("move_left"): input += Vector2.LEFT

		_velocity_on_jump = _camera_relative_wish(input.normalized())
		# Freeze the takeoff speed so a sprint-jump carries sprint-scale momentum
		# for the whole jump (mid-air Shift can't change it).
		_speed_on_jump = sprint_speed if Input.is_action_pressed("sprint") else walk_speed
		
		if Input.is_action_pressed("sprint"):
			_is_sprinting_on_jump = true
		else:
			_is_sprinting_on_jump = false


## Project a camera-relative input Vector2 to a horizontal WORLD wish-vector.
## Used by both ground movement and the jump-momentum capture so they share one
## source of truth for the camera basis math.
## Sign convention (from the Vector2 gathering above):
##   input.y < 0 = forward, input.y > 0 = backward, input.x = strafe (right +).
func _camera_relative_wish(input: Vector2) -> Vector3:
	var basis := _rig.global_transform.basis
	var forward := (-basis.z)
	forward.y = 0.0
	forward = forward.normalized()
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	return forward * -input.y + right * input.x


## Resolve ONE mid-air cardinal axis to a signed scalar.
## - `neg_held`: is the key driving this axis negative held? (backward / left)
## - `pos_held`: is the key driving this axis positive held? (forward / right)
## - `momentum`: this axis's captured world-momentum component (sign = direction)
## Returns a positive value toward the positive key, negative toward the negative.
##
## Per-axis rule (axes are independent):
##   both keys held            -> 0      (cancel)
##   pos held, momentum > 0    -> momentum (preserve — you jumped that way)
##   pos held, momentum <= 0   -> +jump_move_speed (nudge / brake toward pos)
##   neg held, momentum < 0    -> momentum (preserve)
##   neg held, momentum >= 0   -> -jump_move_speed (nudge / brake toward neg)
##   neither held              -> 0      (snap stop on this axis, no coasting)
func _resolve_air_axis(neg_held: bool, pos_held: bool, momentum: float) -> float:
	if neg_held and pos_held:
		return 0.0                      # conflicting input cancels the axis
	if pos_held:
		return momentum if momentum > 0.0 else jump_move_speed
	if neg_held:
		return momentum if momentum < 0.0 else -jump_move_speed
	return 0.0                          # released -> axis stops dead
