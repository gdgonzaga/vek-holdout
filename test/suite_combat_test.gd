extends GdUnitTestSuite

## Unit tests for Combat subsystem (HealthComponent, EnemyBase, EnemySwarmer).

const Doubles = preload("res://test/helpers/doubles.gd")
const HealthCompScript = preload("res://subsystems/combat/components/health_component.gd")
const EnemyBaseScript = preload("res://subsystems/combat/enemy_base.gd")
const SwarmerScene = preload("res://subsystems/combat/enemies/enemy_swarmer/enemy_swarmer.tscn")
const BrawlerScene = preload("res://subsystems/combat/enemies/enemy_brawler/enemy_brawler.tscn")
const ShooterScene = preload("res://subsystems/combat/enemies/enemy_shooter/enemy_shooter.tscn")
const PlayerScene = preload("res://subsystems/player/player.tscn")
const ColonySandboxScript = preload("res://test/helpers/colony_sandbox.gd")

var _sandbox: ColonySandboxScript


func before_test() -> void:
	_sandbox = ColonySandboxScript.new(self)


func after_test() -> void:
	_sandbox.restore()


func test_health_component_initialization() -> void:
	var health := HealthCompScript.new() as HealthComponent
	health.max_hp = 80
	health.max_durability = 20
	auto_free(health)
	health._ready()

	assert_int(health.current_hp).is_equal(80)
	assert_int(health.current_durability).is_equal(20)
	assert_bool(health.is_dead).is_false()


func test_health_component_damage_hp_only() -> void:
	var health := HealthCompScript.new() as HealthComponent
	health.max_hp = 100
	health.max_durability = 0
	auto_free(health)
	health._ready()

	health.take_damage(25)
	assert_int(health.current_hp).is_equal(75)
	assert_int(health.current_durability).is_equal(0)
	assert_bool(health.is_dead).is_false()


func test_health_component_durability_absorbs_fully() -> void:
	var health := HealthCompScript.new() as HealthComponent
	health.max_hp = 100
	health.max_durability = 50
	auto_free(health)
	health._ready()

	health.take_damage(30)
	assert_int(health.current_hp).is_equal(100)
	assert_int(health.current_durability).is_equal(20)
	assert_bool(health.is_dead).is_false()


func test_health_component_durability_overflow_to_hp() -> void:
	var health := HealthCompScript.new() as HealthComponent
	health.max_hp = 100
	health.max_durability = 30
	auto_free(health)
	health._ready()

	# 30 absorbs into durability, remaining 20 hits HP
	health.take_damage(50)
	assert_int(health.current_durability).is_equal(0)
	assert_int(health.current_hp).is_equal(80)
	assert_bool(health.is_dead).is_false()


func test_health_component_fatal_damage() -> void:
	var health := HealthCompScript.new() as HealthComponent
	health.max_hp = 50
	health.max_durability = 10
	auto_free(health)
	health._ready()

	var counter := Doubles.SignalCounter.new(health.entity_died)

	health.take_damage(100)
	assert_int(health.current_hp).is_equal(0)
	assert_int(health.current_durability).is_equal(0)
	assert_bool(health.is_dead).is_true()
	assert_int(counter.count).is_equal(1)

	# Further damage when dead should not emit again or change hp
	health.take_damage(50)
	assert_int(counter.count).is_equal(1)
	assert_int(counter.read()).is_equal(1)


func test_health_component_heal_and_repair() -> void:
	var health := HealthCompScript.new() as HealthComponent
	health.max_hp = 100
	health.max_durability = 50
	auto_free(health)
	health._ready()

	health.take_damage(70) # 50 durability + 20 HP -> hp = 80, dur = 0
	assert_int(health.current_hp).is_equal(80)
	assert_int(health.current_durability).is_equal(0)

	health.heal(10)
	assert_int(health.current_hp).is_equal(90)

	health.heal(50) # Clamps to max_hp
	assert_int(health.current_hp).is_equal(100)

	health.repair_durability(25)
	assert_int(health.current_durability).is_equal(25)

	health.repair_durability(50) # Clamps to max_durability
	assert_int(health.current_durability).is_equal(50)


func test_health_component_serialize_deserialize() -> void:
	var health := HealthCompScript.new() as HealthComponent
	health.max_hp = 120
	health.max_durability = 40
	auto_free(health)
	health._ready()
	health.take_damage(50) # dur=0, hp=110

	var saved := health.serialize()

	var restored := HealthCompScript.new() as HealthComponent
	auto_free(restored)
	restored.deserialize(saved)

	assert_int(restored.max_hp).is_equal(120)
	assert_int(restored.max_durability).is_equal(40)
	assert_int(restored.current_hp).is_equal(110)
	assert_int(restored.current_durability).is_equal(0)
	assert_bool(restored.is_dead).is_false()


