extends GdUnitTestSuite
## Tests for GearStatus: why a slot's target is met, pending, or unobtainable.
## Content-agnostic: ItemDefs are in-memory (registered in ItemDB only for the test's
## duration) and crates/colonists come from ColonySandbox. The resolution order mirrors
## EquipmentAudit: partner swap, pockets, queued fetch, storage, then nothing.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const ITEM_ID: String = "gear_status_item"

var _sandbox: ColonySandbox
var _previous_item_defs: Dictionary = {}


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)


func after_test() -> void:
	for id_val: String in _previous_item_defs:
		if _previous_item_defs[id_val] != null:
			ItemDB._defs_by_id[id_val] = _previous_item_defs[id_val]
		else:
			ItemDB._defs_by_id.erase(id_val)
	_previous_item_defs.clear()
	_sandbox.restore()


func _make_item(id_val: String, item_tags: Array[String]) -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = id_val
	def.tags = item_tags
	def.weight = 1.0
	if not _previous_item_defs.has(id_val):
		_previous_item_defs[id_val] = ItemDB._defs_by_id.get(id_val, null)
	ItemDB._defs_by_id[id_val] = def
	return def


func _evaluate(colonist: Colonist, slot_id: String = Equipment.SLOT_MAIN_HAND) -> GearStatus.Result:
	return GearStatus.evaluate(colonist, slot_id, _sandbox.test_registry, _sandbox.test_board)


func _post_fetch_job(colonist_id: String, slot_id: String, item_id: String) -> void:
	var job: FetchEquipmentJob = FetchEquipmentJob.new()
	job.target_colonist_id = colonist_id
	job.target_slot = slot_id
	job.target_item_id = item_id
	_sandbox.test_board.add_job(job)


# ==============================
# Terminal states
# ==============================

func test_no_target_reports_no_target() -> void:
	var colonist: Colonist = _sandbox.make_colonist()

	assert_int(_evaluate(colonist).state).is_equal(GearStatus.State.NO_TARGET)


func test_null_colonist_reports_no_target() -> void:
	var result: GearStatus.Result = GearStatus.evaluate(
			null, Equipment.SLOT_MAIN_HAND, _sandbox.test_registry, _sandbox.test_board)

	assert_int(result.state).is_equal(GearStatus.State.NO_TARGET)


func test_equipped_target_reports_met() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var item: ItemDef = _make_item(ITEM_ID, ["tool"])
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, item)
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, ITEM_ID)

	var result: GearStatus.Result = _evaluate(colonist)

	assert_int(result.state).is_equal(GearStatus.State.MET)
	assert_bool(result.is_pending()).is_false()


# ==============================
# Pending reasons
# ==============================

func test_target_in_partner_slot_reports_swap_and_names_that_slot() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var item: ItemDef = _make_item(ITEM_ID, ["tool"])
	colonist.equipment.equip(Equipment.SLOT_HOLSTER, item)
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, ITEM_ID)

	var result: GearStatus.Result = _evaluate(colonist)

	assert_int(result.state).is_equal(GearStatus.State.SWAP)
	assert_bool(result.is_pending()).is_true()
	assert_str(result.text.to_lower()).contains(
			GearText.slot_display_name(Equipment.SLOT_HOLSTER).to_lower())


func test_target_in_pockets_reports_pockets() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	_make_item(ITEM_ID, ["tool"])
	colonist.inventory.items[ITEM_ID] = 1
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, ITEM_ID)

	assert_int(_evaluate(colonist).state).is_equal(GearStatus.State.POCKETS)


func test_queued_fetch_job_for_this_colonist_and_slot_reports_fetching() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	_make_item(ITEM_ID, ["tool"])
	_sandbox.make_crate(ITEM_ID, 1)
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, ITEM_ID)
	_post_fetch_job(colonist.colonist_id, Equipment.SLOT_MAIN_HAND, ITEM_ID)

	assert_int(_evaluate(colonist).state).is_equal(GearStatus.State.FETCHING)


func test_fetch_job_for_another_colonist_does_not_count() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	_make_item(ITEM_ID, ["tool"])
	_sandbox.make_crate(ITEM_ID, 1)
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, ITEM_ID)
	_post_fetch_job("someone_else", Equipment.SLOT_MAIN_HAND, ITEM_ID)

	assert_int(_evaluate(colonist).state).is_equal(GearStatus.State.IN_STORAGE)


func test_target_in_a_crate_reports_in_storage() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	_make_item(ITEM_ID, ["tool"])
	_sandbox.make_crate(ITEM_ID, 2)
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, ITEM_ID)

	assert_int(_evaluate(colonist).state).is_equal(GearStatus.State.IN_STORAGE)


func test_target_held_nowhere_reports_unavailable() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	_make_item(ITEM_ID, ["tool"])
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, ITEM_ID)

	var result: GearStatus.Result = _evaluate(colonist)

	assert_int(result.state).is_equal(GearStatus.State.UNAVAILABLE)
	assert_bool(result.is_pending()).is_true()


# ==============================
# Resolution order
# ==============================

func test_pockets_outrank_storage() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	_make_item(ITEM_ID, ["tool"])
	_sandbox.make_crate(ITEM_ID, 1)
	colonist.inventory.items[ITEM_ID] = 1
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, ITEM_ID)

	assert_int(_evaluate(colonist).state).is_equal(GearStatus.State.POCKETS)


func test_slot_without_a_swap_partner_ignores_other_equipped_slots() -> void:
	var colonist: Colonist = _sandbox.make_colonist()
	var item: ItemDef = _make_item(ITEM_ID, ["tool", "equip_head"])
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, item)
	colonist.equipment.set_desired_item(Equipment.SLOT_HEAD, ITEM_ID)

	assert_int(_evaluate(colonist, Equipment.SLOT_HEAD).state).is_equal(GearStatus.State.UNAVAILABLE)
