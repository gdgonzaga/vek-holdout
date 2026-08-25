extends GdUnitTestSuite

## Unit tests for Phase 2 Fractional Job System, JobInstance, WorkerClaim, and declarative JobDef.

const JobInstanceScript = preload("res://subsystems/jobs/job_instance.gd")
const WorkerClaimScript = preload("res://subsystems/jobs/worker_claim.gd")
const JobDefScript = preload("res://data/jobs/job_def.gd")


func _create_dummy_job_def(
	id: String = "mine_voxel",
	anim: StringName = &"digging",
	tool_tag: StringName = &"pickaxe",
	units_per_swing: int = 20,
	duration: float = 1.0
) -> JobDef:
	var def: JobDef = auto_free(JobDef.new())
	def.id = id
	def.display_name = "Mine Voxel"
	def.labor_id = "mining"
	def.work_animation = anim
	def.required_tool_tag = tool_tag
	def.default_units_per_cycle = units_per_swing
	def.work_duration = duration
	def.base_priority = 0.8
	return def


func test_job_instance_initialization() -> void:
	var def := _create_dummy_job_def()
	var job = JobInstanceScript.create(def, 100, Vector3(1, 2, 3))
	
	assert_str(job.labor_id).is_equal("mining")
	assert_str(job.title).is_equal("Mine Voxel")
	assert_int(job.total_units).is_equal(100)
	assert_int(job.unclaimed_units).is_equal(100)
	assert_int(job.completed_units).is_equal(0)
	assert_bool(job.is_available()).is_true()
	assert_bool(job.is_completed).is_false()
	assert_bool(job.is_cancelled).is_false()
	assert_int(job.get_remaining_uncompleted_units()).is_equal(100)


func test_single_claim_and_completion() -> void:
	var def := _create_dummy_job_def()
	var job = JobInstanceScript.create(def, 50)
	
	var claim = job.try_claim_units("colonist_1", 20)
	assert_object(claim).is_not_null()
	assert_str(claim.colonist_id).is_equal("colonist_1")
	assert_int(claim.claimed_units).is_equal(20)
	assert_int(claim.completed_units).is_equal(0)
	assert_int(job.unclaimed_units).is_equal(30)
	assert_int(job.completed_units).is_equal(0)
	
	# Apply partial work
	var applied: int = claim.apply_work(10)
	assert_int(applied).is_equal(10)
	assert_int(claim.completed_units).is_equal(10)
	assert_int(claim.get_remaining_units()).is_equal(10)
	assert_int(job.completed_units).is_equal(10)
	assert_bool(claim.is_finished()).is_false()
	
	# Finish the remaining units for this claim
	applied = claim.apply_work(10)
	assert_int(applied).is_equal(10)
	assert_int(claim.completed_units).is_equal(20)
	assert_bool(claim.is_finished()).is_true()
	assert_int(job.completed_units).is_equal(20)
	assert_int(job.unclaimed_units).is_equal(30)
	assert_bool(job.is_completed).is_false()


func test_concurrent_multi_colonist_mining() -> void:
	var def := _create_dummy_job_def("mine_block", &"digging", &"pickaxe", 20)
	var job = JobInstanceScript.create(def, 100)
	
	# 3 colonists claim batches simultaneously
	var claim_a = job.try_claim_units("colonist_a", 20)
	var claim_b = job.try_claim_units("colonist_b", 20)
	var claim_c = job.try_claim_units("colonist_c", 20)
	
	assert_object(claim_a).is_not_null()
	assert_object(claim_b).is_not_null()
	assert_object(claim_c).is_not_null()
	assert_int(job.unclaimed_units).is_equal(40)
	assert_int(job.active_claims.size()).is_equal(3)
	
	# Colonists finish their first batches
	claim_a.apply_work(20)
	claim_b.apply_work(20)
	claim_c.apply_work(20)
	
	assert_int(job.completed_units).is_equal(60)
	assert_int(job.active_claims.size()).is_equal(0)
	assert_int(job.unclaimed_units).is_equal(40)
	assert_bool(job.is_completed).is_false()
	
	# Colonists A and B take the final two batches
	var claim_a2 = job.try_claim_units("colonist_a", 20)
	var claim_b2 = job.try_claim_units("colonist_b", 20)
	assert_object(claim_a2).is_not_null()
	assert_object(claim_b2).is_not_null()
	assert_int(job.unclaimed_units).is_equal(0)
	assert_bool(job.is_available()).is_false()
	
	# Colonist C tries to claim when unclaimed is 0
	var claim_c2 = job.try_claim_units("colonist_c", 20)
	assert_object(claim_c2).is_null()
	
	# Finish remaining batches
	claim_a2.apply_work(20)
	claim_b2.apply_work(20)
	
	assert_int(job.completed_units).is_equal(100)
	assert_bool(job.is_completed).is_true()
	assert_int(job.get_remaining_uncompleted_units()).is_equal(0)


