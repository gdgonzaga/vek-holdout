## gdUnit4 test suite for the Equipment component.
## Tests are content-agnostic: all ItemDefs are created in-memory.
## No .tres files are loaded; ItemDB is never queried.
extends GdUnitTestSuite

const Doubles = preload("res://test/helpers/doubles.gd")
# ==============================
# Helpers
# ==============================

func _make_item(id_val: String, item_tags: Array[String]) -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = id_val
	def.tags = item_tags
	return def


func _make_equipment() -> Equipment:
	return auto_free(Equipment.new())


# ==============================
# can_equip_to
# ==============================

func test_can_equip_to_main_hand_with_tool_tag() -> void:
	var eq: Equipment = _make_equipment()
	var item: ItemDef = _make_item("axe", ["tool", "axe"])
	assert_bool(eq.can_equip_to(Equipment.SLOT_MAIN_HAND, item)).is_true()


func test_can_equip_to_main_hand_with_weapon_tag() -> void:
	var eq: Equipment = _make_equipment()
	var item: ItemDef = _make_item("sword", ["weapon", "melee"])
	assert_bool(eq.can_equip_to(Equipment.SLOT_MAIN_HAND, item)).is_true()


func test_can_equip_to_holster_with_tool_tag() -> void:
	var eq: Equipment = _make_equipment()
	var item: ItemDef = _make_item("pickaxe", ["tool"])
	assert_bool(eq.can_equip_to(Equipment.SLOT_HOLSTER, item)).is_true()


func test_can_equip_to_rejects_wrong_tag() -> void:
	var eq: Equipment = _make_equipment()
	var item: ItemDef = _make_item("rock", ["material"])
	assert_bool(eq.can_equip_to(Equipment.SLOT_MAIN_HAND, item)).is_false()


func test_can_equip_to_rejects_null_item() -> void:
	var eq: Equipment = _make_equipment()
	assert_bool(eq.can_equip_to(Equipment.SLOT_MAIN_HAND, null)).is_false()


func test_can_equip_to_rejects_unknown_slot() -> void:
	var eq: Equipment = _make_equipment()
	var item: ItemDef = _make_item("axe", ["tool"])
	assert_bool(eq.can_equip_to("banana", item)).is_false()


func test_can_equip_head_slot_requires_equip_head_tag() -> void:
	var eq: Equipment = _make_equipment()
	var helm: ItemDef = _make_item("helm", ["equip_head"])
	var axe: ItemDef = _make_item("axe", ["tool"])
	assert_bool(eq.can_equip_to(Equipment.SLOT_HEAD, helm)).is_true()
	assert_bool(eq.can_equip_to(Equipment.SLOT_HEAD, axe)).is_false()


# ==============================
# equip / unequip / get_item / is_empty
# ==============================

func test_equip_places_item_in_slot() -> void:
	var eq: Equipment = _make_equipment()
	var item: ItemDef = _make_item("axe", ["tool"])
	assert_bool(eq.equip(Equipment.SLOT_MAIN_HAND, item)).is_true()
	assert_object(eq.get_item(Equipment.SLOT_MAIN_HAND)).is_equal(item)


func test_equip_returns_false_for_invalid_tag() -> void:
	var eq: Equipment = _make_equipment()
	var item: ItemDef = _make_item("dirt", ["material"])
	assert_bool(eq.equip(Equipment.SLOT_MAIN_HAND, item)).is_false()
	assert_bool(eq.is_empty(Equipment.SLOT_MAIN_HAND)).is_true()


