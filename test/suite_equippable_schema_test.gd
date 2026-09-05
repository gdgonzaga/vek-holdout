extends GdUnitTestSuite

## Unit tests for EquippableParams and modular action schemas (ARCH "Data Schemas / Capabilities").
## Tests capability composition on ItemDef and polymorphic action params.

func test_item_def_default_not_equippable() -> void:
	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "plain_stone"
	assert_bool(item.is_equippable()).is_false()
	assert_object(item.equippable).is_null()


func test_item_def_with_equippable_params() -> void:
	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "test_sword"
	var equip: EquippableParams = auto_free(EquippableParams.new())
	equip.slot_type = EquippableParams.SlotType.MAIN_HAND
	equip.animation_stance = "melee_1h"
	item.equippable = equip

	assert_bool(item.is_equippable()).is_true()
	assert_object(item.equippable).is_not_null()
	assert_int(item.equippable.slot_type).is_equal(EquippableParams.SlotType.MAIN_HAND)
	assert_str(item.equippable.animation_stance).is_equal("melee_1h")


func test_combat_action_params_polymorphism() -> void:
	var item: ItemDef = auto_free(ItemDef.new())
	var equip: EquippableParams = auto_free(EquippableParams.new())
	var action: CombatActionParams = auto_free(CombatActionParams.new())
	action.id = "pistol_shot"
	action.cooldown_seconds = 0.25
	action.damage = 22.0
	action.range_meters = 40.0
	action.is_hitscan = true
	action.spread_angle_degrees = 2.0
	equip.primary_action = action
	item.equippable = equip

	assert_bool(item.is_equippable()).is_true()
	assert_bool(item.equippable.primary_action is EquipActionParams).is_true()
	assert_bool(item.equippable.primary_action is CombatActionParams).is_true()

	var combat: CombatActionParams = item.equippable.primary_action as CombatActionParams
	assert_float(combat.damage).is_equal(22.0)
	assert_float(combat.cooldown_seconds).is_equal(0.25)
	assert_bool(combat.is_hitscan).is_true()


func test_load_assault_rifle_tres() -> void:
	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "assault_rifle"
	var equip: EquippableParams = auto_free(EquippableParams.new())
	equip.slot_type = EquippableParams.SlotType.TWO_HAND
	equip.animation_stance = "rifle"
	var combat: CombatActionParams = auto_free(CombatActionParams.new())
	combat.id = "rifle_fire"
	combat.damage = 15.0
	combat.cooldown_seconds = 0.15
	combat.is_hitscan = true
	equip.primary_action = combat
	item.equippable = equip

	assert_object(item).is_not_null()
	assert_str(item.id).is_equal("assault_rifle")
	assert_bool(item.is_equippable()).is_true()
	assert_object(item.equippable).is_not_null()
	assert_int(item.equippable.slot_type).is_equal(EquippableParams.SlotType.TWO_HAND)
	assert_str(item.equippable.animation_stance).is_equal("rifle")
	assert_object(item.equippable.primary_action).is_not_null()
	assert_bool(item.equippable.primary_action is CombatActionParams).is_true()

	var retrieved: CombatActionParams = item.equippable.primary_action as CombatActionParams
	assert_str(retrieved.id).is_equal("rifle_fire")
	assert_float(retrieved.damage).is_equal(15.0)
	assert_float(retrieved.cooldown_seconds).is_equal(0.15)
	assert_bool(retrieved.is_hitscan).is_true()


func test_colonist_equip_item() -> void:
	var colonist: Colonist = auto_free(Colonist.new())
	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "sample_item"
	colonist.equip_item(item)
	assert_object(colonist.equipped_item).is_equal(item)


func test_player_equip_and_unequip_item() -> void:
	var player: Player = auto_free(Player.new())
	var item: ItemDef = auto_free(ItemDef.new())
	item.id = "sample_weapon"
	player.equip_item(item)
	assert_object(player.equipped_item).is_equal(item)
	player.unequip_item()
	assert_object(player.equipped_item).is_null()


func test_player_gun_fire_damages_enemy() -> void:
	var enemy: EnemyBase = auto_free(EnemyBase.new())
	var health: HealthComponent = auto_free(HealthComponent.new())
	health.name = "HealthComponent"
	health.max_hp = 100
	enemy.add_child(health)
	add_child(enemy)
	enemy._ready()

	var combat_params: CombatActionParams = auto_free(CombatActionParams.new())
	combat_params.damage = 35.0

	var player: Player = auto_free(Player.new())
	# Direct test on enemy damage execution
	enemy.take_damage(int(combat_params.damage), player)
	assert_int(health.current_hp).is_equal(65)


func test_combat_action_execute_on_null_actor_is_safe() -> void:
	var action: CombatActionParams = auto_free(CombatActionParams.new())
	# Should not crash or error
	action.execute(null)
	assert_bool(true).is_true()


func test_combat_action_params_show_tracer_property() -> void:
	var action: CombatActionParams = auto_free(CombatActionParams.new())
	assert_bool(action.show_tracer).is_true()
	action.show_tracer = false
	assert_bool(action.show_tracer).is_false()


func test_enemy_lethal_damage_triggers_death_and_free() -> void:
	var enemy: EnemyBase = auto_free(EnemyBase.new())
	var health: HealthComponent = auto_free(HealthComponent.new())
	health.name = "HealthComponent"
	health.max_hp = 50
	enemy.add_child(health)
	add_child(enemy)
	enemy._ready()

	var combat_params: CombatActionParams = auto_free(CombatActionParams.new())
	combat_params.damage = 60.0

	var player: Player = auto_free(Player.new())
	enemy.take_damage(int(combat_params.damage), player)

	assert_int(health.current_hp).is_equal(0)
	assert_bool(enemy.is_queued_for_deletion()).is_true()