func test_enemy_swarmer_instantiation() -> void:
	var swarmer := SwarmerScene.instantiate() as EnemyBase
	auto_free(swarmer)
	swarmer._ready()

	assert_that(swarmer).is_not_null()
	assert_that(swarmer.health_component).is_not_null()
	assert_int(swarmer.health_component.max_hp).is_equal(50)
	assert_int(swarmer.health_component.max_durability).is_equal(10)

	swarmer.take_damage(20)
	assert_int(swarmer.health_component.current_durability).is_equal(0)
	assert_int(swarmer.health_component.current_hp).is_equal(40)


func test_enemy_brawler_instantiation() -> void:
	var brawler := BrawlerScene.instantiate() as EnemyBase
	auto_free(brawler)
	brawler._ready()

	assert_that(brawler).is_not_null()
	assert_that(brawler.health_component).is_not_null()
	assert_int(brawler.health_component.max_hp).is_equal(140)
	assert_int(brawler.health_component.max_durability).is_equal(0)
	assert_that(brawler.bt_player).is_not_null()
	assert_that(brawler.bt_player.behavior_tree).is_not_null()
	assert_str(brawler.bt_player.behavior_tree.resource_path).contains("enemy_melee")

	var combat_action: CombatActionParams = brawler.get_combat_action()
	assert_object(combat_action).is_instanceof(MeleeActionParams)

	brawler.take_damage(30)
	assert_int(brawler.health_component.current_hp).is_equal(110)


func test_enemy_shooter_instantiation() -> void:
	var shooter := ShooterScene.instantiate() as EnemyBase
	auto_free(shooter)
	shooter._ready()

	assert_that(shooter).is_not_null()
	assert_that(shooter.health_component).is_not_null()
	assert_int(shooter.health_component.max_hp).is_equal(60)
	assert_int(shooter.health_component.max_durability).is_equal(0)
	assert_that(shooter.bt_player).is_not_null()
	assert_that(shooter.bt_player.behavior_tree).is_not_null()
	assert_str(shooter.bt_player.behavior_tree.resource_path).contains("enemy_ranged_kiter")

	var combat_action: CombatActionParams = shooter.get_combat_action()
	assert_object(combat_action).is_instanceof(RangedActionParams)

	shooter.take_damage(25)
	assert_int(shooter.health_component.current_hp).is_equal(35)


func test_enemy_base_serialize_deserialize() -> void:
	var swarmer := SwarmerScene.instantiate() as EnemyBase
	auto_free(swarmer)
	swarmer._ready()
	swarmer.position = Vector3(10.0, 2.5, -5.0)
	swarmer.velocity = Vector3(1.0, 0.0, -1.0)
	swarmer.take_damage(15)

	var saved := swarmer.serialize()

	var restored := SwarmerScene.instantiate() as EnemyBase
	auto_free(restored)
	restored._ready()
	restored.deserialize(saved)

	assert_float(restored.position.x).is_equal_approx(10.0, 0.01)
	assert_float(restored.position.y).is_equal_approx(2.5, 0.01)
	assert_float(restored.position.z).is_equal_approx(-5.0, 0.01)
	assert_int(restored.health_component.current_hp).is_equal(45)


func test_enemy_base_ai_components_initialization() -> void:
	var swarmer := SwarmerScene.instantiate() as EnemyBase
	auto_free(swarmer)
	swarmer._ready()

	assert_that(swarmer.pathfinder).is_not_null()
	assert_that(swarmer.bt_player).is_not_null()
	assert_that(swarmer.get_node_or_null("StepClimber")).is_not_null()


func test_enemy_base_path_following_locomotion() -> void:
	var swarmer := SwarmerScene.instantiate() as EnemyBase
	auto_free(swarmer)
	add_child(swarmer)
	swarmer.global_position = Vector3.ZERO
	swarmer.set_path([Vector3(5.0, 0.0, 0.0)])
	assert_bool(swarmer.has_arrived()).is_false()

	swarmer._physics_process(0.5)
	assert_float(swarmer.velocity.x).is_greater(0.0)

	swarmer.global_position = Vector3(5.0, 0.0, 0.0)
	swarmer._physics_process(0.1)
	assert_bool(swarmer.has_arrived()).is_true()
	assert_float(swarmer.velocity.x).is_equal_approx(0.0, 0.01)


