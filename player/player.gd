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

@export var move_speed := 3.5
@export var gravity := 9.8

var mode := Mode.NORMAL
var state := State.IDLE

@onready var _rig: CameraRig = $CameraRig
@onready var _mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	# Esc releases the cursor. Real pause (GameState.set_paused) is deferred —
	# TODO: route through GameState once Core lands.
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	# Click to recapture after Esc.
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Camera-relative WASD on the ground plane.
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input.y -= 1.0
	if Input.is_key_pressed(KEY_S): input.y += 1.0
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	input = input.normalized()

	var basis := _rig.global_transform.basis
	var forward := (-basis.z)
	forward.y = 0.0
	forward = forward.normalized()
	var right := basis.x
	right.y = 0.0
	right = right.normalized()
	var wish := forward * -input.y + right * input.x

	velocity.x = wish.x * move_speed
	velocity.z = wish.z * move_speed
	move_and_slide()

	# Movement state + visual facing (CharacterBody3D itself never rotates, so the
	# camera rig's orbit is decoupled from where the avatar looks).
	if wish.length_squared() > 0.001:
		state = State.WALK
		_mesh.look_at(_mesh.global_position + wish, Vector3.UP)
	else:
		state = State.IDLE
