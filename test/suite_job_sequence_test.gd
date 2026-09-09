extends GdUnitTestSuite
## Unit tests for JobSequence pipeline orchestration (ARCH "Subsystem: Jobs").

const HAULING_DEF: JobDef = preload("res://data/jobs/hauling.tres")
const CONSTRUCTION_DEF: JobDef = preload("res://data/jobs/construction.tres")
const CRAFTING_DEF: JobDef = preload("res://data/jobs/crafting.tres")
const DEPLOY_DEF: JobDef = preload("res://data/jobs/deploy.tres")

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

var _sandbox: ColonySandbox


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)


func after_test() -> void:
	_sandbox.restore()


func test_sequence_step_progression() -> void:
	var board: JobBoard = Colony.job_board

	var seq := JobSequence.new()
	seq.id = "seq_test_1"
	seq.title = "Test Sequence"

	var job1 := Job.from_def(DEPLOY_DEF)
	job1.id = "job_step_1"
	job1.sequence_id = seq.id
	board.add_job(job1)
	seq.add_step(job1.id)

	var bp := auto_free(Blueprint.new()) as Blueprint
	bp.target_def_id = "test_wall"
	add_child(bp)

	var job2 := Job.from_def(CONSTRUCTION_DEF)
	job2.id = "job_step_2"
	job2.target_node = bp
	job2.sequence_id = seq.id
	board.add_job(job2)
	seq.add_step(job2.id)

	board.add_sequence(seq)

	# Initial state: step 1 is active, step 2 is gated
	assert_bool(seq.is_step_active("job_step_1")).is_true()
	assert_bool(seq.is_step_active("job_step_2")).is_false()
	assert_bool(job1.is_available()).is_true()
	assert_bool(job2.is_available()).is_false()

	# Pruning step 1 (completing it) advances sequence to step 2
	job1.should_close() # check
	board.remove_job(job1.id)
	seq.advance_step()

	assert_bool(seq.is_step_active("job_step_1")).is_false()
	assert_bool(seq.is_step_active("job_step_2")).is_true()
	assert_bool(job2.is_available()).is_true()

	# Completing step 2 finishes the sequence
	seq.advance_step()
	assert_int(seq.status).is_equal(int(JobSequence.Status.COMPLETED))


func test_sequence_cancellation_cascades_to_all_steps() -> void:
	var board: JobBoard = Colony.job_board

	var seq := JobSequence.new()
	seq.id = "seq_test_cancel"

	var job1 := Job.from_def(HAULING_DEF)
	job1.id = "cancel_j1"
	job1.sequence_id = seq.id
	board.add_job(job1)
	seq.add_step(job1.id)

	var job2 := Job.from_def(CONSTRUCTION_DEF)
	job2.id = "cancel_j2"
	job2.sequence_id = seq.id
	board.add_job(job2)
	seq.add_step(job2.id)

	board.add_sequence(seq)
	assert_object(board.get_job("cancel_j1")).is_not_null()
	assert_object(board.get_job("cancel_j2")).is_not_null()

	# Cancelling sequence removes both jobs from the board
	board.cancel_sequence(seq.id)
	assert_int(seq.status).is_equal(int(JobSequence.Status.CANCELLED))
	assert_object(board.get_job("cancel_j1")).is_null()
	assert_object(board.get_job("cancel_j2")).is_null()


func test_construction_sequence_def_factory() -> void:
	var bp := auto_free(Blueprint.new()) as Blueprint
	bp.target_def_id = "test_wall"
	add_child(bp)

	var seq_def := ConstructionSequenceDef.new()
	var seq: JobSequence = seq_def.create_sequence(bp, Vector3i(1, 2, 3))
	auto_free(seq)

	assert_object(seq).is_not_null()
	assert_int(seq.step_job_ids.size()).is_equal(1) # costless blueprint has 1 step (construction)


func test_sequence_save_load_roundtrip() -> void:
	var board: JobBoard = Colony.job_board

	var seq := JobSequence.new()
	seq.id = "seq_saved"
	seq.title = "Saved Sequence"
	seq.anchor_cell = Vector3i(10, 5, 20)
	seq.step_job_ids = ["j1", "j2", "j3"]
	seq.current_step_index = 1
	board.add_sequence(seq)

	var data: Dictionary = board.serialize()
	board.clear()
	assert_object(board.get_sequence("seq_saved")).is_null()

	board.deserialize(data)
	var restored: JobSequence = board.get_sequence("seq_saved")
	assert_object(restored).is_not_null()
	assert_str(restored.title).is_equal("Saved Sequence")
	assert_bool(restored.anchor_cell == Vector3i(10, 5, 20)).is_true()
	assert_int(restored.current_step_index).is_equal(1)
	assert_bool(restored.is_step_active("j2")).is_true()
	assert_bool(restored.is_step_active("j1")).is_false()