func test_enemy_base_path_following_with_elevation_step() -> void:
	var swarmer := SwarmerScene.instantiate() as EnemyBase
	auto_free(swarmer)
	add_child(swarmer)
	swarmer.global_position = Vector3.ZERO
	# Path with a step up (> 0.2 Y difference)
	swarmer.set_path([Vector3(1.0, 0.0, 0.0), Vector3(2.0, 1.0, 0.0), Vector3(5.0, 1.0, 0.0)])
	assert_bool(swarmer.has_arrived()).is_false()

	# Simulate moving through waypoints without getting stuck oscillating
	for i in range(100):
		swarmer._physics_process(0.016)
		swarmer.global_position.x += swarmer.velocity.x * 0.016
		if swarmer.has_arrived():
			break

	assert_bool(swarmer.has_arrived()).is_true()


func test_player_has_health_component_after_ready() -> void:
	var player: Player = PlayerScene.instantiate()
	auto_free(player)
	add_child(player)

	assert_that(player.health_component).is_not_null()
	assert_int(player.health_component.max_hp).is_equal(100)
	assert_bool(player.is_dead).is_false()


func test_player_take_damage_and_heal_forward_to_health_component() -> void:
	var player: Player = PlayerScene.instantiate()
	auto_free(player)
	add_child(player)

	player.take_damage(30)
	assert_int(player.health_component.current_hp).is_equal(70)

	player.heal(10)
	assert_int(player.health_component.current_hp).is_equal(80)


func test_player_death_sets_state_and_emits_player_died() -> void:
	var player: Player = PlayerScene.instantiate()
	auto_free(player)
	add_child(player)

	var counter := Doubles.SignalCounter.new(EventBus.player_died)

	player.take_damage(1000)
	assert_bool(player.is_dead).is_true()
	assert_int(player.state).is_equal(Player.State.DEAD)
	assert_int(counter.count).is_equal(1)


func test_player_serialize_deserialize_round_trips_health() -> void:
	var player: Player = PlayerScene.instantiate()
	auto_free(player)
	add_child(player)
	player.take_damage(35)

	var saved := player.serialize()

	var restored: Player = PlayerScene.instantiate()
	auto_free(restored)
	add_child(restored)
	restored.deserialize(saved)

	assert_int(restored.health_component.current_hp).is_equal(65)


func test_colonist_has_health_component_after_ready() -> void:
	var colonist: Colonist = _sandbox.make_colonist()

	assert_that(colonist.health_component).is_not_null()
	assert_int(colonist.health_component.max_hp).is_equal(colonist.colonist_def.max_hp)
	assert_bool(colonist.is_dead).is_false()


func test_colonist_take_damage_and_heal_forward_to_health_component() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var starting_hp := colonist.get_max_hp()

	colonist.take_damage(30, null)
	assert_int(colonist.get_hp()).is_equal(starting_hp - 30)
	assert_int(colonist.health_component.current_hp).is_equal(starting_hp - 30)

	colonist.heal(10)
	assert_int(colonist.get_hp()).is_equal(starting_hp - 20)


func test_colonist_death_emits_colonist_died_and_sets_is_dead() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var counter := Doubles.SignalCounter.new(EventBus.colonist_died)

	colonist.take_damage(100000, null)
	assert_bool(colonist.is_dead).is_true()
	assert_int(counter.count).is_equal(1)


func test_colonist_serialize_deserialize_round_trips_health() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.take_damage(15, null)

	var saved := colonist.serialize()

	var restored: Colonist = _sandbox.make_colonist()
	restored.deserialize(saved)

	assert_int(restored.health_component.current_hp).is_equal(colonist.get_max_hp() - 15)


func test_colonist_deserialize_legacy_save_format() -> void:
	var colonist: Colonist = _sandbox.make_colonist()

	# Pre-HealthComponent saves stored flat "hp"/"is_dead" keys instead of a
	# nested "health" dict.
	colonist.deserialize({"hp": 7, "is_dead": false})

	assert_int(colonist.health_component.current_hp).is_equal(7)
	assert_bool(colonist.is_dead).is_false()


func test_enemy_base_is_dead_reflects_health_component() -> void:
	var swarmer := SwarmerScene.instantiate() as EnemyBase
	auto_free(swarmer)
	swarmer._ready()

	assert_bool(swarmer.is_dead).is_false()
	swarmer.take_damage(10000)
	assert_bool(swarmer.is_dead).is_true()


class SpyPlayerAnimController extends PlayerAnimationController:
	var trigger_calls: Array[StringName] = []

	func trigger_action(action_name: StringName) -> void:
		trigger_calls.append(action_name)


