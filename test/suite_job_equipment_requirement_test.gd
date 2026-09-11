## gdUnit4 test suite for job equipment requirements, dynamic fetch intercept, and durability readiness.
## Tests are content-agnostic: in-memory defs only.
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


func _make_work_job_def(req_id: String = "", req_tags: Array[StringName] = []) -> JobDef:
	var def: JobDef = auto_free(JobDef.new())
	def.id = "test_mining_def"
	def.display_name = "Mining"
	def.labor_id = "mining"
	def.work_duration = 1.0
	def.required_equipped = req_id
	def.required_equipped_tags = req_tags
	return def


# ==============================
# 1. Equipment Requirements API
# ==============================

func test_equipment_has_required_equipment_by_id() -> void:
	var colonist: Colonist = _make_colonist()
	var pick: ItemDef = _make_item("mining_pick", ["mining_tool", "tool"])
	assert_bool(colonist.equipment.has_required_equipment("mining_pick", [])).is_false()

	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, pick)
	assert_bool(colonist.equipment.has_required_equipment("mining_pick", [])).is_true()
	assert_bool(colonist.equipment.has_required_equipment("other_pick", [])).is_false()


func test_equipment_has_required_equipment_by_tags() -> void:
	var colonist: Colonist = _make_colonist()
	var pick: ItemDef = _make_item("copper_pick", ["mining_tool", "tool"])

	colonist.equipment.equip(Equipment.SLOT_HOLSTER, pick)
	assert_bool(colonist.equipment.has_required_equipment("", [&"mining_tool"])).is_true()
	assert_bool(colonist.equipment.has_required_equipment("", [&"farming_tool"])).is_false()


func test_equipment_swap_hand_for_requirements() -> void:
	var colonist: Colonist = _make_colonist()
	var axe: ItemDef = _make_item("wood_axe", ["chopping_tool", "tool"])
	var pick: ItemDef = _make_item("iron_pick", ["mining_tool", "tool"])

	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, axe)
	colonist.equipment.equip(Equipment.SLOT_HOLSTER, pick)

	# Swap to main_hand for mining_tool
	var swapped: bool = colonist.equipment.swap_hand_for_requirements("", [&"mining_tool"])
	assert_bool(swapped).is_true()
	assert_str(colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("iron_pick")
	assert_str(colonist.equipment.get_item(Equipment.SLOT_HOLSTER).id).is_equal("wood_axe")


# ==============================
# 2. StorageRegistry Tag Matching
# ==============================

func test_storage_registry_finds_closest_matching_tool() -> void:
	var _pick: ItemDef = _make_item("mining_pick_iron", ["mining_tool", "tool"])
	var crate = _sandbox.make_crate("mining_pick_iron", 2)
	crate.global_position = Vector3(5, 0, 5)

	var found_id: String = Colony.storage_registry.find_closest_item_matching(
		"", [&"mining_tool"], Vector3.ZERO
	)
	assert_str(found_id).is_equal("mining_pick_iron")


# ==============================
# 3. JobBoard Tool Gating & Intercept
# ==============================

func test_job_board_skips_job_when_tool_unavailable() -> void:
	var colonist: Colonist = _make_colonist()
	colonist.set_labor_priority("mining", 3)

	var _pick: ItemDef = _make_item("mining_pick", ["mining_tool", "tool"])
	var def: JobDef = _make_work_job_def("", [&"mining_tool"])
	var job: Job = Job.from_def(def)
	job.location = Vector3(10, 0, 10)
	Colony.job_board.add_job(job)

	# Colonist has no tool and storage has no tool -> job skipped, returns null
	var best = Colony.job_board.get_best_job_for(colonist)
	assert_object(best).is_null()


func test_job_board_intercepts_with_fetch_job_when_tool_in_storage() -> void:
	var colonist: Colonist = _make_colonist()
	colonist.set_labor_priority("mining", 3)

	var _pick: ItemDef = _make_item("mining_pick", ["mining_tool", "tool"])
	_sandbox.make_crate("mining_pick", 1)

	var def: JobDef = _make_work_job_def("", [&"mining_tool"])
	var job: Job = Job.from_def(def)
	job.location = Vector3(10, 0, 10)
	Colony.job_board.add_job(job)

	# Tool is in storage -> JobBoard intercepts and returns a targeted FetchEquipmentJob
	var best = Colony.job_board.get_best_job_for(colonist)
	assert_object(best).is_not_null()
	assert_bool(best is FetchEquipmentJob).is_true()
	var fetch_job := best as FetchEquipmentJob
	assert_str(fetch_job.target_colonist_id).is_equal(colonist.colonist_id)
	assert_str(fetch_job.target_item_id).is_equal("mining_pick")

	# The original work job was NOT claimed and remains on the board
	assert_bool(job.is_assigned(colonist.colonist_id)).is_false()


func test_job_board_returns_work_job_when_tool_already_equipped() -> void:
	var colonist: Colonist = _make_colonist()
	colonist.set_labor_priority("mining", 3)

	var pick: ItemDef = _make_item("mining_pick", ["mining_tool", "tool"])
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, pick)

	var def: JobDef = _make_work_job_def("", [&"mining_tool"])
	var job: Job = Job.from_def(def)
	job.location = Vector3(10, 0, 10)
	Colony.job_board.add_job(job)

	# Tool already equipped -> returns the mining work job directly
	var best = Colony.job_board.get_best_job_for(colonist)
	assert_object(best).is_not_null()
	assert_bool(best is Job).is_true()
	assert_str(best.id).is_equal(job.id)


