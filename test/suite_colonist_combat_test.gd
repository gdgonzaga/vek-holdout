extends GdUnitTestSuite

## Unit tests for ColonistCombat (GDD §6.7 "Fight" stance, MVP subset) and
## BTActionColonistCombatAttack — reactive weapon combat for any armed colonist,
## from wherever they are, no pursuit. Content-agnostic: weapons are built
## in-memory, never loaded from authored .tres ids.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const BTActionColonistCombatAttackScript = preload("res://subsystems/ai/tasks/actions/bt_action_colonist_combat_attack.gd")
const BTActionScanThreatsScript = preload("res://subsystems/ai/tasks/actions/bt_action_scan_threats.gd")

var _sandbox: ColonySandbox
var _blackboard: Blackboard


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)
	_blackboard = Blackboard.new()


func after_test() -> void:
	_sandbox.restore()


func _make_weapon(action: CombatActionParams) -> ItemDef:
	var item := ItemDef.new()
	item.id = "test_weapon"
	item.weight = 1.0
	item.tags = ["weapon"]
	var equippable := EquippableParams.new()
	equippable.primary_action = action
	item.equippable = equippable
	return item


func _make_melee_action(p_range: float = 2.0, p_cooldown: float = 0.5) -> MeleeActionParams:
	var action := MeleeActionParams.new()
	action.damage = 10.0
	action.range_meters = p_range
	action.cooldown_seconds = p_cooldown
	action.windup_seconds = 0.0
	action.active_seconds = 0.1
	return action


func _make_target(pos: Vector3) -> Node3D:
	var target := Node3D.new()
	auto_free(target)
	_sandbox.container.add_child(target)
	target.global_position = pos
	return target


# ── ColonistCombat ───────────────────────────────────────────────────────────

func test_unarmed_colonist_has_no_combat_action() -> void:
	var colonist := _sandbox.make_colonist()
	assert_that(colonist.combat.get_combat_action()).is_null()


func test_unarmed_colonist_attack_is_a_noop() -> void:
	var colonist := _sandbox.make_colonist()
	var target := _make_target(colonist.global_position)
	assert_bool(colonist.combat.attack(target)).is_false()


func test_armed_colonist_exposes_combat_action() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.equip_item(_make_weapon(_make_melee_action()))

	assert_that(colonist.combat.get_combat_action()).is_not_null()


func test_target_in_range_boundary() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.equip_item(_make_weapon(_make_melee_action(2.0)))
	colonist.global_position = Vector3.ZERO

	var in_range := _make_target(Vector3(2.0, 0, 0))
	var out_of_range := _make_target(Vector3(2.1, 0, 0))

	assert_bool(colonist.combat.is_target_in_range(in_range)).is_true()
	assert_bool(colonist.combat.is_target_in_range(out_of_range)).is_false()