func test_player_primary_action_only_triggers_animation_when_action_fires() -> void:
	var player: Player = PlayerScene.instantiate()
	auto_free(player)
	add_child(player)

	var spy := SpyPlayerAnimController.new()
	auto_free(spy)
	player.anim_controller = spy

	var action := MeleeActionParams.new()
	action.cooldown_seconds = 10.0
	action.windup_seconds = 0.0
	action.active_seconds = 0.0
	var item := ItemDef.new()
	item.id = "test_weapon"
	item.tags = ["weapon"]
	var equip := EquippableParams.new()
	equip.primary_action = action
	item.equippable = equip
	player.equipment.equip(Equipment.SLOT_MAIN_HAND, item)

	player._on_primary_action()
	assert_int(spy.trigger_calls.size()).is_equal(1)

	# Regression: spamming the input while still on cooldown must not
	# re-trigger (and thus restart) the swing animation.
	player._on_primary_action()
	assert_int(spy.trigger_calls.size()).is_equal(1)


func test_ranged_action_params_spawns_projectile_when_not_hitscan() -> void:
	var actor := Node3D.new()
	auto_free(actor)
	_sandbox.container.add_child(actor)
	actor.global_position = Vector3.ZERO

	var action := RangedActionParams.new()
	auto_free(action)
	action.is_hitscan = false
	action.damage = 40.0
	action.projectile_speed = 15.0
	action.range_meters = 50.0

	action.execute(actor)

	var found: Projectile = null
	for child in _sandbox.container.get_children():
		if child is Projectile:
			found = child as Projectile
	auto_free(found)

	assert_that(found).is_not_null()
	assert_int(found.damage).is_equal(40)
	assert_float(found.speed).is_equal(15.0)


## Regression: the melee hitbox's sweep-box orientation must track the
## resolved aim direction alone. It previously derived rotation from
## Transform3D.looking_at(center_pos + dir, ...), which folds the actor's
## absolute world position into the direction -- correct only near
## world-origin. Placing the actor far from origin reproduces the bug.
func test_melee_hitbox_tracks_aim_direction_away_from_world_origin() -> void:
	var actor := Node3D.new()
	auto_free(actor)
	add_child(actor)
	actor.global_position = Vector3(40.0, 0.0, 40.0)
	# Node3D fallback in _resolve_aim reads dir from -basis.z, matching look_at's convention.
	actor.look_at(actor.global_position + Vector3(1.0, 0.0, 0.0), Vector3.UP)

	var hit_dummy := _make_damage_dummy(Vector3(42.5, 1.0, 40.0)) # 2.5 m along the true +X aim
	var missed_dummy := _make_damage_dummy(Vector3(40.0, 1.0, 43.0)) # same distance, perpendicular

	for _i in range(3):
		await get_tree().physics_frame

	var action := MeleeActionParams.new()
	auto_free(action)
	action.windup_seconds = 0.0
	action.active_seconds = 0.0 # single hitbox evaluation, no timer wait
	action.range_meters = 3.0
	action.damage = 10.0

	await action.execute(actor)

	var hit_health := hit_dummy.get_node("HealthComponent") as HealthComponent
	var missed_health := missed_dummy.get_node("HealthComponent") as HealthComponent
	assert_int(hit_health.current_hp).is_equal(90)
	assert_int(missed_health.current_hp).is_equal(100)


## Auxiliary: A static body with a HealthComponent child, positioned to act as
## a melee hitbox target in the world-origin-distance regression test above.
func _make_damage_dummy(pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	auto_free(body)
	var shape_node := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.4
	shape_node.shape = shape
	body.add_child(shape_node)
	var health := HealthCompScript.new() as HealthComponent
	health.name = "HealthComponent"
	health.max_hp = 100
	body.add_child(health)
	add_child(body)
	body.global_position = pos
	return body


func test_enemy_ai_behavior_with_colonist() -> void:
	var colonist := CharacterBody3D.new()
	colonist.name = "TestColonist"
	auto_free(colonist)
	add_child(colonist)
	colonist.add_to_group("colonists")
	colonist.global_position = Vector3(5, 0, 0)

	var swarmer := SwarmerScene.instantiate() as EnemyBase
	auto_free(swarmer)
	add_child(swarmer)
	swarmer.global_position = Vector3.ZERO
	
	# Run frames for enemy (speed 5.0) to scan, acquire target, and traverse towards colonist
	for i in range(70):
		await await_idle_frame()
		swarmer._physics_process(0.016)

	assert_float(swarmer.global_position.x).is_greater(3.0)