func test_claim_clamping_to_unclaimed_units() -> void:
	var def := _create_dummy_job_def()
	var job = JobInstanceScript.create(def, 25)
	
	# Request 50 units when only 25 are available
	var claim = job.try_claim_units("colonist_1", 50)
	assert_object(claim).is_not_null()
	assert_int(claim.claimed_units).is_equal(25)
	assert_int(job.unclaimed_units).is_equal(0)
	assert_bool(job.is_available()).is_false()


func test_abandon_claim_restores_unclaimed_units() -> void:
	var def := _create_dummy_job_def()
	var job = JobInstanceScript.create(def, 100)
	
	var claim = job.try_claim_units("colonist_1", 40)
	assert_int(job.unclaimed_units).is_equal(60)
	
	# Colonist works 10 units then gets drafted/interrupted
	claim.apply_work(10)
	assert_int(job.completed_units).is_equal(10)
	assert_int(claim.completed_units).is_equal(10)
	
	# Abandon claim (restores 30 unworked units)
	claim.abandon()
	
	assert_int(job.unclaimed_units).is_equal(90)
	assert_int(job.completed_units).is_equal(10)
	assert_int(job.active_claims.size()).is_equal(0)
	assert_bool(job.is_available()).is_true()


func test_batch_hauling_lifecycle() -> void:
	var def: JobDef = auto_free(JobDef.new())
	def.id = "hauling"
	def.display_name = "Haul Wood"
	def.labor_id = "hauling"
	
	# Haul job for 35 Wood items
	var haul_job = JobInstanceScript.create_haul(
		def,
		&"wood",
		35,
		Vector3(0, 0, 0),
		Vector3(10, 0, 10)
	)
	
	assert_str(haul_job.item_id).is_equal("wood")
	assert_int(haul_job.total_units).is_equal(35)
	assert_int(haul_job.unclaimed_units).is_equal(35)
	
	# Colonist with carry capacity 10 reserves batch
	var batch1 = haul_job.reserve_batch(10, "hauler_1")
	assert_object(batch1).is_not_null()
	assert_int(batch1.claimed_units).is_equal(10)
	assert_int(haul_job.unclaimed_units).is_equal(25)
	
	# Hauler delivers items to destination
	batch1.apply_work(10)
	assert_int(haul_job.completed_units).is_equal(10)
	assert_bool(batch1.is_finished()).is_true()
	
	# Subsequent trips
	var batch2 = haul_job.reserve_batch(10, "hauler_1")
	batch2.apply_work(10)
	
	var batch3 = haul_job.reserve_batch(10, "hauler_1")
	batch3.apply_work(10)
	
	# Final batch takes remaining 5 units
	var batch4 = haul_job.reserve_batch(10, "hauler_1")
	assert_int(batch4.claimed_units).is_equal(5)
	batch4.apply_work(5)
	
	assert_int(haul_job.completed_units).is_equal(35)
	assert_bool(haul_job.is_completed).is_true()


func test_claim_rejection_when_exhausted() -> void:
	var def := _create_dummy_job_def()
	var job = JobInstanceScript.create(def, 20)
	
	var claim1 = job.try_claim_units("colonist_1", 20)
	assert_object(claim1).is_not_null()
	
	var claim2 = job.try_claim_units("colonist_2", 10)
	assert_object(claim2).is_null()


func test_job_cancellation() -> void:
	var def := _create_dummy_job_def()
	var job = JobInstanceScript.create(def, 100)
	
	var claim = job.try_claim_units("colonist_1", 30)
	assert_object(claim).is_not_null()
	
	job.cancel_job()
	
	assert_bool(job.is_cancelled).is_true()
	assert_bool(job.is_available()).is_false()
	assert_int(job.unclaimed_units).is_equal(0)
	assert_int(job.active_claims.size()).is_equal(0)
	
	var new_claim = job.try_claim_units("colonist_2", 10)
	assert_object(new_claim).is_null()


func test_worker_claim_forwarding() -> void:
	var def := _create_dummy_job_def("chop_tree", &"chopping", &"axe", 25, 2.0)
	var job = JobInstanceScript.create(def, 100, Vector3(5, 0, 5))
	
	var claim = job.try_claim_units("worker_9", 25)
	assert_object(claim).is_not_null()
	assert_str(claim.get_work_animation()).is_equal("chopping")
	assert_float(claim.get_work_duration()).is_equal(2.0)
	assert_str(claim.get_required_tool_tag()).is_equal("axe")
	assert_str(claim.get_labor_id()).is_equal("mining")
	assert_vector(claim.target_pos).is_equal(Vector3(5, 0, 5))
