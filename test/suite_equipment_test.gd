## gdUnit4 test suite for the Equipment component.
## Tests are content-agnostic: all ItemDefs are created in-memory.
## No .tres files are loaded; ItemDB is never queried.
extends GdUnitTestSuite

const Doubles = preload("res://test/helpers/doubles.gd")
var _previous_item_defs: Dictionary = {}

func after_test() -> void:
	if ItemDB != null:
		for id_val in _previous_item_defs:
			if _previous_item_defs[id_val] != null:
				ItemDB._defs_by_id[id_val] = _previous_item_defs[id_val]
			else:
				ItemDB._defs_by_id.erase(id_val)
	_previous_item_defs.clear()


func _make_item(id_val: String, item_tags: Array[String], item_weight: float = 1.0) -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = id_val
	def.tags = item_tags
	def.weight = item_weight
	if ItemDB != null:
		if not _previous_item_defs.has(id_val):
			_previous_item_defs[id_val] = ItemDB._defs_by_id.get(id_val, null)
		ItemDB._defs_by_id[id_val] = def
	return def


func _make_equipment() -> Equipment:
	return auto_free(Equipment.new())


# ==============================
# ensure_on
# ==============================

func test_ensure_on_creates_equipment_and_visualizer_for_a_bare_actor() -> void:
	var actor := auto_free(Node.new()) as Node

	var eq := Equipment.ensure_on(actor)

	assert_object(eq).is_not_null()
	assert_object(actor.get_node_or_null("Equipment")).is_same(eq)
	assert_object(actor.get_node_or_null("EquipmentVisualizer")).is_not_null()


## Calling ensure_on a second time with the actor's own already-resolved Equipment (the
## documented usage: "pass the actor's own field") must return that same component rather
## than creating a second one.
func test_ensure_on_is_idempotent_when_passed_the_previously_returned_equipment() -> void:
	var actor := auto_free(Node.new()) as Node
	var first := Equipment.ensure_on(actor)

	var second := Equipment.ensure_on(actor, first)

	assert_object(second).is_same(first)
	var equipment_children := 0
	for child: Node in actor.get_children():
		if child is Equipment:
			equipment_children += 1
	assert_int(equipment_children).is_equal(1)


# ==============================
# get_all_desired_items
# ==============================

