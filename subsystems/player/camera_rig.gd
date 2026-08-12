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
@export var spring_length := 3.0
@export_range(-1.2, 1.2) var min_pitch := -1.2
@export_range(-1.2, 1.2) var max_pitch := 1.2
@export var height_offset := 1.4
## Horizontal frustum shift: positive moves the view right (body frames screen-left).
## Uses Camera3D.h_offset so the aim direction stays along the spring arm's axis.
@export var h_offset := 0.5
## Vertical frustum shift: negative moves view up (body frames screen-bottom).
## Uses Camera3D.v_offset.
@export var v_offset := 0.4

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
	# Shift the view frustum right/up so the player body sits screen-left/bottom.
	# h_offset/v_offset move what the screen CENTER points at without rotating the
	# camera — this is the correct Godot approach for TPS over-shoulder framing.
	cam.h_offset = h_offset
	cam.v_offset = v_offset
	_spring.add_child(cam)

	# Raise the pivot to eye/shoulder height (capsule top is at 1.6 m).
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


## The active Camera3D (a child of the spring arm). Built in _ready, so callers
## must wait until the rig is ready before requesting this.
func get_camera() -> Camera3D:
	if _spring == null or _spring.get_child_count() == 0:
		return null
	var cam := _spring.get_child(0)
	return cam as Camera3D


# --- SaveSystem contract -----------------------------------------------------
# Yaw/pitch are private orbit state with no setters; these accessors expose them
# for save/load without widening the gameplay API.

## Current yaw (horizontal orbit angle) in radians.
func get_yaw() -> float:
	return _yaw


## Current pitch (vertical tilt) in radians, within [min_pitch, max_pitch].
func get_pitch() -> float:
	return _pitch


## Restore the orbit orientation (radians). Pitch is clamped to the export
## range and both are applied immediately via _apply_rotation. Used by save/load.
func set_orientation(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = clampf(pitch, min_pitch, max_pitch)
	_apply_rotation()
