class_name InputComponent
extends Node
## Reads raw player input and exposes it via query methods.
##
## Handles discrete actions (build toggle, interact, click-to-recapture,
## blueprint cancel) through _unhandled_input. Continuous actions (movement,
## sprint, jump) are exposed as per-frame query methods called by the parent
## Player in _physics_process.

## Emitted when the player presses the build toggle key (B).
signal build_toggle_pressed()

## Emitted when the player presses the interact key (E).
signal interact_pressed()

## Emitted when the player clicks while the cursor is visible (requesting
## mouse recapture).
signal recapture_requested()

## Emitted when the player presses ui_cancel (Esc).
signal ui_cancel_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_toggle"):
		build_toggle_pressed.emit()
		return
	if event.is_action_pressed("interact"):
		interact_pressed.emit()
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		recapture_requested.emit()
		return
	if event.is_action_pressed("ui_cancel"):
		ui_cancel_pressed.emit()
		return


## Normalized camera-relative movement input (WASD).
## Positive y = backward, negative y = forward, positive x = right, negative x = left.
func get_movement_input() -> Vector2:
	var input := Vector2.ZERO
	if Input.is_action_pressed("move_forward"): input += Vector2.UP
	if Input.is_action_pressed("move_backward"): input += Vector2.DOWN
	if Input.is_action_pressed("move_right"): input += Vector2.RIGHT
	if Input.is_action_pressed("move_left"): input += Vector2.LEFT
	return input.normalized()


## Whether the jump key (Space) is currently held.
func wants_jump() -> bool:
	return Input.is_action_pressed("jump")


## Whether the sprint key (Shift) is currently held.
func wants_sprint() -> bool:
	return Input.is_action_pressed("sprint")