## The caller must be able to inspect the returned snapshot without risking the component's
## own live _desired_slots dictionary.
func test_get_all_desired_items_returns_a_copy_not_the_live_dictionary() -> void:
	var eq := _make_equipment()
	eq.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_desired_axe")

	var snapshot := eq.get_all_desired_items()
	snapshot[Equipment.SLOT_MAIN_HAND] = "tampered"

	assert_str(eq.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal("test_desired_axe")


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
	# Main hand accepts "tool" and "weapon"; register one synthetic item that fits
	# and one that does not, instead of assuming shipped items with those tags exist.
	var fits: ItemDef = _make_item("test_eligible_fits", ["tool"])
	var excluded: ItemDef = _make_item("test_eligible_excluded", ["material"])

	var eligible: Array[ItemDef] = Equipment.get_eligible_items_for_slot(Equipment.SLOT_MAIN_HAND)

	assert_bool(eligible.has(fits)).is_true()
	assert_bool(eligible.has(excluded)).is_false()
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


func test_stow_and_equip_to_empty_main_hand() -> void:
	var eq: Equipment = _make_equipment()
	var pick: ItemDef = _make_item("pickaxe", ["tool"])
	var ok: bool = eq.stow_and_equip(Equipment.SLOT_MAIN_HAND, pick)
	assert_bool(ok).is_true()
	assert_str(eq.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("pickaxe")


func test_stow_and_equip_stows_to_empty_holster() -> void:
	var eq: Equipment = _make_equipment()
	var sword: ItemDef = _make_item("sword", ["weapon"])
	var pick: ItemDef = _make_item("pickaxe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, sword)

	var ok: bool = eq.stow_and_equip(Equipment.SLOT_MAIN_HAND, pick)
	assert_bool(ok).is_true()
	assert_str(eq.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("pickaxe")
	assert_str(eq.get_item(Equipment.SLOT_HOLSTER).id).is_equal("sword")


func test_stow_and_equip_stows_to_inventory_when_holster_occupied() -> void:
	var eq: Equipment = _make_equipment()
	var sword: ItemDef = _make_item("sword", ["weapon"])
	var pistol: ItemDef = _make_item("pistol", ["weapon"])
	var pick: ItemDef = _make_item("pickaxe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, sword)
	eq.equip(Equipment.SLOT_HOLSTER, pistol)

	var inv: Inventory = auto_free(Inventory.new())
	inv.capacity = 100.0
	var ok: bool = eq.stow_and_equip(Equipment.SLOT_MAIN_HAND, pick, inv)
	assert_bool(ok).is_true()
	assert_str(eq.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("pickaxe")
	assert_str(eq.get_item(Equipment.SLOT_HOLSTER).id).is_equal("pistol")
	assert_int(inv.get_item_count("sword")).is_equal(1)


func test_stow_and_equip_fails_when_inventory_full_and_holster_occupied() -> void:
	var eq: Equipment = _make_equipment()
	var sword: ItemDef = _make_item("sword", ["weapon"])
	var pistol: ItemDef = _make_item("pistol", ["weapon"])
	var pick: ItemDef = _make_item("pickaxe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, sword)
	eq.equip(Equipment.SLOT_HOLSTER, pistol)

	var inv: Inventory = auto_free(Inventory.new())
	inv.capacity = 0.5  # Too small to accept sword (weight 1.0)
	var ok: bool = eq.stow_and_equip(Equipment.SLOT_MAIN_HAND, pick, inv)
	assert_bool(ok).is_false()
	assert_str(eq.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("sword")
	assert_str(eq.get_item(Equipment.SLOT_HOLSTER).id).is_equal("pistol")


func test_bt_action_equip_tool_stows_main_hand_to_inventory() -> void:
	var colonist: CharacterBody3D = auto_free(CharacterBody3D.new())
	add_child(colonist)
	var eq: Equipment = _make_equipment()
	eq.name = "Equipment"
	colonist.add_child(eq)
	var inv: Inventory = auto_free(Inventory.new())
	inv.name = "Inventory"
	inv.capacity = 100.0
	colonist.add_child(inv)

	var sword: ItemDef = _make_item("sword", ["weapon"])
	var pistol: ItemDef = _make_item("pistol", ["weapon"])
	var pick: ItemDef = _make_item("pickaxe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, sword)
	eq.equip(Equipment.SLOT_HOLSTER, pistol)
	inv.add("pickaxe", 1)

	var bb: Blackboard = auto_free(Blackboard.new())
	bb.set_var(&"required_equipped_tags", [&"tool"])

	var action: BTAction = auto_free(BTActionEquipTool.new()) as BTAction
	action.initialize(colonist, bb, colonist)
	var status: int = action.execute(0.1)

	assert_int(status).is_equal(BTAction.SUCCESS)
	assert_str(eq.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("pickaxe")
	assert_str(eq.get_item(Equipment.SLOT_HOLSTER).id).is_equal("pistol")
	assert_int(inv.get_item_count("sword")).is_equal(1)
	assert_int(inv.get_item_count("pickaxe")).is_equal(0)


# ==============================
# equip_from_inventory / unequip_to_inventory (player equip moves items)
# ==============================

## Inventory holding `count` of each given item, roomy unless `capacity` is passed.
func _make_carry(stacks: Dictionary, capacity: float = 100.0) -> Inventory:
	var inv: Inventory = auto_free(Inventory.new())
	inv.capacity = capacity
	for item_id: String in stacks:
		inv.add(item_id, stacks[item_id])
	return inv


func test_equip_from_inventory_moves_item_into_main_hand() -> void:
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool"])
	var inv: Inventory = _make_carry({"axe": 1})

	var result: Equipment.EquipResult = eq.equip_from_inventory(axe, inv)

	assert_int(result).is_equal(Equipment.EquipResult.OK)
	assert_str(eq.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("axe")
	assert_int(inv.get_item_count("axe")).is_equal(0)


func test_equip_from_inventory_takes_exactly_one_of_a_stack() -> void:
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool"])
	var inv: Inventory = _make_carry({"axe": 3})

	eq.equip_from_inventory(axe, inv)

	assert_int(inv.get_item_count("axe")).is_equal(2)


func test_equip_from_inventory_stows_held_item_in_free_holster() -> void:
	var eq: Equipment = _make_equipment()
	var sword: ItemDef = _make_item("sword", ["weapon"])
	var pick: ItemDef = _make_item("pickaxe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, sword)
	var inv: Inventory = _make_carry({"pickaxe": 1})

	var result: Equipment.EquipResult = eq.equip_from_inventory(pick, inv)

	assert_int(result).is_equal(Equipment.EquipResult.OK)
	assert_str(eq.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("pickaxe")
	assert_str(eq.get_item(Equipment.SLOT_HOLSTER).id).is_equal("sword")
	assert_int(inv.get_item_count("sword")).is_equal(0)


func test_equip_from_inventory_returns_held_item_to_inventory_when_holster_taken() -> void:
	# Break caught: equip() alone overwrites the slot, so the held item would simply vanish.
	var eq: Equipment = _make_equipment()
	var sword: ItemDef = _make_item("sword", ["weapon"])
	var pistol: ItemDef = _make_item("pistol", ["weapon"])
	var pick: ItemDef = _make_item("pickaxe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, sword)
	eq.equip(Equipment.SLOT_HOLSTER, pistol)
	var inv: Inventory = _make_carry({"pickaxe": 1})

	var result: Equipment.EquipResult = eq.equip_from_inventory(pick, inv)

	assert_int(result).is_equal(Equipment.EquipResult.OK)
	assert_str(eq.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("pickaxe")
	assert_str(eq.get_item(Equipment.SLOT_HOLSTER).id).is_equal("pistol")
	assert_int(inv.get_item_count("sword")).is_equal(1)


func test_equip_from_inventory_routes_wearable_to_its_slot() -> void:
	var eq: Equipment = _make_equipment()
	var cap: ItemDef = _make_item("cap", ["equip_head"])
	var inv: Inventory = _make_carry({"cap": 1})

	var result: Equipment.EquipResult = eq.equip_from_inventory(cap, inv)

	assert_int(result).is_equal(Equipment.EquipResult.OK)
	assert_str(eq.get_item(Equipment.SLOT_HEAD).id).is_equal("cap")
	assert_bool(eq.is_empty(Equipment.SLOT_MAIN_HAND)).is_true()


func test_equip_from_inventory_swaps_out_worn_apparel() -> void:
	var eq: Equipment = _make_equipment()
	var old_cap: ItemDef = _make_item("old_cap", ["equip_head"])
	var new_cap: ItemDef = _make_item("new_cap", ["equip_head"])
	eq.equip(Equipment.SLOT_HEAD, old_cap)
	var inv: Inventory = _make_carry({"new_cap": 1})

	var result: Equipment.EquipResult = eq.equip_from_inventory(new_cap, inv)

	assert_int(result).is_equal(Equipment.EquipResult.OK)
	assert_str(eq.get_item(Equipment.SLOT_HEAD).id).is_equal("new_cap")
	assert_int(inv.get_item_count("old_cap")).is_equal(1)


func test_equip_from_inventory_reports_not_carried_and_changes_nothing() -> void:
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool"])
	var inv: Inventory = _make_carry({})

	var result: Equipment.EquipResult = eq.equip_from_inventory(axe, inv)

	assert_int(result).is_equal(Equipment.EquipResult.NOT_CARRIED)
	assert_bool(eq.is_empty(Equipment.SLOT_MAIN_HAND)).is_true()


func test_equip_from_inventory_reports_no_slot_and_keeps_the_item() -> void:
	var eq: Equipment = _make_equipment()
	var rock: ItemDef = _make_item("rock", ["material"])
	var inv: Inventory = _make_carry({"rock": 2})

	var result: Equipment.EquipResult = eq.equip_from_inventory(rock, inv)

	assert_int(result).is_equal(Equipment.EquipResult.NO_SLOT)
	assert_int(inv.get_item_count("rock")).is_equal(2)


func test_equip_from_inventory_refuses_an_item_already_held_in_that_slot() -> void:
	# Break caught: stow_and_equip treats "same id" as success, which would delete the spare copy.
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, axe)
	var inv: Inventory = _make_carry({"axe": 1})

	var result: Equipment.EquipResult = eq.equip_from_inventory(axe, inv)

	assert_int(result).is_equal(Equipment.EquipResult.ALREADY_HELD)
	assert_int(inv.get_item_count("axe")).is_equal(1)


func test_equip_from_inventory_no_room_for_displaced_item_changes_nothing() -> void:
	var eq: Equipment = _make_equipment()
	var heavy: ItemDef = _make_item("heavy_sword", ["weapon"], 6.0)
	var pistol: ItemDef = _make_item("pistol", ["weapon"])
	var pick: ItemDef = _make_item("pickaxe", ["tool"], 5.0)
	eq.equip(Equipment.SLOT_MAIN_HAND, heavy)
	eq.equip(Equipment.SLOT_HOLSTER, pistol)
	var inv: Inventory = _make_carry({"pickaxe": 1}, 5.0)  # once pickaxe leaves, only 5 kg free

	var result: Equipment.EquipResult = eq.equip_from_inventory(pick, inv)

	assert_int(result).is_equal(Equipment.EquipResult.NO_ROOM)
	assert_int(inv.get_item_count("pickaxe")).is_equal(1)
	assert_str(eq.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("heavy_sword")
	assert_str(eq.get_item(Equipment.SLOT_HOLSTER).id).is_equal("pistol")


func test_equip_from_inventory_counts_the_freed_weight_of_the_new_item() -> void:
	# Break caught: stowing the held item BEFORE removing the new one fails on a full inventory.
	var eq: Equipment = _make_equipment()
	var sword: ItemDef = _make_item("sword", ["weapon"], 5.0)
	var pistol: ItemDef = _make_item("pistol", ["weapon"])
	var pick: ItemDef = _make_item("pickaxe", ["tool"], 5.0)
	eq.equip(Equipment.SLOT_MAIN_HAND, sword)
	eq.equip(Equipment.SLOT_HOLSTER, pistol)
	var inv: Inventory = _make_carry({"pickaxe": 1}, 5.0)  # completely full

	var result: Equipment.EquipResult = eq.equip_from_inventory(pick, inv)

	assert_int(result).is_equal(Equipment.EquipResult.OK)
	assert_int(inv.get_item_count("sword")).is_equal(1)
	assert_int(inv.get_item_count("pickaxe")).is_equal(0)


func test_equip_from_inventory_emits_slot_changed_for_the_target_slot() -> void:
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool"])
	var inv: Inventory = _make_carry({"axe": 1})
	var counter := Doubles.SignalCounter.new(eq.slot_changed)

	eq.equip_from_inventory(axe, inv)

	assert_int(counter.read()).is_equal(1)


func test_unequip_to_inventory_returns_the_item() -> void:
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, axe)
	var inv: Inventory = _make_carry({})

	var ok: bool = eq.unequip_to_inventory(Equipment.SLOT_MAIN_HAND, inv)

	assert_bool(ok).is_true()
	assert_bool(eq.is_empty(Equipment.SLOT_MAIN_HAND)).is_true()
	assert_int(inv.get_item_count("axe")).is_equal(1)


func test_unequip_to_inventory_refused_when_full_keeps_item_equipped() -> void:
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool"], 3.0)
	eq.equip(Equipment.SLOT_MAIN_HAND, axe)
	var inv: Inventory = _make_carry({}, 1.0)

	var ok: bool = eq.unequip_to_inventory(Equipment.SLOT_MAIN_HAND, inv)

	assert_bool(ok).is_false()
	assert_str(eq.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("axe")


func test_unequip_to_inventory_on_empty_slot_is_false() -> void:
	var eq: Equipment = _make_equipment()
	var inv: Inventory = _make_carry({})
	assert_bool(eq.unequip_to_inventory(Equipment.SLOT_MAIN_HAND, inv)).is_false()


# ==============================
# count_equipped_item / count_equipped_tag
# ==============================

func test_count_equipped_item_counts_slots_holding_the_id() -> void:
	var eq: Equipment = _make_equipment()
	var axe: ItemDef = _make_item("axe", ["tool"])
	eq.equip(Equipment.SLOT_MAIN_HAND, axe)
	eq.equip(Equipment.SLOT_HOLSTER, axe)
	assert_int(eq.count_equipped_item("axe")).is_equal(2)
	assert_int(eq.count_equipped_item("saw")).is_equal(0)


func test_count_equipped_tag_counts_slots_whose_item_has_the_tag() -> void:
	var eq: Equipment = _make_equipment()
	eq.equip(Equipment.SLOT_MAIN_HAND, _make_item("hoe", ["tool", "gardening_tool"]))
	eq.equip(Equipment.SLOT_HOLSTER, _make_item("saw", ["tool"]))
	assert_int(eq.count_equipped_tag("tool")).is_equal(2)
	assert_int(eq.count_equipped_tag("gardening_tool")).is_equal(1)
	assert_int(eq.count_equipped_tag("weapon")).is_equal(0)


# ==============================
# is_gear
# ==============================

func test_is_gear_true_for_tools_weapons_apparel_and_shields() -> void:
	for tag: String in ["tool", "weapon", "equip_head", "equip_torso", "shield"]:
		assert_bool(Equipment.is_gear(_make_item("gear_probe", [tag]))).is_true()


func test_is_gear_false_for_items_no_slot_accepts() -> void:
	assert_bool(Equipment.is_gear(_make_item("plain_probe", ["material", "wood"]))).is_false()
	assert_bool(Equipment.is_gear(_make_item("untagged_probe", []))).is_false()


func test_is_gear_false_for_null() -> void:
	assert_bool(Equipment.is_gear(null)).is_false()
