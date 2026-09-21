extends GdUnitTestSuite

## Player locomotion: ground walk/sprint, jump and air momentum, ledge exit, and the
## input lock. A dead player takes no input, and the speed carried through a jump keeps
## the penalty that applies while walking.
## Content-agnostic: the need penalty is an in-memory NeedDef and the floor is a
## test-built StaticBody3D.

const PlayerScene = preload("res://subsystems/player/player.tscn")
const MiningRig = preload("res://test/helpers/mining_rig.gd")

const PENALIZED_NEED := &"hunger"
const PENALTY_MULT := 0.5

var _saved_current_map: Node = null


func before_test() -> void:
	_saved_current_map = SceneManager._current_map
	ColonistNeeds._cached_need_defs.clear()
	ColonistNeeds._defs_loaded = true


func after_test() -> void:
	SceneManager._current_map = _saved_current_map
	Input.action_release(&"move_forward")
	Input.action_release(&"jump")
	Input.action_release(&"sprint")
	Input.action_release(&"move_backward")
	ColonistNeeds._cached_need_defs.clear()
	ColonistNeeds._defs_loaded = false


func test_dead_player_ignores_movement_input() -> void:
	# Break caught: the movement handler rewrites state every tick, so a corpse keeps
	# walking and reads WALK instead of DEAD.
	var player := await _spawn_grounded_player()
	player.take_damage(1000)

	Input.action_press(&"move_forward")
	await _physics_frames(3)

	assert_int(player.state).is_equal(Player.State.DEAD)
	assert_float(_horizontal_speed(player)).is_equal(0.0)


func test_dead_player_cannot_jump() -> void:
	# Break caught: _handle_jump only checks the busy lock, so a corpse can still leave the floor.
	var player := await _spawn_grounded_player()
	player.take_damage(1000)

	Input.action_press(&"jump")
	await _physics_frames(5)

	assert_bool(player.is_on_floor()).is_true()


func test_dead_player_cannot_open_the_build_menu() -> void:
	# Break caught: hotkey handlers only check the busy lock, so a dead player can still open modals.
	_mount_ui_layer()
	var player := _spawn_player()
	player.take_damage(1000)

	player.get_node("InputComponent").build_toggle_pressed.emit()

	assert_int(player.mode).is_equal(Player.Mode.NORMAL)


func test_living_player_opens_the_build_menu() -> void:
	# Control for the dead-player test above: the same hotkey path must work while alive,
	# otherwise that test would pass without the death guard doing anything.
	_mount_ui_layer()
	var player := _spawn_player()

	player.get_node("InputComponent").build_toggle_pressed.emit()

	assert_int(player.mode).is_equal(Player.Mode.BUILD_MENU)


func test_jump_keeps_the_depleted_need_speed_penalty() -> void:
	# Break caught: takeoff speed taken from the raw walk speed, so jumping sheds the
	# slowdown a depleted need applies on the ground.
	_install_speed_penalty(PENALIZED_NEED, PENALTY_MULT)
	var player := await _spawn_grounded_player()
	player.needs.set_need(PENALIZED_NEED, 0.0)
	var penalized_speed := _walk_speed(player) * PENALTY_MULT

	Input.action_press(&"move_forward")
	await _physics_frames(3)
	# Guard against a vacuous pass: the penalty must actually be active on the ground.
	assert_float(_horizontal_speed(player)).is_equal_approx(penalized_speed, 0.01)

	Input.action_press(&"jump")
	await _wait_until_airborne(player)
	# One more tick so the reading comes from the airborne branch, not the takeoff tick.
	await _physics_frames(2)

	assert_float(_horizontal_speed(player)).is_equal_approx(penalized_speed, 0.01)


func test_walking_moves_at_walk_speed_and_reports_walk() -> void:
	# Break caught: the wrong base speed on the ground, or a state other than WALK while walking.
	var player := await _spawn_grounded_player()

	Input.action_press(&"move_forward")
	await _physics_frames(3)

	assert_float(_horizontal_speed(player)).is_equal_approx(_walk_speed(player), 0.01)
	assert_int(player.state).is_equal(Player.State.WALK)


