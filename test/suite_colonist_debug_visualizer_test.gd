extends GdUnitTestSuite

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

var _sandbox: ColonySandbox
var _colonist: Colonist
var _visualizer: ColonistDebugVisualizer


func before_test() -> void:
	# ColonySandbox isolates Colony's map-wiring caches (R3) so an earlier
	# suite's real terrain predicate can never leak into this one.
	_sandbox = ColonySandbox.new(self)
	_colonist = _sandbox.make_colonist()
	_visualizer = _colonist.get_node("ColonistDebugVisualizer") as ColonistDebugVisualizer
	# The colonist is built directly (not through Colony's spawn flow), so its
	# pathfinder is never wired to a predicate — bind a trivial always-walkable
	# one to stop "walkability predicate not set" warnings from spamming every
	# test; test_diagnostics_pathfinder_and_step_climber_telemetry overrides it.
	_colonist.pathfinder.set_walkability(func(_cell: Vector3i) -> bool: return true)


func after_test() -> void:
	_sandbox.restore()


func test_visualizer_initialization() -> void:
	assert_object(_visualizer).is_not_null()
	assert_object(_visualizer._bt_player).is_not_null()
	assert_object(_visualizer._brain).is_not_null()
	assert_object(_visualizer._pathfinder).is_not_null()
	assert_object(_visualizer._step_climber).is_not_null()
	assert_object(_visualizer._label).is_not_null()
	assert_object(_visualizer._immediate_mesh).is_not_null()


func test_resolve_colonist_state_idle_move_work() -> void:
	# IDLE state
	_colonist.bt_player.blackboard.set_var(&"current_goal", &"none")
	assert_str(_visualizer._resolve_colonist_state()).is_equal("IDLE")

	# MOVE state
	_colonist.set_path([Vector3(1, 0, 1), Vector3(2, 0, 2)])
	assert_str(_visualizer._resolve_colonist_state()).is_equal("MOVE (wp 1/2)")

	# WORK state
	_colonist.set_path([])
	_colonist.bt_player.blackboard.set_var(&"current_goal", &"work")
	var job := JobInstance.new()
	job.completed_units = 10
	job.total_units = 50
	_colonist.bt_player.blackboard.set_var(&"active_job", job)
	assert_str(_visualizer._resolve_colonist_state()).is_equal("WORK (10/50)")


func test_resolve_colonist_job() -> void:
	var job := JobInstance.new()
	job.id = "abc12345678"
	job.title = "Dig Trench"
	job.anchor_cell = Vector3i(10, 5, 12)
	_colonist.bt_player.blackboard.set_var(&"active_job", job)

	var job_str := _visualizer._resolve_colonist_job()
	assert_str(job_str).contains("Job: Dig Trench [abc123]")
	assert_str(job_str).contains("Anchor: (10, 5, 12)")


func test_resolve_path_info() -> void:
	_colonist.set_path([Vector3(5, 0, 0), Vector3(10, 0, 0)])
	var info := _visualizer._resolve_path_info()
	assert_str(info).contains("Wp 1/2")
	assert_str(info).contains("Dest:")


func test_draw_navigation_path_and_target_marker() -> void:
	_colonist.set_path([Vector3(5, 0, 0), Vector3(10, 0, 0)])
	_visualizer._draw_navigation_path()
	assert_int(_visualizer._immediate_mesh.get_surface_count()).is_greater(0)


func test_resolve_carried_items() -> void:
	_colonist.inventory.items["wood"] = 3
	_colonist.inventory.items["stone"] = 5
	var carry := _visualizer._resolve_carried_items()
	assert_str(carry).contains("wood x3")
	assert_str(carry).contains("stone x5")


