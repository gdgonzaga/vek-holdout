## gdUnit4 test suite for FetchEquipmentJobDef and EquipmentAudit.
## Tests are content-agnostic: all ItemDefs are created in-memory.
## In-memory defs are registered in ItemDB._defs_by_id during tests and cleared in after_test().
extends GdUnitTestSuite

const Doubles := preload("res://test/helpers/doubles.gd")
const ColonySandboxHelper := preload("res://test/helpers/colony_sandbox.gd")

var _sandbox: ColonySandboxHelper
var _previous_item_defs: Dictionary = {}

# ==============================
# Helpers
# ==============================

func before_test() -> void:
	_sandbox = ColonySandboxHelper.new(self)


func after_test() -> void:
	if ItemDB != null:
		for id_val in _previous_item_defs:
			if _previous_item_defs[id_val] != null:
				ItemDB._defs_by_id[id_val] = _previous_item_defs[id_val]
			else:
				ItemDB._defs_by_id.erase(id_val)
	_previous_item_defs.clear()
	_sandbox.restore()


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


func _make_colonist() -> Colonist:
	return _sandbox.make_colonist()


func _make_fetch_job_def() -> FetchEquipmentJobDef:
	var def: FetchEquipmentJobDef = auto_free(FetchEquipmentJobDef.new())
	def.id = "fetch_equipment"
	def.display_name = "Fetch Equipment"
	def.max_assignees = 1
	return def


# ==============================
# FetchEquipmentJob subclass
# ==============================

func test_fetch_job_has_target_slot_and_item_id() -> void:
	var job: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	job.target_slot = Equipment.SLOT_MAIN_HAND
	job.target_item_id = "test_tool"
	assert_str(job.target_slot).is_equal(Equipment.SLOT_MAIN_HAND)
	assert_str(job.target_item_id).is_equal("test_tool")


func test_fetch_job_is_a_job() -> void:
	var job: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	assert_bool(job is Job).is_true()


# ==============================
# EquipmentAudit — equip from inventory
# ==============================

func test_audit_equips_from_inventory_immediately() -> void:
	var colonist: Colonist = _make_colonist()
	var _item: ItemDef = _make_item("test_tool_a", ["tool"])
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_tool_a")
	colonist.inventory.items["test_tool_a"] = 1

	var success: bool = EquipmentAudit._equip_from_inventory(colonist, Equipment.SLOT_MAIN_HAND, "test_tool_a")
	assert_bool(success).is_true()
	assert_bool(colonist.equipment.is_desired_equipped(Equipment.SLOT_MAIN_HAND)).is_true()
	assert_bool(colonist.inventory.has_item("test_tool_a", 1)).is_false()


# ==============================
# EquipmentAudit — post fetch job
# ==============================

func test_audit_posts_fetch_job_when_in_storage() -> void:
	var colonist: Colonist = _make_colonist()
	var _item: ItemDef = _make_item("test_tool_store", ["tool"])
	_sandbox.make_crate("test_tool_store", 3)
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_tool_store")

	EquipmentAudit.run_audit(colonist, Colony.job_board)

	var exists: bool = EquipmentAudit._fetch_job_exists(
		colonist, Equipment.SLOT_MAIN_HAND, "test_tool_store", Colony.job_board)
	assert_bool(exists).is_true()


func test_audit_no_duplicate_jobs() -> void:
	var colonist: Colonist = _make_colonist()
	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_tool_b")

	var job1: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	job1.id = "test-job-1"
	job1.def = def
	job1.target_colonist_id = colonist.colonist_id
	job1.target_slot = Equipment.SLOT_MAIN_HAND
	job1.target_item_id = "test_tool_b"
	Colony.job_board.add_job(job1)

	var exists: bool = EquipmentAudit._fetch_job_exists(
		colonist, Equipment.SLOT_MAIN_HAND, "test_tool_b", Colony.job_board)
	assert_bool(exists).is_true()

	Colony.job_board.remove_job("test-job-1")


