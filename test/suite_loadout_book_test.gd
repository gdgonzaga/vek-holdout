extends GdUnitTestSuite
## Tests for LoadoutBook (named {slot_id: item_id} templates) and for how Colony saves it.
## Content-agnostic: item defs are built in memory and handed to the book through a resolver,
## so ItemDB and res://data/ are never consulted.

const Doubles = preload("res://test/helpers/doubles.gd")

# Swap-and-restore (AGENTS.md): Colony is an autoload shared by every suite.
var _real_loadouts: LoadoutBook
var _real_registry: StorageRegistry


func before_test() -> void:
	_real_loadouts = Colony.loadouts
	_real_registry = Colony.storage_registry
	Colony.loadouts = LoadoutBook.new()
	Colony.storage_registry = auto_free(StorageRegistry.new())
	Colony.colonists.clear()


func after_test() -> void:
	Colony.loadouts = _real_loadouts
	Colony.storage_registry = _real_registry
	Colony.colonists.clear()


func _make_item(id_val: String, item_tags: Array[String]) -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = id_val
	def.tags = item_tags
	return def


func _make_equipment() -> Equipment:
	return auto_free(Equipment.new())


func _resolver(items: Array[ItemDef]) -> Callable:
	var by_id: Dictionary = {}
	for item: ItemDef in items:
		by_id[item.id] = item
	return func(item_id: String) -> ItemDef: return by_id.get(item_id) as ItemDef


func _no_items() -> Array[ItemDef]:
	var none: Array[ItemDef] = []
	return none


# ==============================
# create / rename / delete
# ==============================

func test_create_returns_an_id_for_a_named_loadout() -> void:
	var book := LoadoutBook.new()

	var id: String = book.create("Miner")

	assert_str(id).is_not_empty()
	assert_bool(book.has(id)).is_true()
	assert_str(book.get_name(id)).is_equal("Miner")


func test_create_trims_the_name() -> void:
	var book := LoadoutBook.new()

	var id: String = book.create("  Miner  ")

	assert_str(book.get_name(id)).is_equal("Miner")


func test_create_rejects_a_blank_name() -> void:
	var book := LoadoutBook.new()

	assert_str(book.create("   ")).is_equal("")
	assert_int(book.list_ids().size()).is_equal(0)


func test_create_rejects_a_name_already_in_use_ignoring_case() -> void:
	var book := LoadoutBook.new()
	book.create("Miner")

	assert_str(book.create("miner")).is_equal("")
	assert_int(book.list_ids().size()).is_equal(1)


func test_create_never_reuses_the_id_of_a_deleted_loadout() -> void:
	var book := LoadoutBook.new()
	var first: String = book.create("A")
	book.delete(first)

	var second: String = book.create("B")

	assert_str(second).is_not_equal(first)


func test_list_ids_keeps_creation_order() -> void:
	var book := LoadoutBook.new()
	var a: String = book.create("A")
	var b: String = book.create("B")
	var c: String = book.create("C")

	assert_array(book.list_ids()).is_equal([a, b, c])


func test_create_emits_changed() -> void:
	var book := LoadoutBook.new()
	var counter := Doubles.SignalCounter.new(book.changed)

	book.create("Miner")

	assert_int(counter.read()).is_equal(1)


func test_rename_changes_the_name() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")

	assert_bool(book.rename(id, "Digger")).is_true()
	assert_str(book.get_name(id)).is_equal("Digger")


func test_rename_rejects_a_blank_name_or_one_used_by_another_loadout() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.create("Guard")

	assert_bool(book.rename(id, "  ")).is_false()
	assert_bool(book.rename(id, "GUARD")).is_false()
	assert_str(book.get_name(id)).is_equal("Miner")


func test_rename_to_its_own_name_with_different_case_is_allowed() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("miner")

	assert_bool(book.rename(id, "Miner")).is_true()
	assert_str(book.get_name(id)).is_equal("Miner")


func test_rename_unknown_loadout_fails() -> void:
	assert_bool(LoadoutBook.new().rename("nope", "X")).is_false()


func test_delete_removes_the_loadout() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")

	book.delete(id)

	assert_bool(book.has(id)).is_false()
	assert_int(book.list_ids().size()).is_equal(0)


func test_delete_emits_changed_on_success() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	# Attach the counter after create() so only delete()'s own emission is counted.
	var counter := Doubles.SignalCounter.new(book.changed)

	book.delete(id)

	assert_int(counter.read()).is_equal(1)