# ==============================
# 4. Durability Readiness in BTActionPerformWork
# ==============================

func test_perform_work_aborts_when_tool_broken_or_unequipped() -> void:
	var colonist: Colonist = _make_colonist()
	var pick: ItemDef = _make_item("mining_pick", ["mining_tool", "tool"])
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, pick)

	var def: JobDef = _make_work_job_def("", [&"mining_tool"])
	var job: Job = Job.from_def(def)

	var bb := auto_free(Blackboard.new()) as Blackboard
	bb.set_var(&"active_job", job)

	var work_action: BTAction = auto_free(BTActionPerformWork.new()) as BTAction
	work_action.initialize(colonist, bb, colonist)

	# First tick with tool equipped: RUNNING
	assert_int(work_action.execute(0.1)).is_equal(BTAction.RUNNING)

	# Tool breaks mid-cycle (unequipped / destroyed)
	colonist.equipment.unequip(Equipment.SLOT_MAIN_HAND)

	# Next tick without tool: FAILURE (clean abort)
	assert_int(work_action.execute(0.1)).is_equal(BTAction.FAILURE)


func test_end_to_end_auto_fetch_stow_work_and_restore_cycle() -> void:
	var colonist: Colonist = _make_colonist()
	colonist.set_labor_priority("mining", 3)

	var sword: ItemDef = _make_item("iron_sword", ["weapon"])
	var _pick: ItemDef = _make_item("mining_pick", ["mining_tool", "tool"])

	# Colonist has sword equipped in main_hand, and sword configured as desired weapon
	colonist.equipment.equip(Equipment.SLOT_MAIN_HAND, sword)
	colonist.equipment.set_desired_item(Equipment.SLOT_MAIN_HAND, "iron_sword")

	# Storage has a mining_pick
	_sandbox.make_crate("mining_pick", 1)

	# Job board has a mining job requiring mining_tool
	var def: JobDef = _make_work_job_def("", [&"mining_tool"])
	var job: Job = Job.from_def(def)
	job.id = "mining_job_e2e"
	Colony.job_board.add_job(job)

	# 1. JobBoard intercepts with FetchEquipmentJob
	var intercepted_job = Colony.job_board.get_best_job_for(colonist)
	assert_object(intercepted_job).is_not_null()
	assert_bool(intercepted_job is FetchEquipmentJob).is_true()
	var fetch_job := intercepted_job as FetchEquipmentJob
	assert_bool(fetch_job.is_labor_intercept).is_true()
	assert_str(fetch_job.target_item_id).is_equal("mining_pick")

	# 2. Colonist completes fetch job: tool equipped, sword stowed to holster
	fetch_job.def.complete(colonist, fetch_job)
	assert_str(colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("mining_pick")
	assert_str(colonist.equipment.get_item(Equipment.SLOT_HOLSTER).id).is_equal("iron_sword")

	# 3. Colonist claims the original mining work job directly now that tool is equipped
	var work_job = Colony.job_board.get_best_job_for(colonist)
	assert_object(work_job).is_not_null()
	assert_str(work_job.id).is_equal("mining_job_e2e")

	# 4. Finish the mining job and remove from board
	Colony.job_board.remove_job("mining_job_e2e")

	# 5. Colonist falls idle: EquipmentAudit runs and restores desired iron_sword to main_hand
	EquipmentAudit.run_audit(colonist, Colony.job_board)
	assert_str(colonist.equipment.get_item(Equipment.SLOT_MAIN_HAND).id).is_equal("iron_sword")
	# Tool is in holster after hand/holster swap
	assert_str(colonist.equipment.get_item(Equipment.SLOT_HOLSTER).id).is_equal("mining_pick")
