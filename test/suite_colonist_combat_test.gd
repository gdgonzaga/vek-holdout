extends GdUnitTestSuite

## Unit tests for ColonistCombat (GDD §6.7 "Fight" stance, MVP subset) and
## BTActionColonistCombatAttack — reactive weapon combat for any armed colonist,
## from wherever they are, no pursuit. Content-agnostic: weapons are built
## in-memory, never loaded from authored .tres ids.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const BTActionColonistCombatAttackScript = preload("res://subsystems/ai/tasks/actions/bt_action_colonist_combat_attack.gd")

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