func test_delete_unknown_loadout_is_silent() -> void:
	var book := LoadoutBook.new()
	var counter := Doubles.SignalCounter.new(book.changed)

	book.delete("nope")

	assert_int(counter.read()).is_equal(0)


func test_find_id_by_name_ignores_case_and_returns_empty_when_missing() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")

	assert_str(book.find_id_by_name("mINER")).is_equal(id)
	assert_str(book.find_id_by_name("Ghost")).is_equal("")


# ==============================
# set_slot / clear_slot / get_slots
# ==============================

func test_set_slot_stores_one_item_per_slot() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")

	assert_bool(book.set_slot(id, Equipment.SLOT_MAIN_HAND, "pick")).is_true()
	assert_bool(book.set_slot(id, Equipment.SLOT_MAIN_HAND, "axe")).is_true()

	assert_dict(book.get_slots(id)).is_equal({Equipment.SLOT_MAIN_HAND: "axe"})


func test_set_slot_rejects_an_unknown_slot_id() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")

	assert_bool(book.set_slot(id, "tail", "pick")).is_false()
	assert_dict(book.get_slots(id)).is_empty()


func test_set_slot_rejects_a_blank_item_id() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")

	assert_bool(book.set_slot(id, Equipment.SLOT_HEAD, "")).is_false()
	assert_dict(book.get_slots(id)).is_empty()


func test_set_slot_on_unknown_loadout_fails() -> void:
	assert_bool(LoadoutBook.new().set_slot("nope", Equipment.SLOT_HEAD, "helm")).is_false()


func test_clear_slot_removes_only_that_slot() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_HEAD, "helm")
	book.set_slot(id, Equipment.SLOT_MAIN_HAND, "pick")

	book.clear_slot(id, Equipment.SLOT_HEAD)

	assert_dict(book.get_slots(id)).is_equal({Equipment.SLOT_MAIN_HAND: "pick"})


func test_get_slots_returns_a_copy() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_HEAD, "helm")

	var copy: Dictionary = book.get_slots(id)
	copy[Equipment.SLOT_HEAD] = "tampered"

	assert_str(book.get_slots(id)[Equipment.SLOT_HEAD]).is_equal("helm")


func test_set_slot_emits_changed() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	var counter := Doubles.SignalCounter.new(book.changed)

	book.set_slot(id, Equipment.SLOT_HEAD, "helm")

	assert_int(counter.read()).is_equal(1)


# ==============================
# capture_from
# ==============================

func test_capture_from_copies_only_non_empty_targets() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	var eq: Equipment = _make_equipment()
	eq.set_desired_item(Equipment.SLOT_HEAD, "helm")
	eq.set_desired_item(Equipment.SLOT_MAIN_HAND, "pick")

	book.capture_from(id, eq)

	assert_dict(book.get_slots(id)).is_equal({
		Equipment.SLOT_HEAD: "helm",
		Equipment.SLOT_MAIN_HAND: "pick",
	})


func test_capture_from_replaces_the_slots_it_held_before() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_FEET, "boots")
	var eq: Equipment = _make_equipment()
	eq.set_desired_item(Equipment.SLOT_HEAD, "helm")

	book.capture_from(id, eq)

	assert_dict(book.get_slots(id)).is_equal({Equipment.SLOT_HEAD: "helm"})


func test_capture_from_unknown_loadout_is_silent() -> void:
	var book := LoadoutBook.new()
	var counter := Doubles.SignalCounter.new(book.changed)

	book.capture_from("nope", _make_equipment())

	assert_int(counter.read()).is_equal(0)


# ==============================
# apply_to
# ==============================

func test_apply_to_sets_every_defined_slot_as_a_target() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_HEAD, "helm")
	book.set_slot(id, Equipment.SLOT_MAIN_HAND, "pick")
	var items: Array[ItemDef] = [_make_item("helm", ["equip_head"]), _make_item("pick", ["tool"])]
	var eq: Equipment = _make_equipment()

	var result: Dictionary = book.apply_to(id, eq, _resolver(items))

	assert_str(eq.get_desired_item(Equipment.SLOT_HEAD)).is_equal("helm")
	assert_str(eq.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal("pick")
	assert_int(result["changed"]).is_equal(2)
	assert_int(result["skipped"]).is_equal(0)


func test_apply_to_leaves_slots_the_loadout_does_not_define_alone() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_MAIN_HAND, "pick")
	var items: Array[ItemDef] = [_make_item("pick", ["tool"])]
	var eq: Equipment = _make_equipment()
	eq.set_desired_item(Equipment.SLOT_TORSO, "vest")

	book.apply_to(id, eq, _resolver(items))

	assert_str(eq.get_desired_item(Equipment.SLOT_TORSO)).is_equal("vest")


