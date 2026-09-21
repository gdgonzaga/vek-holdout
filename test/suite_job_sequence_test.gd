extends GdUnitTestSuite
## Unit tests for JobSequence pipeline orchestration (ARCH "Subsystem: Jobs").

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const JobFixtures = preload("res://test/helpers/job_fixtures.gd")

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

	var job1 := Job.from_def(JobFixtures.deploy())
	job1.id = "job_step_1"
	job1.sequence_id = seq.id
	board.add_job(job1)
	seq.add_step(job1.id)

	var bp := auto_free(Blueprint.new()) as Blueprint
	bp.target_def_id = "test_wall"
	add_child(bp)

	var job2 := Job.from_def(JobFixtures.construction())
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

	# Completing step 1 flags it finished; the board's own poll prunes it and advances the
	# sequence (this test never calls advance_step itself).
	job1.is_completed = true
	var poller := _sandbox.make_colonist()
	poller.global_position = Vector3(50.0, 0.0, 50.0) # clear of the blueprint's cell so step 2 stays claimable
	board.get_best_job_for(poller)

	assert_object(board.get_job("job_step_1")).is_null()
	assert_object(board.get_job("job_step_2")).is_same(job2)
	assert_int(seq.current_step_index).is_equal(1)
	assert_bool(seq.is_step_active("job_step_1")).is_false()
	assert_bool(seq.is_step_active("job_step_2")).is_true()
	assert_bool(job2.is_available()).is_true()

	# Completing the last step lets the next poll finish the sequence and retire it from the board
	job2.is_completed = true
	board.get_best_job_for(poller)
	assert_int(seq.status).is_equal(int(JobSequence.Status.COMPLETED))
	assert_object(board.get_sequence("seq_test_1")).is_null()


func test_sequence_cancellation_cascades_to_all_steps() -> void:
	var board: JobBoard = Colony.job_board

	var seq := JobSequence.new()
	seq.id = "seq_test_cancel"

	var job1 := Job.from_def(JobFixtures.hauling())
	job1.id = "cancel_j1"
	job1.sequence_id = seq.id
	board.add_job(job1)
	seq.add_step(job1.id)

	var job2 := Job.from_def(JobFixtures.construction())
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