func test_audit_does_not_report_stale_item_id_as_existing() -> void:
	var colonist: Colonist = _make_colonist()
	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_tool_new")

	var old_job: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	old_job.id = "test-job-old"
	old_job.def = def
	old_job.target_colonist_id = colonist.colonist_id
	old_job.target_slot = Equipment.SLOT_MAIN_HAND
	old_job.target_item_id = "test_tool_old"
	Colony.job_board.add_job(old_job)

	var exists: bool = EquipmentAudit._fetch_job_exists(
		colonist, Equipment.SLOT_MAIN_HAND, "test_tool_new", Colony.job_board)
	assert_bool(exists).is_false()

	Colony.job_board.remove_job("test-job-old")


func test_audit_replaces_stale_job_on_desire_change() -> void:
	var colonist: Colonist = _make_colonist()
	var _item1: ItemDef = _make_item("test_tool_v1", ["tool"])
	var _item2: ItemDef = _make_item("test_tool_v2", ["tool"])
	_sandbox.make_crate("test_tool_v1", 2)
	_sandbox.make_crate("test_tool_v2", 2)

	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_tool_v1")
	EquipmentAudit.run_audit(colonist, Colony.job_board)
	assert_bool(EquipmentAudit._fetch_job_exists(colonist, Equipment.SLOT_MAIN_HAND, "test_tool_v1", Colony.job_board)).is_true()

	# Change desired item
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_tool_v2")
	EquipmentAudit.run_audit(colonist, Colony.job_board)
	assert_bool(EquipmentAudit._fetch_job_exists(colonist, Equipment.SLOT_MAIN_HAND, "test_tool_v2", Colony.job_board)).is_true()


# ==============================
# EquipmentAudit — unequip wrong item
# ==============================

func test_audit_unequips_wrong_item_to_inventory() -> void:
	var colonist: Colonist = _make_colonist()
	var wrong_item: ItemDef = _make_item("test_wrong_tool", ["tool"])
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_correct_tool")
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, wrong_item)
	assert_bool(colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND) != null).is_true()

	var result: bool = EquipmentAudit._unequip_to_inventory(colonist, Equipment.SLOT_MAIN_HAND)
	assert_bool(result).is_true()
	assert_bool(colonist.equipment.is_empty(Equipment.SLOT_MAIN_HAND)).is_true()
	assert_bool(colonist.inventory.has_item("test_wrong_tool", 1)).is_true()


func test_audit_skips_unequip_when_carry_full() -> void:
	var colonist: Colonist = _make_colonist()
	colonist.inventory.capacity = 0.5
	var wrong_item: ItemDef = _make_item("test_heavy_tool", ["tool"], 10.0)
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, wrong_item)

	var result: bool = EquipmentAudit._unequip_to_inventory(colonist, Equipment.SLOT_MAIN_HAND)
	assert_bool(result).is_false()
	assert_bool(colonist.equipment.is_empty(Equipment.SLOT_MAIN_HAND)).is_false()


# ==============================
# EquipmentAudit — hand/holster swap
# ==============================

func test_audit_swaps_hand_holster_instead_of_fetching() -> void:
	var colonist: Colonist = _make_colonist()
	var pick: ItemDef = _make_item("test_pick", ["tool"])
	var club: ItemDef = _make_item("test_club", ["tool"])

	colonist.equipment.equip(Equipment.SLOT_HOLSTER, pick)
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, club)
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_pick")

	EquipmentAudit._audit_hand_pair(colonist, Colony.job_board)

	var hand_item: ItemDef = colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND)
	assert_bool(hand_item != null and hand_item.id == "test_pick").is_true()

	var fetch_exists: bool = EquipmentAudit._fetch_job_exists(
		colonist, Equipment.SLOT_MAIN_HAND, "test_pick", Colony.job_board)
	assert_bool(fetch_exists).is_false()


func test_audit_swaps_holster_to_hand_when_desired_sidearm_in_hand() -> void:
	var colonist: Colonist = _make_colonist()
	var pick: ItemDef = _make_item("test_pick", ["tool"])
	var club: ItemDef = _make_item("test_club", ["tool"])

	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, club)
	colonist.equipment.equip(Equipment.SLOT_HOLSTER, pick)
	colonist.equipment.set_desired_item(Equipment.SLOT_HOLSTER, "test_club")

	EquipmentAudit._audit_hand_pair(colonist, Colony.job_board)

	var holster_item: ItemDef = colonist.equipment.get_item(Equipment.SLOT_HOLSTER)
	assert_bool(holster_item != null and holster_item.id == "test_club").is_true()


