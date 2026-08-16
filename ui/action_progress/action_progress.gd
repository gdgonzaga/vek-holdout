extends Control
## Generic timed-action progress gauge. Shown by any action that needs to run
## over a fixed duration (today: BuildAction; future: chops, crafts, etc.).
##
## This node owns the per-frame tick because GameActions are Resources — they
## have no _ready/_process and never enter the scene tree. Callers configure it
## via setup() and react via the completed / cancelled signals; the gauge itself
## knows nothing about what it is timing (no Blueprint, no Player references).
##
## Lifecycle: instantiated by the triggering action, mounted on a CanvasLayer,
## freed on completion or cancel. Registers with UiGate while up, which shows
## the cursor (so the Cancel button is clickable) and blocks gameplay input;
## CameraRig only orbits while the mouse is captured, so camera-look freezes
## too. Unregistering on free re-captures the cursor.

## Fired exactly once when the bar fills to `duration`.
signal completed()

## Fired exactly once on cancel. Carries seconds worked so the caller can
## persist partial progress and resume later via setup(..., start_elapsed).
signal cancelled(elapsed: float)

@onready var _title_label: Label = $Panel/VBox/Header/TitleLabel
@onready var _cancel_button: Button = $Panel/VBox/Header/CancelButton
@onready var _bar: ProgressBar = $Panel/VBox/ProgressBar

var _duration: float = 0.0
var _elapsed: float = 0.0
## Guards against double-settle (Cancel clicked then Esc, or two frames racing)
## so exactly one of completed / cancelled is ever emitted.
var _settled := false


func _ready() -> void:
	UiGate.open_modal(self)


func _exit_tree() -> void:
	UiGate.close_modal(self)


## Configure and start the gauge.
##   label_text    — title shown in the header.
##   duration      — seconds the bar takes to fill.
##   start_elapsed — seconds already worked (resume); 0 for a fresh action.
func setup(label_text: String, duration: float, start_elapsed: float = 0.0) -> void:
	_duration = max(duration, 0.001) # avoid divide-by-zero on a malformed def
	_elapsed = start_elapsed
	# Defer until the node is in the tree so @onready has resolved.
	if not is_node_ready():
		ready.connect(_begin.bind(label_text), CONNECT_ONE_SHOT)
	else:
		_begin(label_text)


func _begin(label_text: String) -> void:
	_title_label.text = label_text if label_text != "" else "Working..."
	_cancel_button.pressed.connect(_cancel)
	_update_bar()
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	_update_bar()
	if _elapsed >= _duration:
		_settle(true)


func _update_bar() -> void:
	_bar.value = clampf(_elapsed / _duration, 0.0, 1.0) * 100.0


func _cancel() -> void:
	_settle(false)


## Emit exactly one terminal signal, stop ticking, and free. UiGate re-captures
## the cursor when the freed gauge unregisters.
func _settle(success: bool) -> void:
	if _settled:
		return
	_settled = true
	set_process(false)
	if success:
		completed.emit()
	else:
		cancelled.emit(_elapsed)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
