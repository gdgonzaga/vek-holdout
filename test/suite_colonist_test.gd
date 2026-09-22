extends GdUnitTestSuite

## Colonist persistence (serialize/deserialize round trip of the state a Colonist owns).
## Extended in R13; starts with the one test that used to live in suite_ai_tasks_test.
## R13: extended test_stateless_colonist_save_load (rather than adding a parallel
## test) to also cover every other field Colonist.serialize() writes — display_name,
## labor_priorities, raid_stance, squad_id, health (via health_component), skills,
## and equipment (slot contents + the desired-slot ledger). HIGH-RISK (save/serialize,
## AGENTS.md): mutation-checked with two required mutants — see the R13 hand-back.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

## Synthetic head-slot item, registered into ItemDB only for this test (the
## suite_item_display_name_test.gd swap-and-restore pattern: restore only the
## one id this suite touches, never a blanket ItemDB reset).
const HELMET_ID := "test_r13_colonist_helmet"

var _sandbox: ColonySandbox
var _previous_helmet_def: Variant = null


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)
	_previous_helmet_def = ItemDB._defs_by_id.get(HELMET_ID, null)
	var helmet: ItemDef = auto_free(ItemDef.new()) as ItemDef
	helmet.id = HELMET_ID
	helmet.tags = ["equip_head"]
	ItemDB._defs_by_id[HELMET_ID] = helmet


func after_test() -> void:
	_sandbox.restore()
	if _previous_helmet_def != null:
		ItemDB._defs_by_id[HELMET_ID] = _previous_helmet_def
	else:
		ItemDB._defs_by_id.erase(HELMET_ID)


func test_stateless_colonist_save_load() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	colonist.global_position = Vector3(12.0, 3.5, -8.0)
	colonist.inventory.items["wood_plank"] = 7
	colonist.needs.set_need(&"hunger", 0.42)
	colonist.needs.set_need(&"rest", 0.88)

	# R13: every other field serialize() writes, set to a non-default value.
	colonist.display_name = "Test Colonist Alpha"
	colonist.labor_priorities["test_labor"] = 4
	colonist.set_raid_stance(2)
	colonist.squad_id = "test_squad_alpha"
	# setup() gives a known, non-shipped max_hp; take_damage's math (setup - 17)
	# is hand-derived, not the production formula (durability is 0 here, so no
	# overflow resolution runs).
	colonist.health_component.setup(50)
	colonist.health_component.take_damage(17, null)
	# Synthetic skill_id: deserialize() never validates against the skill catalog,
	# so this round-trips without depending on any shipped skill definition.
	colonist.skill_set.skills["test_skill"] = {"level": 4, "progress": 9}
	var helmet: ItemDef = ItemDB.get_def(HELMET_ID)
	colonist.equipment.equip(Equipment.SLOT_HEAD, helmet)
	colonist.equipment.set_desired_item(Equipment.SLOT_TORSO, "test_r13_desired_torso")

	var data: Dictionary = colonist.serialize()
	assert_bool(data.has("needs")).is_true()
	assert_bool(data.has("inventory")).is_true()
	assert_bool(data.has("pos")).is_true()
	assert_int(data["inventory"]["items"]["wood_plank"]).is_equal(7)

	# Deserialize into another colonist
	var loaded_colonist: Colonist = _sandbox.make_colonist()
	loaded_colonist.deserialize(data)

	assert_vector(loaded_colonist.global_position).is_equal(Vector3(12.0, 3.5, -8.0))
	assert_int(loaded_colonist.inventory.get_item_count("wood_plank")).is_equal(7)
	assert_float(loaded_colonist.needs.get_need(&"hunger")).is_equal_approx(0.42, 0.001)
	assert_float(loaded_colonist.needs.get_need(&"rest")).is_equal_approx(0.88, 0.001)

	assert_str(loaded_colonist.display_name).is_equal("Test Colonist Alpha")
	assert_int(int(loaded_colonist.labor_priorities.get("test_labor", 0))).is_equal(4)
	assert_int(loaded_colonist.raid_stance).is_equal(2)
	assert_str(loaded_colonist.squad_id).is_equal("test_squad_alpha")

	assert_int(loaded_colonist.health_component.max_hp).is_equal(50)
	assert_int(loaded_colonist.health_component.current_hp).is_equal(33)
	assert_bool(loaded_colonist.health_component.is_dead).is_false()

	assert_int(int(loaded_colonist.skill_set.skills["test_skill"]["level"])).is_equal(4)
	assert_int(int(loaded_colonist.skill_set.skills["test_skill"]["progress"])).is_equal(9)

	# Compare the equipped ItemDef by identity, never is_equal (AGENTS.md) —
	# ItemDB.get_def resolves the SAME registered Resource, not a copy.
	assert_object(loaded_colonist.equipment.get_item(Equipment.SLOT_HEAD)).is_same(helmet)
	assert_str(loaded_colonist.equipment.get_all_desired_items().get(Equipment.SLOT_TORSO, "")).is_equal("test_r13_desired_torso")