func test_audit_swaps_shield_back_pair() -> void:
	var colonist: Colonist = _make_colonist()
	var shield: ItemDef = _make_item("test_shield", ["shield"])
	colonist.equipment.equip(Equipment.SLOT_BACK, shield)
	colonist.equipment.set_desired_item(Equipment.SLOT_OFF_HAND, "test_shield")

	EquipmentAudit._audit_shield_pair(colonist, Colony.job_board)

	var off_item: ItemDef = colonist.equipment.get_item(Equipment.SLOT_OFF_HAND)
	assert_bool(off_item != null and off_item.id == "test_shield").is_true()
	assert_bool(colonist.equipment.is_empty(Equipment.SLOT_BACK)).is_true()


# ==============================
# FetchEquipmentJobDef — should_close
# ==============================

func test_fetch_job_def_should_close_when_slot_satisfied() -> void:
	var colonist: Colonist = _make_colonist()
	var item: ItemDef = _make_item("test_tool_c", ["tool"])
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_tool_c")
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, item)

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	job.target_colonist_id = colonist.colonist_id
	job.target_slot = Equipment.SLOT_MAIN_HAND
	job.target_item_id = "test_tool_c"

	assert_bool(def.should_close(job)).is_true()


func test_fetch_job_def_should_close_when_desired_changed() -> void:
	var colonist: Colonist = _make_colonist()
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_tool_new")

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	job.target_colonist_id = colonist.colonist_id
	job.target_slot = Equipment.SLOT_MAIN_HAND
	job.target_item_id = "test_tool_old"

	assert_bool(def.should_close(job)).is_true()


func test_fetch_job_def_should_close_when_item_gone_from_storage() -> void:
	var colonist: Colonist = _make_colonist()
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_tool_lost")

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	job.target_colonist_id = colonist.colonist_id
	job.target_slot = Equipment.SLOT_MAIN_HAND
	job.target_item_id = "test_tool_lost"

	assert_bool(def.should_close(job)).is_true()


# ==============================
# FetchEquipmentJobDef — is_available_for
# ==============================

func test_fetch_job_def_not_available_when_desired_changed() -> void:
	var colonist: Colonist = _make_colonist()
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_tool_new")

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	job.target_colonist_id = colonist.colonist_id
	job.target_slot = Equipment.SLOT_MAIN_HAND
	job.target_item_id = "test_tool_old"

	assert_bool(def.is_available_for(job, colonist)).is_false()


func test_fetch_job_def_not_available_when_slot_satisfied() -> void:
	var colonist: Colonist = _make_colonist()
	var item: ItemDef = _make_item("test_tool_d", ["tool"])
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_tool_d")
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, item)

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	job.target_colonist_id = colonist.colonist_id
	job.target_slot = Equipment.SLOT_MAIN_HAND
	job.target_item_id = "test_tool_d"

	assert_bool(def.is_available_for(job, colonist)).is_false()


func test_fetch_job_def_is_not_available_when_no_storage() -> void:
	var colonist: Colonist = _make_colonist()
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "test_tool_no_store")

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	job.target_colonist_id = colonist.colonist_id
	job.target_slot = Equipment.SLOT_MAIN_HAND
	job.target_item_id = "test_tool_no_store"

	assert_bool(def.is_available_for(job, colonist)).is_false()


# ==============================
# FetchEquipmentJobDef — meets_requirements
# ==============================

func test_fetch_job_def_meets_requirements_only_for_designated_colonist() -> void:
	var colonist_a: Colonist = _make_colonist()
	var colonist_b: Colonist = _make_colonist()

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	job.target_colonist_id = colonist_a.colonist_id
	job.target_slot = Equipment.SLOT_MAIN_HAND
	job.target_item_id = "test_tool_e"

	assert_bool(def.meets_requirements(colonist_a, job)).is_true()
	assert_bool(def.meets_requirements(colonist_b, job)).is_false()


# ==============================
# FetchEquipmentJobDef — complete() execution
# ==============================

