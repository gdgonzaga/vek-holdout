class_name CameraRig
extends Node3D
## Third-person orbit rig: SpringArm3D (collision) + Camera3D.
##
## Tracks the parent (the Player) in position; mouse motion orbits around it.
## Yaw is applied to this rig (horizontal swing), pitch to the SpringArm (vertical
## tilt, clamped). The rig follows the avatar without inheriting its visual
## facing, so the camera keeps its orbit independent of where the capsule looks.
##
## LMB/RMB are NOT consumed here — they're reserved for the player's item actions
## (GDD §4). Only mouse motion drives the orbit.

@export var sensitivity := 0.0025
@export var spring_length := 5.0
@export_range(-1.2, 1.2) var min_pitch := -0.8
@export_range(-1.2, 1.2) var max_pitch := 0.6
@export var height_offset := 1.6

var _yaw := 0.0
var _pitch := -0.25
var _spring: SpringArm3D

func _ready() -> void:
	# Build the rig as children so player.tscn only needs the CameraRig node.
	_spring = SpringArm3D.new()
	_spring.spring_length = spring_length
	_spring.collision_mask = 1
	add_child(_spring)

	var cam := Camera3D.new()
	cam.current = true
	_spring.add_child(cam)

	# Raise the pivot so the arm orbits roughly at head height.
	position.y = height_offset

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * sensitivity
		_pitch -= event.relative.y * sensitivity
		_pitch = clamp(_pitch, min_pitch, max_pitch)
		_apply_rotation()

func _apply_rotation() -> void:
	rotation.y = _yaw
	_spring.rotation.x = _pitch
