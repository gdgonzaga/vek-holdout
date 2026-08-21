class_name InputComponent
extends Node
## Reads raw player input and exposes it via query methods.
##
## The single choke point for gameplay input: every read — discrete actions
## (build toggle, interact, click-to-recapture, blueprint cancel) through
## _unhandled_input and continuous actions (movement, sprint, jump) via the
## per-frame query methods — goes dead while UiGate reports a modal UI open, so
## gameplay keys can never leak through an open screen or stack screens.

## Emitted when the player presses the build toggle key (B).
signal build_toggle_pressed()

## Emitted when the player presses the dig box toggle key (Shift+G).
signal dig_box_toggle_pressed()

## Emitted when the player clicks the primary action button (LMB) during gameplay.
signal primary_action_pressed()

## Emitted when the player presses the interact key (E).
signal interact_pressed()

## Emitted when the player releases the interact key (E).
signal interact_released()

## Emitted when the player clicks while the cursor is visible (requesting
## mouse recapture).
signal recapture_requested()

## Emitted when the player presses ui_cancel (Esc).
signal ui_cancel_pressed()


# Wheel events are InputEventMouseButton with pressed == true; exclude them from
# the click-to-recapture trigger so scrolling a visible-cursor UI (e.g. the build
# menu) doesn't yank the cursor back into MOUSE_MODE_CAPTURED.
const _WHEEL_BUTTONS := [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN,
		MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]


func _unhandled_input(event: InputEvent) -> void:
	# Open panels own the keyboard (including their Esc handling); only the
	# click-to-recapture recovery stays reachable with a visible cursor, and
	# even that is part of gameplay, not of a panel.
	if UiGate.is_input_blocked():
		return
	if event.is_action_pressed("build_toggle"):
		build_toggle_pressed.emit()
		return
	if event.is_action_pressed("dig_box_toggle"):
		dig_box_toggle_pressed.emit()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT 			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		primary_action_pressed.emit()
		return
	if event.is_action_pressed("interact"):
		interact_pressed.emit()
		return
	if event.is_action_released("interact"):
		interact_released.emit()
		return
	if event is InputEventMouseButton and event.pressed \
			and not event.button_index in _WHEEL_BUTTONS \
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		recapture_requested.emit()
		return
	if event.is_action_pressed("ui_cancel"):
		ui_cancel_pressed.emit()
		return


## Normalized camera-relative movement input (WASD).
## Positive y = backward, negative y = forward, positive x = right, negative x = left.
func get_movement_input() -> Vector2:
	if UiGate.is_input_blocked():
		return Vector2.ZERO
	var input := Vector2.ZERO
	if Input.is_action_pressed("move_forward"): input += Vector2.UP
	if Input.is_action_pressed("move_backward"): input += Vector2.DOWN
	if Input.is_action_pressed("move_right"): input += Vector2.RIGHT
	if Input.is_action_pressed("move_left"): input += Vector2.LEFT
	return input.normalized()


## Whether the jump key (Space) is currently held.
func wants_jump() -> bool:
	return not UiGate.is_input_blocked() and Input.is_action_pressed("jump")


## Whether the sprint key (Shift) is currently held.
func wants_sprint() -> bool:
	return not UiGate.is_input_blocked() and Input.is_action_pressed("sprint")
