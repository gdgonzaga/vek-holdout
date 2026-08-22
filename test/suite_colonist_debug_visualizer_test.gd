extends GdUnitTestSuite

var _colonist: Colonist
var _visualizer: ColonistDebugVisualizer


func before_test() -> void:
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	_colonist = colonist_scene.instantiate() as Colonist
	auto_free(_colonist)
	add_child(_colonist)
	_visualizer = _colonist.get_node("ColonistDebugVisualizer") as ColonistDebugVisualizer


func test_visualizer_initialization() -> void:
	assert_object(_visualizer).is_not_null()
	assert_object(_visualizer._colonist_ai).is_not_null()
	assert_object(_visualizer._label).is_not_null()
	assert_object(_visualizer._immediate_mesh).is_not_null()


func test_resolve_colonist_state_idle_move_work() -> void:
	var ai = _colonist.get_node("ColonistAI")
	
	# IDLE state
	ai._state = ColonistAI.State.IDLE
	assert_str(_visualizer._resolve_colonist_state()).is_equal("IDLE")

	# MOVE state
	ai._state = ColonistAI.State.MOVE
	_colonist.set_path([Vector3(1, 0, 1), Vector3(2, 0, 2)])
	assert_str(_visualizer._resolve_colonist_state()).is_equal("MOVE (wp 1/2)")

	# WORK state
	ai._state = ColonistAI.State.WORK
	ai._work_elapsed = 1.2
	ai._work_duration = 2.0
	assert_str(_visualizer._resolve_colonist_state()).is_equal("WORK (1.2s / 2.0s)")


func test_resolve_colonist_job_and_leg() -> void:
	var job := Job.new()
	job.id = "abc12345678"
	job.title = "Dig Trench"
	job.anchor_cell = Vector3i(10, 5, 12)
	_colonist.current_job = job

	var job_str := _visualizer._resolve_colonist_job()
	assert_str(job_str).contains("Job: Dig Trench [abc123]")
	assert_str(job_str).contains("Anchor: (10, 5, 12)")

	# Test with active Leg
	var ai = _colonist.get_node("ColonistAI")
	var leg := JobLeg.new()
	leg.kind = 1 # FETCH
	leg.location = Vector3(5.0, 1.0, 8.0)
	ai._leg = leg

	var job_str_with_leg := _visualizer._resolve_colonist_job()
	assert_str(job_str_with_leg).contains("Leg: FETCH @ (5.0, 1.0, 8.0)")


func test_resolve_path_info() -> void:
	_colonist.set_path([Vector3(5, 0, 0), Vector3(10, 0, 0)])
	var info := _visualizer._resolve_path_info()
	assert_str(info).contains("Wp 1/2")
	assert_str(info).contains("Dest:")


func test_draw_navigation_path_and_target_marker() -> void:
	_colonist.set_path([Vector3(5, 0, 0), Vector3(10, 0, 0)])
	_visualizer._draw_navigation_path()
	# ImmediateMesh should have generated surfaces (line strip, waypoint markers, target marker)
	assert_int(_visualizer._immediate_mesh.get_surface_count()).is_greater(0)


func test_resolve_carried_items() -> void:
	_colonist.inventory.items["wood"] = 3
	_colonist.inventory.items["stone"] = 5
	var carry := _visualizer._resolve_carried_items()
	assert_str(carry).contains("wood x3")
	assert_str(carry).contains("stone x5")