func test_apply_to_skips_an_item_the_resolver_does_not_know() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_MAIN_HAND, "ghost")
	var eq: Equipment = _make_equipment()

	var result: Dictionary = book.apply_to(id, eq, _resolver(_no_items()))

	assert_str(eq.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal("")
	assert_int(result["changed"]).is_equal(0)
	assert_int(result["skipped"]).is_equal(1)


func test_apply_to_skips_an_item_that_does_not_fit_the_slot() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_HEAD, "pick")
	var items: Array[ItemDef] = [_make_item("pick", ["tool"])]
	var eq: Equipment = _make_equipment()

	var result: Dictionary = book.apply_to(id, eq, _resolver(items))

	assert_str(eq.get_desired_item(Equipment.SLOT_HEAD)).is_equal("")
	assert_int(result["skipped"]).is_equal(1)


func test_apply_to_keeps_the_old_target_when_the_new_item_is_skipped() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_MAIN_HAND, "ghost")
	var eq: Equipment = _make_equipment()
	eq.set_desired_item(Equipment.SLOT_MAIN_HAND, "old")

	book.apply_to(id, eq, _resolver(_no_items()))

	assert_str(eq.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal("old")


func test_apply_to_does_not_touch_a_slot_already_on_target() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_MAIN_HAND, "pick")
	var items: Array[ItemDef] = [_make_item("pick", ["tool"])]
	var eq: Equipment = _make_equipment()
	eq.set_desired_item(Equipment.SLOT_MAIN_HAND, "pick")
	var counter := Doubles.SignalCounter.new(eq.desired_slot_changed)

	var result: Dictionary = book.apply_to(id, eq, _resolver(items))

	assert_int(counter.read()).is_equal(0)
	assert_int(result["changed"]).is_equal(0)
	assert_int(result["skipped"]).is_equal(0)


func test_apply_to_unknown_loadout_changes_nothing() -> void:
	var book := LoadoutBook.new()
	var eq: Equipment = _make_equipment()

	var result: Dictionary = book.apply_to("nope", eq, _resolver(_no_items()))

	assert_int(result["changed"]).is_equal(0)
	assert_int(result["skipped"]).is_equal(0)


func test_apply_to_does_not_modify_the_book() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_MAIN_HAND, "pick")
	var items: Array[ItemDef] = [_make_item("pick", ["tool"])]
	var counter := Doubles.SignalCounter.new(book.changed)

	book.apply_to(id, _make_equipment(), _resolver(items))

	assert_int(counter.read()).is_equal(0)


# ==============================
# matches / find_matching_ids
# ==============================

func test_matches_when_every_defined_slot_is_the_target() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_HEAD, "helm")
	book.set_slot(id, Equipment.SLOT_MAIN_HAND, "pick")
	var eq: Equipment = _make_equipment()
	eq.set_desired_item(Equipment.SLOT_HEAD, "helm")
	eq.set_desired_item(Equipment.SLOT_MAIN_HAND, "pick")

	assert_bool(book.matches(id, eq)).is_true()


func test_matches_is_false_when_one_slot_differs() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_HEAD, "helm")
	book.set_slot(id, Equipment.SLOT_MAIN_HAND, "pick")
	var eq: Equipment = _make_equipment()
	eq.set_desired_item(Equipment.SLOT_HEAD, "helm")
	eq.set_desired_item(Equipment.SLOT_MAIN_HAND, "axe")

	assert_bool(book.matches(id, eq)).is_false()


func test_matches_ignores_targets_in_slots_the_loadout_does_not_define() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_MAIN_HAND, "pick")
	var eq: Equipment = _make_equipment()
	eq.set_desired_item(Equipment.SLOT_MAIN_HAND, "pick")
	eq.set_desired_item(Equipment.SLOT_TORSO, "vest")

	assert_bool(book.matches(id, eq)).is_true()


func test_an_empty_loadout_matches_nothing() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Blank")

	assert_bool(book.matches(id, _make_equipment())).is_false()


func test_matches_unknown_loadout_is_false() -> void:
	assert_bool(LoadoutBook.new().matches("nope", _make_equipment())).is_false()


