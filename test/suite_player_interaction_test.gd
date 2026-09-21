extends GdUnitTestSuite

## The player's crosshair interaction: which InteractionComponent is under the crosshair (and
## the announcements that follow), the E-key tap/hold paths, and LMB preferring a manual
## interaction on the crosshair target over mining. Aimed at a wall that stands in for a
## furniture body carrying an InteractionComponent, in front of a smooth-terrain owner so a
## press that wrongly falls through shows up as terrain damage.
## Content-agnostic: the component and its action are in-memory doubles.

const MiningRig = preload("res://test/helpers/mining_rig.gd")


## Records the payload of interactable_changed. A RefCounted receiver, so the connection dies
## with the log instead of leaking into later tests.
class ChangeLog extends RefCounted:
	var components: Array = []

	func _init(changed: Signal) -> void:
		changed.connect(_on_changed)

	func _on_changed(component: InteractionComponent) -> void:
		components.append(component)


## InteractionComponent double: records interact() instead of opening the interaction UI.
class RecordingInteractionComponent extends InteractionComponent:
	var interact_actors: Array[Node] = []

	func interact(actor: Node) -> void:
		interact_actors.append(actor)


## GameAction double that frees its own target synchronously, as an action consuming the thing
## it acts on (a pickup, a harvest) would if it used free() rather than queue_free().
class FreeingAction extends GameAction:
	func execute(_actor: Node, target: Node) -> void:
		target.free()


## Furniture-like body whose interaction options are dynamic: refresh_interaction_options swaps
## the component's options for a fresh one, as a blueprint's remaining-cost option would.
class RefreshingBody extends StaticBody3D:
	var component: InteractionComponent
	var fresh_option: ActionOption

	func refresh_interaction_options() -> void:
		component.action_options = [fresh_option]


## GameAction double: records every execution.
class RecordingAction extends GameAction:
	var calls: Array = []

	func execute(actor: Node, target: Node) -> void:
		calls.append([actor, target])


func test_looking_at_an_interactable_announces_it_and_looking_away_clears_it() -> void:
	# Break caught: the HUD label never learning what is under the crosshair, or never hiding it again.
	var scene := await _aimed_scene()
	var log := ChangeLog.new(_changed_signal(scene.player))

	scene.player._rig.set_orientation(deg_to_rad(90.0), 0.0)
	await _physics_frames(2)
	assert_array(log.components).is_equal([null])

	scene.player._rig.set_orientation(0.0, 0.0)
	await _physics_frames(2)
	assert_array(log.components).is_equal([null, scene.component])


func test_a_component_is_found_from_a_collider_nested_below_its_owner() -> void:
	# Break caught: only a component sitting directly on the struck body being found, so furniture
	# whose collider is a child of the node carrying the InteractionComponent is never targetable.
	var rig := MiningRig.new(self)
	var holder := Node3D.new()
	var component := RecordingInteractionComponent.new()
	component.name = "InteractionComponent"
	holder.add_child(component)
	rig.smooth.get_terrain().add_child(holder)
	rig.add_wall(holder)

	var player := await rig.spawn_aimed_player()
	var log := ChangeLog.new(_changed_signal(player))
	player.mode = Player.Mode.BUILD_MENU
	await _physics_frames(2)
	player.mode = Player.Mode.NORMAL
	await _physics_frames(2)

	assert_array(log.components).is_equal([null, component])


func test_clear_interactable_announces_null_once() -> void:
	# Break caught: SceneManager clearing the target before a map unload either not notifying the
	# HUD (stale label over the title screen) or notifying it repeatedly.
	var scene := await _aimed_scene()
	var log := ChangeLog.new(_changed_signal(scene.player))

	_clear(scene.player)
	_clear(scene.player)

	assert_array(log.components).is_equal([null])


func test_no_target_outside_normal_mode() -> void:
	# Break caught: the crosshair label staying up over a placement or designation mode that owns the cursor.
	var scene := await _aimed_scene()
	var log := ChangeLog.new(_changed_signal(scene.player))

	scene.player.mode = Player.Mode.BUILD_PLACEMENT
	await _physics_frames(2)

	assert_array(log.components).is_equal([null])


func test_tap_e_runs_the_first_action_option_and_re_announces_the_target() -> void:
	# Break caught: the tap not running the first option on the crosshair target, or not re-announcing
	# so a status line (a blueprint's "Plank 3/15") goes stale until the player looks away.
	var scene := await _aimed_scene()
	var log := ChangeLog.new(_changed_signal(scene.player))

	_tap_e(scene.player)

	assert_int(scene.action.calls.size()).is_equal(1)
	assert_object(scene.action.calls[0][0]).is_same(scene.player)
	assert_object(scene.action.calls[0][1]).is_same(scene.wall)
	assert_array(log.components).is_equal([scene.component])


func test_tap_e_runs_the_options_the_target_reports_now() -> void:
	# Break caught: the tap acting on options cached from an earlier frame, so a target whose
	# options change (a blueprint's next cost, a crop's stage) runs a stale action.
	var rig := MiningRig.new(self)
	var body := RefreshingBody.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 20.0, 1.0)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0.0, 0.0, -1.5)
	var stale := RecordingAction.new()
	var fresh := RecordingAction.new()
	body.component = RecordingInteractionComponent.new()
	body.component.name = "InteractionComponent"
	body.component.action_options = [_option_running(stale)]
	body.fresh_option = _option_running(fresh)
	body.add_child(body.component)
	rig.smooth.get_terrain().add_child(body)
	var player := await rig.spawn_aimed_player()
	# The targeting ticks refresh it; put the stale option back so only the tap can fix it.
	body.component.action_options = [_option_running(stale)]

	_tap_e(player)

	assert_int(fresh.calls.size()).is_equal(1)
	assert_int(stale.calls.size()).is_equal(0)