func test_unequip_returns_item_and_clears_slot() -> void:
	var eq: Equipment = _make_equipment()
	var item: ItemDef = _make_item("axe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, item)
	var removed: ItemDef = eq.unequip(Equipment.SLOT_MAIN_HAND)
	assert_object(removed).is_equal(item)
	assert_bool(eq.is_empty(Equipment.SLOT_MAIN_HAND)).is_true()


func test_unequip_empty_slot_returns_null() -> void:
	var eq: Equipment = _make_equipment()
	assert_object(eq.unequip(Equipment.SLOT_MAIN_HAND)).is_null()


func test_is_empty_true_initially() -> void:
	var eq: Equipment = _make_equipment()
	for slot_id: String in Equipment.SLOT_ACCEPTED_TAGS:
		assert_bool(eq.is_empty(slot_id)).is_true()


func test_equip_emits_slot_changed_signal() -> void:
	var eq: Equipment = _make_equipment()
	var item: ItemDef = _make_item("axe", ["tool"])
	var counter := Doubles.SignalCounter.new(eq.slot_changed)
	eq.equip(Equipment.SLOT_MAIN_HAND, item)
	assert_int(counter.read()).is_equal(1)


func test_unequip_emits_slot_changed_signal() -> void:
	var eq: Equipment = _make_equipment()
	var item: ItemDef = _make_item("axe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, item)
	var counter := Doubles.SignalCounter.new(eq.slot_changed)
	eq.unequip(Equipment.SLOT_MAIN_HAND)
	assert_int(counter.read()).is_equal(1)


# ==============================
# get_slot_for_item
# ==============================

func test_get_slot_for_item_prefers_main_hand() -> void:
	var eq: Equipment = _make_equipment()
	var item: ItemDef = _make_item("axe", ["tool"])
	assert_str(eq.get_slot_for_item(item)).is_equal(Equipment.SLOT_MAIN_HAND)


func test_get_slot_for_item_falls_back_to_holster_when_main_hand_full() -> void:
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool"])
	var pick: ItemDef = _make_item("pickaxe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, axe)
	assert_str(eq.get_slot_for_item(pick)).is_equal(Equipment.SLOT_HOLSTER)


func test_get_slot_for_item_returns_empty_when_no_slot_available() -> void:
	var eq: Equipment = _make_equipment()
	var item: ItemDef = _make_item("dirt", ["material"])
	assert_str(eq.get_slot_for_item(item)).is_equal("")


# ==============================
# has_item_with_tag
# ==============================

func test_has_item_with_tag_true_when_equipped() -> void:
	var eq: Equipment = _make_equipment()
	var item: ItemDef = _make_item("axe", ["tool", "axe"])
	eq.equip(Equipment.SLOT_MAIN_HAND, item)
	assert_bool(eq.has_item_with_tag("axe")).is_true()


func test_has_item_with_tag_false_when_not_equipped() -> void:
	var eq: Equipment = _make_equipment()
	assert_bool(eq.has_item_with_tag("axe")).is_false()


# ==============================
# swap_hand_for_tag
# ==============================

func test_swap_hand_for_tag_succeeds_when_already_in_main_hand() -> void:
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool", "axe"])
	eq.equip(Equipment.SLOT_MAIN_HAND, axe)
	assert_bool(eq.swap_hand_for_tag(&"axe")).is_true()
	# Main hand unchanged.
	assert_object(eq.get_item(Equipment.SLOT_MAIN_HAND)).is_equal(axe)


func test_swap_hand_for_tag_swaps_from_holster() -> void:
	var eq: Equipment = _make_equipment()
	var club: ItemDef = _make_item("club", ["weapon"])
	var pick: ItemDef = _make_item("pickaxe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, club)
	eq.equip(Equipment.SLOT_HOLSTER, pick)

	# Need a pickaxe (tool) — it's in the holster.
	assert_bool(eq.swap_hand_for_tag(&"tool")).is_true()
	assert_object(eq.get_item(Equipment.SLOT_MAIN_HAND)).is_equal(pick)
	assert_object(eq.get_item(Equipment.SLOT_HOLSTER)).is_equal(club)


func test_swap_hand_for_tag_returns_false_when_tag_absent() -> void:
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, axe)
	# No shield anywhere.
	assert_bool(eq.swap_hand_for_tag(&"shield")).is_false()


func test_swap_hand_for_tag_emits_slot_changed_for_both_slots() -> void:
	var eq: Equipment = _make_equipment()
	var club: ItemDef = _make_item("club", ["weapon"])
	var pick: ItemDef = _make_item("pickaxe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, club)
	eq.equip(Equipment.SLOT_HOLSTER, pick)
	var counter := Doubles.SignalCounter.new(eq.slot_changed)
	eq.swap_hand_for_tag(&"tool")
	assert_int(counter.read()).is_equal(2)


# ==============================
# swap_hand_to_holster
# ==============================

func test_swap_hand_to_holster_exchanges_contents() -> void:
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool"])
	var club: ItemDef = _make_item("club", ["weapon"])
	eq.equip(Equipment.SLOT_MAIN_HAND, axe)
	eq.equip(Equipment.SLOT_HOLSTER, club)
	eq.swap_hand_to_holster()
	assert_object(eq.get_item(Equipment.SLOT_MAIN_HAND)).is_equal(club)
	assert_object(eq.get_item(Equipment.SLOT_HOLSTER)).is_equal(axe)


func test_swap_hand_to_holster_safe_when_holster_empty() -> void:
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, axe)
	eq.swap_hand_to_holster()
	assert_bool(eq.is_empty(Equipment.SLOT_MAIN_HAND)).is_true()
	assert_object(eq.get_item(Equipment.SLOT_HOLSTER)).is_equal(axe)


func test_swap_hand_to_holster_safe_when_both_empty() -> void:
	var eq: Equipment = _make_equipment()
	eq.swap_hand_to_holster()
	assert_bool(eq.is_empty(Equipment.SLOT_MAIN_HAND)).is_true()
	assert_bool(eq.is_empty(Equipment.SLOT_HOLSTER)).is_true()


# ==============================
# serialize / deserialize
# ==============================

func test_serialize_produces_correct_keys() -> void:
	var eq: Equipment = _make_equipment()
	var data: Dictionary = eq.serialize()
	for slot_id: String in Equipment.SLOT_ACCEPTED_TAGS:
		assert_bool(data.has(slot_id)).is_true()


func test_serialize_stores_item_id_for_equipped_slot() -> void:
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, axe)
	var data: Dictionary = eq.serialize()
	assert_str(data[Equipment.SLOT_MAIN_HAND]).is_equal("axe")


func test_serialize_stores_empty_string_for_empty_slot() -> void:
	var eq: Equipment = _make_equipment()
	var data: Dictionary = eq.serialize()
	assert_str(data[Equipment.SLOT_MAIN_HAND]).is_equal("")


# ==============================
# BTActionEquipTool
# ==============================

func test_bt_action_equip_tool_vacuous_success_when_no_tag() -> void:
	var action: BTAction = auto_free(BTActionEquipTool.new()) as BTAction
	var node: Node = auto_free(Node.new())
	var bb := Blackboard.new()
	action.initialize(node, bb, node)
	assert_int(action.execute(0.1)).is_equal(BTAction.SUCCESS)


func test_bt_action_equip_tool_swaps_from_holster() -> void:
	var action: BTAction = auto_free(BTActionEquipTool.new()) as BTAction
	var actor: Node = auto_free(Node.new())
	var eq := Equipment.new()
	eq.name = "Equipment"
	actor.add_child(eq)

	var club: ItemDef = _make_item("club", ["weapon"])
	var pick: ItemDef = _make_item("pickaxe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, club)
	eq.equip(Equipment.SLOT_HOLSTER, pick)

	var bb := Blackboard.new()
	bb.set_var(&"required_tool_tag", "tool")
	action.initialize(actor, bb, actor)

	var status: int = action.execute(0.1)
	assert_int(status).is_equal(BTAction.SUCCESS)
	assert_object(eq.get_item(Equipment.SLOT_MAIN_HAND)).is_equal(pick)
	assert_object(eq.get_item(Equipment.SLOT_HOLSTER)).is_equal(club)


func test_bt_action_equip_tool_fails_when_item_not_found() -> void:
	var action: BTAction = auto_free(BTActionEquipTool.new()) as BTAction
	var actor: Node = auto_free(Node.new())
	var eq := Equipment.new()
	eq.name = "Equipment"
	actor.add_child(eq)

	var bb := Blackboard.new()
	bb.set_var(&"required_tool_tag", "pickaxe")
	action.initialize(actor, bb, actor)

	var status: int = action.execute(0.1)
	assert_int(status).is_equal(BTAction.FAILURE)


# ==============================
# Desired Slots API
# ==============================

func test_desired_slots_initialize_empty() -> void:
	var eq: Equipment = _make_equipment()
	for slot_id: String in Equipment.SLOT_ACCEPTED_TAGS:
		assert_str(eq.get_desired_item(slot_id)).is_equal("")


func test_set_and_get_desired_item() -> void:
	var eq: Equipment = _make_equipment()
	eq.set_desired_item(Equipment.SLOT_MAIN_HAND, "iron_axe")
	assert_str(eq.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal("iron_axe")
	# Other slots remain untouched
	assert_str(eq.get_desired_item(Equipment.SLOT_HOLSTER)).is_equal("")


func test_clear_desired_item() -> void:
	var eq: Equipment = _make_equipment()
	eq.set_desired_item(Equipment.SLOT_HEAD, "iron_helmet")
	eq.clear_desired_item(Equipment.SLOT_HEAD)
	assert_str(eq.get_desired_item(Equipment.SLOT_HEAD)).is_equal("")


func test_desired_slot_changed_signal() -> void:
	var eq: Equipment = _make_equipment()
	var counter := Doubles.SignalCounter.new(eq.desired_slot_changed)
	eq.set_desired_item(Equipment.SLOT_MAIN_HAND, "pickaxe")
	assert_int(counter.read()).is_equal(1)


func test_is_desired_equipped_status() -> void:
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool"])
	var club: ItemDef = _make_item("club", ["weapon"])

	# No desired set, slot empty -> true
	assert_bool(eq.is_desired_equipped(Equipment.SLOT_MAIN_HAND)).is_true()

	# Desired set to "axe", slot empty -> false
	eq.set_desired_item(Equipment.SLOT_MAIN_HAND, "axe")
	assert_bool(eq.is_desired_equipped(Equipment.SLOT_MAIN_HAND)).is_false()

	# Slot has club, desired is axe -> false
	eq.equip(Equipment.SLOT_MAIN_HAND, club)
	assert_bool(eq.is_desired_equipped(Equipment.SLOT_MAIN_HAND)).is_false()

	# Slot has axe, desired is axe -> true
	eq.equip(Equipment.SLOT_MAIN_HAND, axe)
	assert_bool(eq.is_desired_equipped(Equipment.SLOT_MAIN_HAND)).is_true()


func test_get_eligible_items_for_slot() -> void:
	# Main hand accepts "tool" and "weapon"
	var eligible: Array[ItemDef] = Equipment.get_eligible_items_for_slot(Equipment.SLOT_MAIN_HAND)
	assert_object(eligible).is_not_null()
	# Every returned item must carry at least tool or weapon
	for def: ItemDef in eligible:
		assert_bool(def.has_tag("tool") or def.has_tag("weapon")).is_true()


func test_serialize_and_deserialize_desired_slots() -> void:
	var eq1: Equipment = _make_equipment()
	eq1.set_desired_item(Equipment.SLOT_MAIN_HAND, "axe")
	eq1.set_desired_item(Equipment.SLOT_HEAD, "helmet")
	var data: Dictionary = eq1.serialize()

	var eq2: Equipment = _make_equipment()
	eq2.deserialize(data)
	assert_str(eq2.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal("axe")
	assert_str(eq2.get_desired_item(Equipment.SLOT_HEAD)).is_equal("helmet")
	assert_str(eq2.get_desired_item(Equipment.SLOT_TORSO)).is_equal("")