func test_complete_equips_item_and_removes_from_crate() -> void:
	var colonist: Colonist = _make_colonist()
	var _item: ItemDef = _make_item("test_fetch_sword", ["weapon", "tool"])
	var crate: Furniture = _sandbox.make_crate("test_fetch_sword", 2)
	var crate_inv: Inventory = Colony.storage_registry.inventory_of(crate)

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	job.id = "test-complete-job"
	job.def = def
	job.target_colonist_id = colonist.colonist_id
	job.target_slot = Equipment.SLOT_MAIN_HAND
	job.target_item_id = "test_fetch_sword"
	Colony.job_board.add_job(job)

	def.complete(colonist, job)

	# Equipped in slot
	var equipped: ItemDef = colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND)
	assert_bool(equipped != null and equipped.id == "test_fetch_sword").is_true()
	# Removed from crate inventory
	assert_int(crate_inv.get_item_count("test_fetch_sword")).is_equal(1)
	# Job removed from board by _finish
	assert_object(Colony.job_board.get_job("test-complete-job")).is_null()


func test_complete_noop_if_crate_has_no_item() -> void:
	var colonist: Colonist = _make_colonist()
	var _item: ItemDef = _make_item("test_missing_tool", ["tool"])
	_sandbox.make_crate("test_missing_tool", 0)  # Empty crate

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	job.id = "test-empty-job"
	job.def = def
	job.target_colonist_id = colonist.colonist_id
	job.target_slot = Equipment.SLOT_MAIN_HAND
	job.target_item_id = "test_missing_tool"
	Colony.job_board.add_job(job)

	def.complete(colonist, job)

	assert_bool(colonist.equipment.is_empty(Equipment.SLOT_MAIN_HAND)).is_true()
	# Job remains alive (not removed) because it did not complete
	assert_object(Colony.job_board.get_job("test-empty-job")).is_not_null()
	Colony.job_board.remove_job("test-empty-job")