func test_wading_slows_walking_by_the_fluid_the_body_is_in() -> void:
	# Break caught: the drag ignoring the fluid's own multiplier (the old code hardcoded one drag
	# for one block id), or never looking at the running map's grid at all. The grid double reports
	# a 0.5 drag for every cell, so ground speed must be exactly half the walk speed.
	var rig := MiningRig.new(self)
	rig.blocky.wading_mult = 0.5
	SceneManager._current_map = rig.map
	var player := await _spawn_grounded_player()

	Input.action_press(&"move_forward")
	await _physics_frames(3)

	assert_float(_horizontal_speed(player)).is_equal_approx(_walk_speed(player) * 0.5, 0.01)
	# The drag is sampled at the lower torso: the player stands on a slab whose top is y = 0, so
	# 0.2 m above the feet is voxel row 0 (a head-height sample would land in row 1 or higher).
	assert_int(rig.blocky.last_wading_query.y).is_equal(0)


func test_walking_without_a_running_map_is_not_slowed() -> void:
	# Break caught: a null map crashing the per-tick speed calculation, or defaulting to a drag.
	SceneManager._current_map = null
	var player := await _spawn_grounded_player()

	Input.action_press(&"move_forward")
	await _physics_frames(3)

	assert_float(_horizontal_speed(player)).is_equal_approx(_walk_speed(player), 0.01)


func test_sprinting_moves_at_sprint_speed_and_reports_sprint() -> void:
	# Break caught: the sprint key not selecting the sprint speed, or state staying WALK.
	var player := await _spawn_grounded_player()

	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	await _physics_frames(3)

	assert_float(_horizontal_speed(player)).is_equal_approx(_sprint_speed(player), 0.01)
	assert_int(player.state).is_equal(Player.State.SPRINT)


func test_standing_still_reports_idle_and_does_not_move() -> void:
	# Break caught: leftover wish velocity sliding the player, or a stale WALK state with no keys held.
	var player := await _spawn_grounded_player()

	await _physics_frames(3)

	assert_float(_horizontal_speed(player)).is_equal(0.0)
	assert_int(player.state).is_equal(Player.State.IDLE)


func test_jump_carries_takeoff_momentum_while_the_key_stays_held() -> void:
	# Break caught: the frozen takeoff momentum lost or rescaled mid-air. Forward is -Z at the
	# default camera yaw, so the whole walk speed must remain on -Z.
	var player := await _spawn_grounded_player()
	Input.action_press(&"move_forward")
	await _physics_frames(3)

	Input.action_press(&"jump")
	await _wait_until_airborne(player)
	await _physics_frames(2)

	assert_float(player.velocity.z).is_equal_approx(-_walk_speed(player), 0.01)
	assert_float(player.velocity.x).is_equal_approx(0.0, 0.01)


func test_jump_lifts_the_body_on_the_tick_the_key_is_seen() -> void:
	# Break caught: the jump check running after move_and_slide, so the impulse sat unused for a
	# whole physics tick and takeoff lagged the key press by a frame. Ticked by hand so exactly one
	# tick passes between the key press and the reading.
	var player := await _spawn_grounded_player()
	player.set_physics_process(false)
	var start_height := player.global_position.y
	Input.action_press(&"jump")

	player.motor.tick(1.0 / 60.0, false, 1.0)

	assert_float(player.global_position.y).is_greater(start_height + 0.01)


func test_takeoff_momentum_is_not_re_captured_as_a_ledge_exit() -> void:
	# Break caught: the first airborne tick of a quick tap counting as "stepped off a ledge" and
	# overwriting the frozen takeoff momentum with whatever the keys say now. Hand-derived: the jump
	# froze forward (-Z) momentum; switching to the backward key with the jump released can then only
	# NUDGE against it, so the horizontal velocity is jump_move_speed (0.5) x takeoff speed toward +Z.
	# A re-capture would freeze the backward direction instead and carry the full walk speed toward +Z.
	var player := await _spawn_grounded_player()
	player.set_physics_process(false)
	Input.action_press(&"move_forward")
	Input.action_press(&"jump")
	player.motor.tick(1.0 / 60.0, false, 1.0)

	Input.action_release(&"jump")
	Input.action_release(&"move_forward")
	Input.action_press(&"move_backward")
	player.motor.tick(1.0 / 60.0, false, 1.0)

	assert_float(player.velocity.z).is_equal_approx(0.5 * _walk_speed(player), 0.01)