func test_diagnostics_pathfinder_and_step_climber_telemetry() -> void:
	var pf := _colonist.pathfinder
	pf.set_walkability(func(c: Vector3i) -> bool: return c.y == 0)
	var path := pf.find_path(Vector3i(0, 0, 0), Vector3i(2, 0, 0))
	assert_array(path).is_not_empty()
	assert_str(pf.last_status).contains("OK")

	# Test failed query updates diagnostics
	var fail_path := pf.find_path(Vector3i(0, 5, 0), Vector3i(2, 5, 0))
	assert_array(fail_path).is_empty()
	assert_str(pf.last_status).contains("FAIL")

	_visualizer._update_label()
	assert_str(_visualizer._label.text).contains("A*:")


func test_end_job_clears_path_and_wireframes() -> void:
	_colonist.set_path([Vector3(5, 0, 0), Vector3(10, 0, 0)])
	_colonist.set_path([])
	_colonist.pathfinder.clear_diagnostics()

	assert_int(_colonist._path.size()).is_equal(0)
	assert_int(_colonist._path_index).is_equal(0)
	assert_bool(_colonist.pathfinder.last_query_start == Vector3i.MAX).is_true()
	assert_bool(_colonist.pathfinder.last_query_target == Vector3i.MAX).is_true()

	_visualizer._draw_navigation_path()
	assert_int(_visualizer._immediate_mesh.get_surface_count()).is_equal(0)


func test_stale_telemetry_draws_nothing() -> void:
	var pf := _colonist.pathfinder
	pf.set_walkability(func(c: Vector3i) -> bool: return c.y == 0)
	assert_array(pf.find_path(Vector3i(0, 5, 0), Vector3i(2, 5, 0))).is_empty()

	_visualizer._draw_navigation_path()
	assert_int(_visualizer._immediate_mesh.get_surface_count()).is_greater(0)

	pf.last_query_time -= _visualizer._TELEMETRY_TTL_SEC + 1.0
	_visualizer._draw_navigation_path()
	assert_int(_visualizer._immediate_mesh.get_surface_count()).is_equal(0)

	_visualizer._update_label()
	assert_bool(_visualizer._label.text.contains("A*:")).is_false()


func test_debug_billboard_visibility_toggle() -> void:
	_colonist.set_debug_billboard_visible(true)
	assert_bool(_colonist.is_debug_billboard_visible()).is_true()
	assert_bool(_visualizer.is_billboard_visible()).is_true()
	assert_bool(_visualizer._label.visible).is_true()

	_colonist.set_path([Vector3(5, 0, 0), Vector3(10, 0, 0)])
	_visualizer._draw_navigation_path()
	assert_int(_visualizer._immediate_mesh.get_surface_count()).is_greater(0)

	_colonist.set_debug_billboard_visible(false)
	assert_bool(_colonist.is_debug_billboard_visible()).is_false()
	assert_bool(_visualizer.is_billboard_visible()).is_false()
	assert_bool(_visualizer._label.visible).is_false()
	assert_int(_visualizer._immediate_mesh.get_surface_count()).is_equal(0)

	_visualizer._process(0.016)
	assert_int(_visualizer._immediate_mesh.get_surface_count()).is_equal(0)

	_colonist.set_debug_billboard_visible(true)
	assert_bool(_colonist.is_debug_billboard_visible()).is_true()
	assert_bool(_visualizer.is_billboard_visible()).is_true()
	assert_bool(_visualizer._label.visible).is_true()


func test_freed_smart_object_does_not_crash_visualizer() -> void:
	var temp_node := Node3D.new()
	add_child(temp_node)
	_colonist.bt_player.blackboard.set_var(&"target_smart_object", temp_node)

	# Free the target node while the blackboard still references it
	temp_node.free()

	# Must not raise "Left operand of 'is' is a previously freed instance".
	# The colonist has no path, so a crash-free draw leaves the wireframe mesh
	# empty — a stronger check than merely surviving the calls.
	_visualizer._draw_navigation_path()
	_visualizer._process(0.016)
	assert_int(_visualizer._immediate_mesh.get_surface_count()).is_equal(0)
