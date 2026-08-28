extends GdUnitTestSuite

## Unit tests for Combat subsystem (HealthComponent, EnemyBase, EnemySwarmer).

const Doubles = preload("res://test/helpers/doubles.gd")
const HealthCompScript = preload("res://subsystems/combat/components/health_component.gd")
const EnemyBaseScript = preload("res://subsystems/combat/enemy_base.gd")
const SwarmerScene = preload("res://subsystems/combat/enemies/enemy_swarmer/enemy_swarmer.tscn")


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