func test_releasing_the_key_mid_air_stops_horizontal_movement() -> void:
	# Break caught: coasting. With neither key held an axis snaps to zero (no air drift).
	var player := await _spawn_grounded_player()
	Input.action_press(&"move_forward")
	await _physics_frames(3)
	Input.action_press(&"jump")
	await _wait_until_airborne(player)

	Input.action_release(&"move_forward")
	await _physics_frames(2)

	assert_float(_horizontal_speed(player)).is_equal(0.0)


func test_turning_the_camera_mid_air_does_not_curve_the_frozen_momentum() -> void:
	# Break caught: momentum re-projected onto the live camera. After a +90 degree yaw the camera
	# looks along -X while the momentum still points along -Z (their dot is 0), so the held forward
	# key can only NUDGE: jump_move_speed (0.5) along -X, scaled by the frozen takeoff speed. A
	# re-projecting implementation would instead carry the full walk speed along -X.
	var player := await _spawn_grounded_player()
	Input.action_press(&"move_forward")
	await _physics_frames(3)
	Input.action_press(&"jump")
	await _wait_until_airborne(player)

	player._rig.set_orientation(deg_to_rad(90.0), 0.0)
	await _physics_frames(2)

	assert_float(player.velocity.x).is_equal_approx(-0.5 * _walk_speed(player), 0.01)
	assert_float(player.velocity.z).is_equal_approx(0.0, 0.01)


func test_stepping_off_a_ledge_keeps_walking_speed() -> void:
	# Break caught: no takeoff capture on ledge exit, so walking off an edge kills all momentum
	# (the frozen speed would still be zero) instead of carrying the walk speed on.
	var player := await _spawn_grounded_player(Vector3(0.0, 0.1, -19.5))
	Input.action_press(&"move_forward")

	await _wait_until_airborne(player)
	await _physics_frames(2)

	assert_float(player.velocity.z).is_equal_approx(-_walk_speed(player), 0.01)


# --- Fixtures ----------------------------------------------------------------

## Auxiliary: A player in the test tree with no floor.
func _spawn_player() -> Player:
	var player: Player = auto_free(PlayerScene.instantiate())
	add_child(player)
	return player


## Auxiliary: A player resting on a test-built slab, settled onto it before returning
## (GroundSafetyGuard snaps on the first tick, then gravity lands the body a few ticks later).
func _spawn_grounded_player(start: Vector3 = Vector3(0.0, 0.1, 0.0)) -> Player:
	var slab_body: StaticBody3D = auto_free(StaticBody3D.new())
	var collider := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(40.0, 1.0, 40.0)
	collider.shape = slab
	slab_body.add_child(collider)
	slab_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(slab_body)

	var player: Player = auto_free(PlayerScene.instantiate())
	player.position = start
	add_child(player)
	for _i in range(30):
		if player.is_on_floor():
			break
		await get_tree().physics_frame
	assert_bool(player.is_on_floor()).is_true()
	return player


## Auxiliary: A "ui_layer" CanvasLayer owned by the test, so menus the player mounts
## are freed with it instead of leaking modal state into later suites.
func _mount_ui_layer() -> void:
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	layer.add_to_group("ui_layer")
	add_child(layer)


## Auxiliary: Registers an in-memory NeedDef whose depletion multiplies locomotion speed.
func _install_speed_penalty(need_id: StringName, multiplier: float) -> void:
	var def: NeedDef = NeedDef.new()
	def.id = need_id
	def.depletion_speed_mult = multiplier
	ColonistNeeds._cached_need_defs[need_id] = def


## Auxiliary: Awaits `count` physics ticks.
func _physics_frames(count: int) -> void:
	for _i in range(count):
		await get_tree().physics_frame


## Auxiliary: Awaits physics ticks until the player leaves the floor (bounded).
func _wait_until_airborne(player: Player) -> void:
	for _i in range(30):
		if not player.is_on_floor():
			return
		await get_tree().physics_frame
	assert_bool(player.is_on_floor()).is_false()


## Auxiliary: Horizontal speed in world units per second.
func _horizontal_speed(player: Player) -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


## Auxiliary: The tunable ground speeds, read through one place so tests don't care which
## node owns them.
func _walk_speed(player: Player) -> float:
	return player.motor.walk_speed


func _sprint_speed(player: Player) -> float:
	return player.motor.sprint_speed