func test_attack_triggers_weapon_use_animation() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.equip_item(_make_weapon(_make_melee_action(3.0)))
	colonist.global_position = Vector3.ZERO
	var target := _make_target(Vector3(1.0, 0, 0))

	assert_bool(colonist.combat.attack(target)).is_true()

	var anim_tree: AnimationTree = colonist.get_node_or_null("AnimationTree")
	assert_that(anim_tree).is_not_null()
	assert_int(anim_tree.get("parameters/ActionOneshot/request")).is_equal(AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func test_attack_respects_cooldown() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.equip_item(_make_weapon(_make_melee_action(2.0, 1.0)))
	colonist.global_position = Vector3.ZERO
	var target := _make_target(Vector3(1.0, 0, 0))

	assert_bool(colonist.combat.attack(target)).is_true()
	assert_bool(colonist.combat.is_on_cooldown()).is_true()
	assert_bool(colonist.combat.attack(target)).is_false()


# ── BTActionColonistCombatAttack ─────────────────────────────────────────────

func test_bt_attack_fails_without_target() -> void:
	var colonist := _sandbox.make_colonist()
	var task: BTAction = auto_free(BTActionColonistCombatAttackScript.new()) as BTAction
	task.initialize(colonist, _blackboard, colonist)

	assert_int(task.execute(0.1)).is_equal(BTAction.FAILURE)


func test_bt_attack_fails_when_unarmed() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.global_position = Vector3.ZERO
	var target := _make_target(Vector3(1.0, 0, 0))
	_blackboard.set_var(&"threat_target", target)

	var task: BTAction = auto_free(BTActionColonistCombatAttackScript.new()) as BTAction
	task.initialize(colonist, _blackboard, colonist)

	assert_int(task.execute(0.1)).is_equal(BTAction.FAILURE)


func test_bt_attack_fails_when_target_out_of_range() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.equip_item(_make_weapon(_make_melee_action(2.0)))
	colonist.global_position = Vector3.ZERO
	var target := _make_target(Vector3(50.0, 0, 0))
	_blackboard.set_var(&"threat_target", target)

	var task: BTAction = auto_free(BTActionColonistCombatAttackScript.new()) as BTAction
	task.initialize(colonist, _blackboard, colonist)

	assert_int(task.execute(0.1)).is_equal(BTAction.FAILURE)


func test_bt_attack_running_when_engaged_and_halts_movement() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.equip_item(_make_weapon(_make_melee_action(3.0)))
	colonist.global_position = Vector3.ZERO
	colonist.set_path([Vector3(10, 0, 0)])
	var target := _make_target(Vector3(1.0, 0, 0))
	_blackboard.set_var(&"threat_target", target)

	var task: BTAction = auto_free(BTActionColonistCombatAttackScript.new()) as BTAction
	task.initialize(colonist, _blackboard, colonist)

	assert_int(task.execute(0.1)).is_equal(BTAction.RUNNING)
	assert_bool(colonist.has_arrived()).is_true()


func test_bt_attack_fails_when_target_is_dead() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.equip_item(_make_weapon(_make_melee_action(3.0)))
	colonist.global_position = Vector3.ZERO
	var target := _sandbox.make_colonist()
	target.global_position = Vector3(1.0, 0, 0)
	target.take_damage(1000000, null)
	_blackboard.set_var(&"threat_target", target)

	var task: BTAction = auto_free(BTActionColonistCombatAttackScript.new()) as BTAction
	task.initialize(colonist, _blackboard, colonist)

	assert_int(task.execute(0.1)).is_equal(BTAction.FAILURE)


func test_bt_attack_fails_gracefully_when_target_is_freed() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.equip_item(_make_weapon(_make_melee_action(3.0)))
	colonist.global_position = Vector3.ZERO

	# A ranged/melee hit can free the target (EnemyBase queue_frees on death)
	# in the same tick that killed it; by the *next* tick the blackboard still
	# holds a stale reference to an already-freed object.
	var target := Node3D.new()
	_sandbox.container.add_child(target)
	_blackboard.set_var(&"threat_target", target)
	target.free()

	var task: BTAction = auto_free(BTActionColonistCombatAttackScript.new()) as BTAction
	task.initialize(colonist, _blackboard, colonist)

	assert_int(task.execute(0.1)).is_equal(BTAction.FAILURE)


# ── Weapon Range & Facing Tests ──────────────────────────────────────────────

func test_get_attack_range_reflects_weapon() -> void:
	var colonist := _sandbox.make_colonist()
	assert_float(colonist.combat.get_attack_range()).is_equal(0.0)

	colonist.equip_item(_make_weapon(_make_melee_action(1.0)))
	assert_float(colonist.combat.get_attack_range()).is_equal(1.0)

	colonist.equip_item(_make_weapon(_make_melee_action(3.5)))
	assert_float(colonist.combat.get_attack_range()).is_equal(3.5)


func test_attack_faces_target() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.equip_item(_make_weapon(_make_melee_action(2.0)))
	colonist.global_position = Vector3.ZERO
	# Target positioned along +X axis (angle PI/2)
	var target := _make_target(Vector3(1.5, 0, 0))

	assert_bool(colonist.combat.attack(target)).is_true()
	var anim_ctrl: ColonistAnimationController = colonist.get_node_or_null("ColonistAnimationController") as ColonistAnimationController
	assert_that(anim_ctrl).is_not_null()
	if anim_ctrl and anim_ctrl.visuals:
		# atan2(1.5, 0) == PI / 2.0 (~1.57)
		assert_float(anim_ctrl.visuals.rotation.y).is_between(1.5, 1.6)


func test_face_target_method_rotates_visuals() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.global_position = Vector3.ZERO
	var anim_ctrl: ColonistAnimationController = colonist.get_node_or_null("ColonistAnimationController") as ColonistAnimationController
	assert_that(anim_ctrl).is_not_null()
	if anim_ctrl and anim_ctrl.visuals:
		anim_ctrl.face_target(Vector3(0, 0, 2.0))
		# Target directly in front along +Z: atan2(0, 2.0) == 0.0
		assert_float(anim_ctrl.visuals.rotation.y).is_between(-0.01, 0.01)

		anim_ctrl.face_target(Vector3(-2.0, 0, 0))
		# Target along -X: atan2(-2.0, 0) == -PI/2 (~ -1.57)
		assert_float(anim_ctrl.visuals.rotation.y).is_between(-1.6, -1.5)


func test_play_animation_override_idle_does_not_fire_attack_oneshot() -> void:
	var colonist := _sandbox.make_colonist()
	var anim_ctrl: ColonistAnimationController = colonist.get_node_or_null("ColonistAnimationController") as ColonistAnimationController
	var anim_tree: AnimationTree = colonist.get_node_or_null("AnimationTree") as AnimationTree
	assert_that(anim_ctrl).is_not_null()
	assert_that(anim_tree).is_not_null()

	# Prime action overlay with AttackOverhead
	anim_ctrl.trigger_action(&"AttackOverhead")
	assert_int(anim_tree.get("parameters/ActionOneshot/request")).is_equal(AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

	# Overriding with Idle must abort the one-shot rather than re-firing AttackOverhead
	anim_ctrl.play_animation_override(&"Idle")
	assert_int(anim_tree.get("parameters/ActionOneshot/request")).is_equal(AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


func test_scan_threats_use_weapon_range_unarmed_fails() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.global_position = Vector3.ZERO
	var enemy := _make_target(Vector3(1.0, 0, 0))
	enemy.add_to_group(&"enemies")

	var task: BTAction = auto_free(BTActionScanThreatsScript.new()) as BTAction
	task.use_weapon_range = true
	var groups: Array[StringName] = [&"enemies"]
	task.threat_groups = groups
	task.initialize(colonist, _blackboard, colonist)

	# Unarmed colonist must fail threat scan even when an enemy is 1.0m away
	assert_int(task.execute(0.1)).is_equal(BTAction.FAILURE)
	assert_bool(_blackboard.has_var(&"threat_target")).is_false()


func test_scan_threats_use_weapon_range_armed_filters_distant_threat() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.equip_item(_make_weapon(_make_melee_action(1.0)))
	colonist.global_position = Vector3.ZERO

	var enemy := _make_target(Vector3(5.0, 0, 0))
	enemy.add_to_group(&"enemies")

	var task: BTAction = auto_free(BTActionScanThreatsScript.new()) as BTAction
	task.use_weapon_range = true
	var groups: Array[StringName] = [&"enemies"]
	task.threat_groups = groups
	task.initialize(colonist, _blackboard, colonist)

	# Enemy at 5.0m is outside 1.0m weapon reach -> scan fails, no threat target set
	assert_int(task.execute(0.1)).is_equal(BTAction.FAILURE)
	assert_bool(_blackboard.has_var(&"threat_target")).is_false()


	# Move enemy into 0.8m reach -> scan succeeds
	enemy.global_position = Vector3(0.8, 0, 0)
	assert_int(task.execute(0.1)).is_equal(BTAction.SUCCESS)
	assert_object(_blackboard.get_var(&"threat_target")).is_equal(enemy)


func test_scan_threats_clears_stale_target_when_threat_leaves_range() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.equip_item(_make_weapon(_make_melee_action(1.0)))
	colonist.global_position = Vector3.ZERO

	var enemy := _make_target(Vector3(0.8, 0, 0))
	enemy.add_to_group(&"enemies")

	var task: BTAction = auto_free(BTActionScanThreatsScript.new()) as BTAction
	task.use_weapon_range = true
	var groups: Array[StringName] = [&"enemies"]
	task.threat_groups = groups
	task.initialize(colonist, _blackboard, colonist)

	# Enemy in range -> scan succeeds, threat_target set
	assert_int(task.execute(0.1)).is_equal(BTAction.SUCCESS)
	assert_object(_blackboard.get_var(&"threat_target")).is_equal(enemy)

	# Enemy walks back out of weapon reach -> a stale threat_target must not
	# survive the rescan (ColonistBrain's need-lock suspension, and any future
	# fight-or-flight logic, depend on this being current, not a memory).
	enemy.global_position = Vector3(5.0, 0, 0)
	assert_int(task.execute(0.1)).is_equal(BTAction.FAILURE)
	assert_bool(_blackboard.has_var(&"threat_target")).is_false()



func test_bt_attack_faces_target_during_tick() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.equip_item(_make_weapon(_make_melee_action(2.0)))
	colonist.global_position = Vector3.ZERO
	var target := _make_target(Vector3(1.0, 0, 0))
	_blackboard.set_var(&"threat_target", target)

	var task: BTAction = auto_free(BTActionColonistCombatAttackScript.new()) as BTAction
	task.initialize(colonist, _blackboard, colonist)

	assert_int(task.execute(0.1)).is_equal(BTAction.RUNNING)
	var anim_ctrl: ColonistAnimationController = colonist.get_node_or_null("ColonistAnimationController") as ColonistAnimationController
	assert_that(anim_ctrl).is_not_null()
	if anim_ctrl and anim_ctrl.visuals:
		# Should have started rotating towards +X (angle ~1.57)
		assert_float(anim_ctrl.visuals.rotation.y).is_greater(0.5)


## While engaged the colonist keeps looking at the threat's center mass; leaving
## the task (threat gone, branch aborted) releases the look.
func test_bt_attack_looks_at_target_until_exit() -> void:
	var colonist := _sandbox.make_colonist()
	colonist.equip_item(_make_weapon(_make_melee_action(2.0)))
	colonist.global_position = Vector3.ZERO
	var target := _make_target(Vector3(1.0, 0, 0))
	_blackboard.set_var(&"threat_target", target)

	var task: BTAction = auto_free(BTActionColonistCombatAttackScript.new()) as BTAction
	task.initialize(colonist, _blackboard, colonist)
	assert_int(task.execute(0.1)).is_equal(BTAction.RUNNING)

	var anim_ctrl := colonist.get_node("ColonistAnimationController") as ColonistAnimationController
	assert_object(anim_ctrl._look_target).is_same(target)

	task.abort()
	assert_that(anim_ctrl._look_target).is_null()