func test_a_target_freed_while_looked_at_is_announced_lost_on_the_next_tick() -> void:
	# Break caught: a freed component compares equal to null, so change detection saw "no target
	# before, none now" and never told the HUD, leaving its label up over an object that is gone.
	var scene := await _aimed_scene()
	var log := ChangeLog.new(_changed_signal(scene.player))

	scene.wall.free()
	await _physics_frames(2)

	assert_array(log.components).is_equal([null])


func test_a_target_freed_in_front_of_other_geometry_is_announced_lost() -> void:
	# Break caught: with something non-interactive behind the freed target, the ray still hits, the
	# component lookup returns nothing, and "nothing" compares equal to the freed component, so the
	# change is never seen and the HUD keeps a label for an object that is gone.
	var scene := await _aimed_scene()
	scene.rig.add_wall(scene.rig.furniture_container, -3.5)
	var log := ChangeLog.new(_changed_signal(scene.player))

	scene.wall.free()
	await _physics_frames(2)

	assert_array(log.components).is_equal([null])


func test_tap_e_on_a_target_the_action_frees_announces_it_lost() -> void:
	# Break caught: the tap re-announcing a component that its own action just freed, handing the
	# HUD a dead object (and leaving the interactor pointing at it).
	var scene := await _aimed_scene()
	scene.component.action_options = [_option_running(FreeingAction.new())]
	var log := ChangeLog.new(_changed_signal(scene.player))

	_tap_e(scene.player)

	assert_array(log.components).is_equal([null])
	assert_object(scene.player.interactor._current_interactable).is_null()


func test_e_on_a_target_freed_since_the_last_tick_drops_it() -> void:
	# Break caught: an E press landing between physics ticks, after the target's owner was removed,
	# reading the freed component (a script error) instead of forgetting it and announcing the loss.
	var scene := await _aimed_scene()
	var log := ChangeLog.new(_changed_signal(scene.player))
	scene.wall.free()

	_tap_e(scene.player)
	_hold_e(scene.player)

	assert_array(log.components).is_equal([null])
	assert_object(scene.player.interactor._current_interactable).is_null()


func test_hold_e_opens_the_interaction_menu_for_the_target() -> void:
	# Break caught: the long press not reaching the crosshair target's component, so no menu opens.
	var scene := await _aimed_scene()

	_hold_e(scene.player)

	assert_array(scene.component.interact_actors).is_equal([scene.player])


func test_e_does_nothing_while_the_player_is_busy() -> void:
	# Break caught: a held player (timed action) still triggering interactions.
	var scene := await _aimed_scene()
	scene.player.set_busy(true)

	_tap_e(scene.player)
	_hold_e(scene.player)

	assert_int(scene.action.calls.size()).is_equal(0)
	assert_int(scene.component.interact_actors.size()).is_equal(0)


func test_lmb_on_a_harvestable_target_does_not_fall_through_to_mining() -> void:
	# Break caught: a manual interaction on the crosshair target (here a Harvestable, which is
	# graceful without furniture params) also mining the terrain behind it, or losing to mining.
	var scene := await _aimed_scene()
	var harvestable := Harvestable.new()
	harvestable.name = "Harvestable"
	scene.wall.add_child(harvestable)
	await _physics_frames(2)

	scene.player.get_node("InputComponent").primary_action_pressed.emit()

	assert_int(scene.rig.smooth.damage_calls).is_equal(0)


# --- Fixtures ----------------------------------------------------------------

## Everything one test needs: the rig, the wall, the component on it, its recording action,
## and the aimed player.
class Scene extends RefCounted:
	var rig: MiningRig
	var wall: StaticBody3D
	var component: RecordingInteractionComponent
	var action: RecordingAction
	var player: Player


## Auxiliary: A wall under the smooth grid carrying a component whose only option runs a
## recording action, with a player aimed at it and the target announced.
func _aimed_scene() -> Scene:
	var scene := Scene.new()
	scene.rig = MiningRig.new(self)
	scene.wall = scene.rig.add_wall(scene.rig.smooth.get_terrain())
	scene.component = RecordingInteractionComponent.new()
	scene.component.name = "InteractionComponent"
	scene.action = RecordingAction.new()
	var option := ActionOption.new()
	option.action = scene.action
	scene.component.action_options.append(option)
	scene.wall.add_child(scene.component)
	scene.player = await scene.rig.spawn_aimed_player()
	return scene


## Auxiliary: An ActionOption whose action is `action`.
func _option_running(action: GameAction) -> ActionOption:
	var option := ActionOption.new()
	option.action = action
	return option


## Auxiliary: Awaits `count` physics ticks.
func _physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


## Auxiliary: The player's target-changed signal, read through one place so tests don't care
## which node owns it.
func _changed_signal(player: Player) -> Signal:
	return player.interactor.interactable_changed


func _clear(player: Player) -> void:
	player.interactor.clear_interactable()


func _tap_e(player: Player) -> void:
	player.interactor.execute_default_action()


func _hold_e(player: Player) -> void:
	player.interactor.open_interaction_menu()
