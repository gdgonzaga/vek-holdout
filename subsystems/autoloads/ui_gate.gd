extends Node
## Central input gate for modal UI (ARCH "UI").
##
## Every modal UI — ad-hoc panels (storage, crafting, interaction menu, build
## menu, action gauge, HUD inventory) and SceneManager full-screen screens —
## registers itself here while open. Gameplay input readers (InputComponent for
## keys, player polling for movement) check is_input_blocked() and go dead, so
## keyboard input can never leak through an open screen or stack screens on top
## of each other. Panels still own their own Esc handling in _unhandled_input;
## UiGate only decides whether gameplay input exists at all.
##
## UiGate is also the single owner of the cursor mode outside gameplay: the
## 0→N modal transition shows the mouse, N→0 re-captures it. Panels must not
## write Input.mouse_mode themselves — call-order between chained opens/closes
## (e.g. interaction menu → storage panel) used to leave the cursor in the
## wrong state.

## Emitted when input blocking starts (true) or ends (false). No consumers yet;
## reserved for reactive HUD (e.g. hiding the crosshair under a panel).
signal input_blocked_changed(blocked: bool)

var _open_modals: Array[Node] = []
var _blocked := false


## Register a modal UI node. Call from _ready (or the open function for panels
## that persist in the scene instead of being freed).
func open_modal(node: Node) -> void:
	if node == null or node in _open_modals:
		return
	_open_modals.append(node)
	_sync()


## Unregister a modal UI node. Call from _exit_tree (or the close function for
## persistent panels). Unknown nodes are ignored, so open/close pairing can
## never wedge the gate.
func close_modal(node: Node) -> void:
	_open_modals.erase(node)
	_sync()


## Whether gameplay input is currently blocked by any open modal UI.
func is_input_blocked() -> bool:
	return _blocked


## Reconcile the blocked state after a membership change: drop entries whose
## nodes were freed without unregistering, then apply the cursor transition.
func _sync() -> void:
	for i in range(_open_modals.size() - 1, -1, -1):
		if not is_instance_valid(_open_modals[i]):
			_open_modals.remove_at(i)
	var blocked := not _open_modals.is_empty()
	if blocked == _blocked:
		return
	_blocked = blocked
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if blocked else Input.MOUSE_MODE_CAPTURED
	input_blocked_changed.emit(blocked)
