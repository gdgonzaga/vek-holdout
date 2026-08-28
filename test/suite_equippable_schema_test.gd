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
	var item: ItemDef = load("res://data/items/assault_rifle.tres")
	assert_object(item).is_not_null()
	assert_str(item.id).is_equal("assault_rifle")
	assert_bool(item.is_equippable()).is_true()
	assert_object(item.equippable).is_not_null()
	assert_int(item.equippable.slot_type).is_equal(EquippableParams.SlotType.TWO_HAND)
	assert_str(item.equippable.animation_stance).is_equal("rifle")
	assert_object(item.equippable.primary_action).is_not_null()
	assert_bool(item.equippable.primary_action is CombatActionParams).is_true()

	var combat: CombatActionParams = item.equippable.primary_action as CombatActionParams
	assert_str(combat.id).is_equal("rifle_fire")
	assert_float(combat.damage).is_equal(15.0)
	assert_float(combat.cooldown_seconds).is_equal(0.15)
	assert_bool(combat.is_hitscan).is_true()
