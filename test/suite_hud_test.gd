extends GdUnitTestSuite

## HUD wiring of the inventory panel: the HUD hands the player to the panel, and the
## panel (not the HUD) owns the I / Esc hotkeys and the no-stacking rule.

const PlayerScene = preload("res://subsystems/player/player.tscn")
const HudScene = preload("res://ui/hud/hud.tscn")
const MiningRig = preload("res://test/helpers/mining_rig.gd")

var _other_modal: Node = null


## InteractionComponent double: the hold path (open_interaction_menu) calls interact();
## recorded instead of opening the real interaction-menu UI (which needs a hud_layer mount
## this suite doesn't set up).
class RecordingInteractionComponent extends InteractionComponent:
	var interact_actors: Array[Node] = []

	func interact(actor: Node) -> void:
		interact_actors.append(actor)


## GameAction double: the tap path (execute_default_action) runs the target's first action
## option; recorded instead of doing anything.
class RecordingAction extends GameAction:
	var calls: Array = []

	func execute(actor: Node, target: Node) -> void:
		calls.append([actor, target])


## Bundles the pieces test_tap_.../test_holding_... both need: a HUD wired to a player already
## aimed at a live InteractionComponent double, so E has a real crosshair target to act on.
class AimedHud extends RefCounted:
	var player: Player
	var hud: Control
	var component: RecordingInteractionComponent
	var action: RecordingAction


func after_test() -> void:
	# Leave the global UiGate clean for whichever suite runs next.
	if is_instance_valid(_other_modal):
		UiGate.close_modal(_other_modal)
	_other_modal = null


func _make_hud() -> Control:
	var player: Player = PlayerScene.instantiate()
	auto_free(player)
	add_child(player)
	var hud := auto_free(HudScene.instantiate()) as Control
	add_child(hud)
	hud.setup(player)
	return hud


## Auxiliary: A HUD wired to a player aimed at a live InteractionComponent double (the crosshair
## target the tap/hold paths below need). Two physics ticks let PlayerInteractor.update_target
## latch the target before the caller drives the press/release/process sequence by hand.
func _aimed_hud() -> AimedHud:
	var scene := AimedHud.new()
	var rig := MiningRig.new(self)
	var wall := rig.add_wall(rig.smooth.get_terrain())
	scene.component = RecordingInteractionComponent.new()
	scene.component.name = "InteractionComponent"
	scene.action = RecordingAction.new()
	var option := ActionOption.new()
	option.action = scene.action
	scene.component.action_options.append(option)
	wall.add_child(scene.component)
	scene.player = await rig.spawn_aimed_player()
	scene.hud = auto_free(HudScene.instantiate()) as Control
	add_child(scene.hud)
	scene.hud.setup(scene.player)
	for _i in range(2):
		await get_tree().physics_frame
	return scene


func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame


func test_hud_mounts_the_inventory_panel_closed() -> void:
	var hud := _make_hud()
	var panel := hud.get_node("InventoryPanel") as InventoryPanel
	assert_object(panel).is_not_null()
	assert_bool(panel.is_open()).is_false()
	assert_bool(panel.visible).is_false()


func test_inventory_key_opens_then_closes_the_panel() -> void:
	var hud := _make_hud()
	var panel := hud.get_node("InventoryPanel") as InventoryPanel

	await _press("inventory_toggle")
	assert_bool(panel.is_open()).is_true()

	await _press("inventory_toggle")
	assert_bool(panel.is_open()).is_false()


func test_cancel_key_closes_the_open_panel() -> void:
	var hud := _make_hud()
	var panel := hud.get_node("InventoryPanel") as InventoryPanel
	panel.open()

	await _press("ui_cancel")

	assert_bool(panel.is_open()).is_false()


func test_inventory_key_never_opens_over_another_modal() -> void:
	# Break caught: dropping the UiGate check would stack the inventory on top of a storage panel.
	var hud := _make_hud()
	var panel := hud.get_node("InventoryPanel") as InventoryPanel
	_other_modal = auto_free(Node.new())
	add_child(_other_modal)
	UiGate.open_modal(_other_modal)

	await _press("inventory_toggle")

	assert_bool(panel.is_open()).is_false()


func test_tap_release_before_the_hold_threshold_runs_the_default_action() -> void:
	# Break caught: the tap/hold split not recognizing a quick release (held well under
	# _HOLD_THRESHOLD) as a tap, so E either never runs the quick action or always opens the
	# long-press menu regardless of how briefly it was held.
	var scene := await _aimed_hud()

	scene.hud._on_interact_pressed()
	# No _process tick at all: the hold timer never accumulates, matching a release that
	# lands on literally the same frame as the press (the fastest possible tap).
	scene.hud._on_interact_released()

	assert_int(scene.action.calls.size()).is_equal(1)
	assert_object(scene.action.calls[0][0]).is_same(scene.player)
	assert_int(scene.component.interact_actors.size()).is_equal(0)


func test_holding_past_the_threshold_opens_the_interaction_menu() -> void:
	# Break caught: _process's hold-timer comparison being dropped or inverted, so a held press
	# never opens the interaction menu (or fires it immediately regardless of hold duration).
	var scene := await _aimed_hud()
	# Read live rather than hardcoding: _HOLD_THRESHOLD is a tuning constant on the HUD script,
	# not test content, so a margin above whatever it currently reads keeps this test correct
	# even if the threshold is retuned.
	var threshold: float = scene.hud._HOLD_THRESHOLD

	scene.hud._on_interact_pressed()
	# One oversized _process tick crosses the threshold without a real wait.
	scene.hud._process(threshold + 0.05)

	assert_int(scene.component.interact_actors.size()).is_equal(1)
	assert_object(scene.component.interact_actors[0]).is_same(scene.player)
	assert_int(scene.action.calls.size()).is_equal(0)

	# The hold already fired inside _process; the release that eventually follows must not
	# also run the tap path (that would run both actions off a single press).
	scene.hud._on_interact_released()
	assert_int(scene.action.calls.size()).is_equal(0)