func test_find_matching_ids_lists_every_match_in_creation_order() -> void:
	var book := LoadoutBook.new()
	var a: String = book.create("A")
	var b: String = book.create("B")
	var c: String = book.create("C")
	book.set_slot(a, Equipment.SLOT_HEAD, "helm")
	book.set_slot(b, Equipment.SLOT_HEAD, "cap")
	book.set_slot(c, Equipment.SLOT_HEAD, "helm")
	var eq: Equipment = _make_equipment()
	eq.set_desired_item(Equipment.SLOT_HEAD, "helm")

	assert_array(book.find_matching_ids(eq)).is_equal([a, c])


# ==============================
# serialize / deserialize / reset
# ==============================

func test_serialize_round_trip_keeps_ids_names_and_slots() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_HEAD, "helm")
	var restored := LoadoutBook.new()

	restored.deserialize(book.serialize())

	assert_array(restored.list_ids()).is_equal([id])
	assert_str(restored.get_name(id)).is_equal("Miner")
	assert_dict(restored.get_slots(id)).is_equal({Equipment.SLOT_HEAD: "helm"})


func test_serialize_survives_a_json_round_trip() -> void:
	var book := LoadoutBook.new()
	var id: String = book.create("Miner")
	book.set_slot(id, Equipment.SLOT_HEAD, "helm")
	var restored := LoadoutBook.new()

	restored.deserialize(JSON.parse_string(JSON.stringify(book.serialize())))

	assert_dict(restored.get_slots(id)).is_equal({Equipment.SLOT_HEAD: "helm"})
	assert_str(restored.create("Guard")).is_not_equal(id)


func test_ids_created_after_a_load_do_not_collide_with_restored_ones() -> void:
	var book := LoadoutBook.new()
	var a: String = book.create("A")
	var b: String = book.create("B")
	var restored := LoadoutBook.new()
	restored.deserialize(book.serialize())

	var fresh: String = restored.create("C")

	assert_bool(fresh in [a, b]).is_false()


func test_deserialize_tolerates_missing_and_malformed_data() -> void:
	var book := LoadoutBook.new()

	book.deserialize({})
	assert_int(book.list_ids().size()).is_equal(0)

	book.deserialize({"loadouts": "garbage", "next_number": "x"})
	assert_int(book.list_ids().size()).is_equal(0)

	book.deserialize({"loadouts": {
		"loadout_1": {"name": "Ok", "slots": {"head": "helm", "tail": "x", "feet": ""}},
		"loadout_2": "not a dictionary",
		"loadout_3": {"slots": {}},
	}})
	assert_str(book.get_name("loadout_1")).is_equal("Ok")
	assert_dict(book.get_slots("loadout_1")).is_equal({"head": "helm"})
	assert_bool(book.has("loadout_2")).is_false()
	assert_str(book.get_name("loadout_3")).is_equal("loadout_3")


func test_deserialize_replaces_whatever_the_book_held() -> void:
	var book := LoadoutBook.new()
	var old_id: String = book.create("Old")

	book.deserialize({})

	assert_bool(book.has(old_id)).is_false()


func test_reset_clears_everything_and_emits_changed() -> void:
	var book := LoadoutBook.new()
	book.create("Miner")
	var counter := Doubles.SignalCounter.new(book.changed)

	book.reset()

	assert_int(book.list_ids().size()).is_equal(0)
	assert_int(counter.read()).is_equal(1)


# ==============================
# Colony wiring
# ==============================

func test_colony_saves_and_restores_its_loadouts() -> void:
	var id: String = Colony.loadouts.create("Miner")
	Colony.loadouts.set_slot(id, Equipment.SLOT_HEAD, "helm")
	var saved: Dictionary = Colony.serialize()

	Colony.loadouts.reset()
	Colony.deserialize(saved)

	assert_str(Colony.loadouts.get_name(id)).is_equal("Miner")
	assert_dict(Colony.loadouts.get_slots(id)).is_equal({Equipment.SLOT_HEAD: "helm"})


func test_colony_loads_an_old_save_without_loadouts_as_an_empty_book() -> void:
	Colony.loadouts.create("Leftover")

	Colony.deserialize({"colonists": []})

	assert_int(Colony.loadouts.list_ids().size()).is_equal(0)


func test_colony_reset_for_new_game_clears_loadouts() -> void:
	Colony.loadouts.create("Miner")

	Colony.reset_for_new_game()

	assert_int(Colony.loadouts.list_ids().size()).is_equal(0)