func test_complete_handles_occupied_slot_with_capacity() -> void:
	var colonist: Colonist = _make_colonist()
	var old_item: ItemDef = _make_item("test_old_weapon", ["weapon"])
	var _new_item: ItemDef = _make_item("test_new_weapon", ["weapon"])
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, old_item)
	_sandbox.make_crate("test_new_weapon", 1)

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	job.id = "test-swap-occupy-job"
	job.def = def
	job.target_colonist_id = colonist.colonist_id
	job.target_slot = Equipment.SLOT_MAIN_HAND
	job.target_item_id = "test_new_weapon"
	Colony.job_board.add_job(job)

	def.complete(colonist, job)

	# New item equipped
	assert_str(colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("test_new_weapon")
	# Old item moved into carry inventory
	assert_bool(colonist.inventory.has_item("test_old_weapon", 1)).is_true()


func test_complete_skips_when_occupied_slot_no_capacity() -> void:
	var colonist: Colonist = _make_colonist()
	colonist.inventory.capacity = 0.5
	var old_item: ItemDef = _make_item("test_heavy_old", ["weapon"], 10.0)
	var _new_item: ItemDef = _make_item("test_heavy_new", ["weapon"], 1.0)
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, old_item)
	_sandbox.make_crate("test_heavy_new", 1)

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = auto_free(FetchEquipmentJob.new())
	job.id = "test-no-cap-job"
	job.def = def
	job.target_colonist_id = colonist.colonist_id
	job.target_slot = Equipment.SLOT_MAIN_HAND
	job.target_item_id = "test_heavy_new"
	Colony.job_board.add_job(job)

	def.complete(colonist, job)

	# Slot was not replaced because old item could not fit in carry
	assert_str(colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("test_heavy_old")
	assert_object(Colony.job_board.get_job("test-no-cap-job")).is_not_null()
	Colony.job_board.remove_job("test-no-cap-job")


# ==============================
# EquipmentSlotRow — sidearm display name
# ==============================

func test_slot_row_displays_holster_as_sidearm() -> void:
	assert_str(EquipmentSlotRow.SLOT_DISPLAY_NAMES.get("holster", "")).is_equal("Sidearm")


func test_slot_row_other_slots_use_title_case() -> void:
	assert_bool(EquipmentSlotRow.SLOT_DISPLAY_NAMES.has("head")).is_false()
	assert_bool(EquipmentSlotRow.SLOT_DISPLAY_NAMES.has("main_hand")).is_false()


# ==============================
# Labor Intercept Fetch Jobs
# ==============================

func test_fetch_job_def_is_available_when_labor_intercept_even_if_desire_empty() -> void:
	var colonist: Colonist = _make_colonist()
	var _item: ItemDef = _make_item("intercept_tool", ["tool"])
	_sandbox.make_crate("intercept_tool", 1)

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = FetchEquipmentJobDef.create_job(
		colonist, Equipment.SLOT_MAIN_HAND, "intercept_tool", def, true
	)

	# Desired slot is empty (""), but is_labor_intercept is true
	assert_str(colonist.equipment.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal("")
	assert_bool(def.is_available_for(job, colonist)).is_true()


func test_fetch_job_def_should_not_close_when_labor_intercept_and_desire_empty() -> void:
	var colonist: Colonist = _make_colonist()
	var _item: ItemDef = _make_item("intercept_tool", ["tool"])
	_sandbox.make_crate("intercept_tool", 1)

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = FetchEquipmentJobDef.create_job(
		colonist, Equipment.SLOT_MAIN_HAND, "intercept_tool", def, true
	)

	assert_str(colonist.equipment.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal("")
	assert_bool(def.should_close(job)).is_false()


func test_complete_stows_to_holster_on_labor_intercept() -> void:
	var colonist: Colonist = _make_colonist()
	var sword: ItemDef = _make_item("sword", ["weapon"])
	var _pick: ItemDef = _make_item("mining_pick", ["tool"])
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, sword)
	_sandbox.make_crate("mining_pick", 1)

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = FetchEquipmentJobDef.create_job(
		colonist, Equipment.SLOT_MAIN_HAND, "mining_pick", def, true
	)
	Colony.job_board.add_job(job)

	def.complete(colonist, job)

	# Pick in main_hand, sword cascaded into empty holster
	assert_str(colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("mining_pick")
	assert_str(colonist.equipment.get_item(Equipment.SLOT_HOLSTER).id).is_equal("sword")


func test_complete_stows_to_inventory_on_labor_intercept_when_holster_occupied() -> void:
	var colonist: Colonist = _make_colonist()
	var sword: ItemDef = _make_item("sword", ["weapon"])
	var pistol: ItemDef = _make_item("pistol", ["weapon"])
	var _pick: ItemDef = _make_item("mining_pick", ["tool"])
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, sword)
	colonist.equipment.equip(Equipment.SLOT_HOLSTER, pistol)
	_sandbox.make_crate("mining_pick", 1)

	var def: FetchEquipmentJobDef = _make_fetch_job_def()
	var job: FetchEquipmentJob = FetchEquipmentJobDef.create_job(
		colonist, Equipment.SLOT_MAIN_HAND, "mining_pick", def, true
	)
	Colony.job_board.add_job(job)

	def.complete(colonist, job)

	# Pick in main_hand, pistol stays in holster, sword stowed into carry inventory
	assert_str(colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("mining_pick")
	assert_str(colonist.equipment.get_item(Equipment.SLOT_HOLSTER).id).is_equal("pistol")
	assert_bool(colonist.inventory.has_item("sword", 1)).is_true()


func test_idle_audit_unequips_unassigned_work_tool_to_inventory_when_no_desired_gear() -> void:
	var colonist: Colonist = _make_colonist()
	var hammer: ItemDef = _make_item("hammer", ["tool", "construction_tool"])
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, hammer)

	# Desired gear is empty string
	assert_str(colonist.equipment.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal("")
	assert_str(colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("hammer")
	assert_int(colonist.inventory.get_item_count("hammer")).is_equal(0)

	# Run audit when idle
	EquipmentAudit.run_audit(colonist, Colony.job_board)

	# Hammer should be unequipped to carry pockets
	assert_object(colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND)).is_null()
	assert_int(colonist.inventory.get_item_count("hammer")).is_equal(1)


func test_idle_audit_preserves_non_tool_gear_when_no_desired_gear() -> void:
	var colonist: Colonist = _make_colonist()
	var sword: ItemDef = _make_item("sword", ["weapon", "melee"])
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, sword)

	# Desired gear is empty string
	assert_str(colonist.equipment.get_desired_item(Equipment.SLOT_MAIN_HAND)).is_equal("")

	# Run audit when idle
	EquipmentAudit.run_audit(colonist, Colony.job_board)

	# Sword (weapon, not tool) should stay equipped
	assert_str(colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("sword")
	assert_int(colonist.inventory.get_item_count("sword")).is_equal(0)
