extends GdUnitTestSuite

## Unit tests for Squad Management and Tactical Deployments (Phase 1).

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
var _sandbox: ColonySandbox


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)
	Colony.squads.clear()
	Colony.colonists.clear()


func after_test() -> void:
	Colony.squads.clear()
	Colony.colonists.clear()
	_sandbox.restore()


func _make_test_colonist() -> Colonist:
	var c := _sandbox.make_colonist()
	Colony.add_colonist(c)
	return c


# ── Squad Management ──────────────────────────────────────────────────────────

func test_squad_lifecycle_and_assignment() -> void:
	var c1 := _make_test_colonist()
	var c2 := _make_test_colonist()

	Colony.create_squad("alpha")
	assert_array(Colony.get_squad_members("alpha")).is_empty()

	Colony.assign_to_squad(c1.colonist_id, "alpha")
	Colony.assign_to_squad(c2.colonist_id, "alpha")

	assert_int(Colony.get_squad_members("alpha").size()).is_equal(2)
	assert_str(c1.squad_id).is_equal("alpha")
	assert_str(c2.squad_id).is_equal("alpha")
	assert_str(Colony.get_squad_for_colonist(c1.colonist_id)).is_equal("alpha")

	# Reassign c1 to bravo
	Colony.assign_to_squad(c1.colonist_id, "bravo")
	assert_str(c1.squad_id).is_equal("bravo")
	assert_int(Colony.get_squad_members("alpha").size()).is_equal(1)
	assert_int(Colony.get_squad_members("bravo").size()).is_equal(1)

	# Remove c2 from alpha
	Colony.remove_from_squad(c2.colonist_id)
	assert_str(c2.squad_id).is_equal("")
	assert_array(Colony.get_squad_members("alpha")).is_empty()

	# Delete squad bravo
	Colony.delete_squad("bravo")
	assert_str(c1.squad_id).is_equal("")
	assert_bool(Colony.squads.has("bravo")).is_false()


# ── Tactical Deployments ──────────────────────────────────────────────────────

func test_deploy_colonist_creates_targeted_job() -> void:
	var c1 := _make_test_colonist()
	var c2 := _make_test_colonist()

	var target_pos := Vector3(15.0, 1.0, 20.0)
	var job := Colony.deploy_colonist(c1.colonist_id, target_pos)

	assert_object(job).is_not_null()
	assert_str(job.target_colonist_id).is_equal(c1.colonist_id)
	assert_vector(job.location).is_equal(target_pos)

	assert_bool(Colony.has_active_deployment(c1.colonist_id)).is_true()
	assert_bool(Colony.has_active_deployment(c2.colonist_id)).is_false()

	# JobBoard selection restricts to target colonist
	var best_c1 = Colony.job_board.get_best_job_for(c1)
	assert_object(best_c1).is_equal(job)

	var best_c2 = Colony.job_board.get_best_job_for(c2)
	assert_object(best_c2).is_null()


func test_deploy_job_claim_and_completion_behavior() -> void:
	var c1 := _make_test_colonist()
	var c2 := _make_test_colonist()

	var job := Colony.deploy_colonist(c1.colonist_id, Vector3(5, 0, 5))

	# c2 cannot assign to c1's deploy job
	assert_bool(job.try_assign(c2)).is_false()

	# c1 can assign
	assert_bool(job.try_assign(c1)).is_true()

	# DeployJob complete() should NOT remove job from board (persistent stationing)
	job.def.complete(c1, job)
	assert_bool(job.should_close()).is_false()
	assert_bool(Colony.has_active_deployment(c1.colonist_id)).is_true()


func test_cancel_deployment() -> void:
	var c1 := _make_test_colonist()
	Colony.deploy_colonist(c1.colonist_id, Vector3(5, 0, 5))
	assert_bool(Colony.has_active_deployment(c1.colonist_id)).is_true()

	Colony.cancel_deployments([c1.colonist_id])
	assert_bool(Colony.has_active_deployment(c1.colonist_id)).is_false()
	assert_object(Colony.job_board.get_best_job_for(c1)).is_null()


func test_deploy_and_cancel_squad() -> void:
	var c1 := _make_test_colonist()
	var c2 := _make_test_colonist()

	Colony.assign_to_squad(c1.colonist_id, "strike_team")
	Colony.assign_to_squad(c2.colonist_id, "strike_team")

	var targets := {
		c1.colonist_id: Vector3(10, 0, 10),
		c2.colonist_id: Vector3(12, 0, 10)
	}
	Colony.deploy_squad("strike_team", targets)

	assert_bool(Colony.has_active_deployment(c1.colonist_id)).is_true()
	assert_bool(Colony.has_active_deployment(c2.colonist_id)).is_true()
	assert_vector(Colony.get_active_deployment_position(c1.colonist_id)).is_equal(Vector3(10, 0, 10))
	assert_vector(Colony.get_active_deployment_position(c2.colonist_id)).is_equal(Vector3(12, 0, 10))

	Colony.cancel_squad_deployment("strike_team")
	assert_bool(Colony.has_active_deployment(c1.colonist_id)).is_false()
	assert_bool(Colony.has_active_deployment(c2.colonist_id)).is_false()


# ── Persistence / Serialization ───────────────────────────────────────────────

func test_squad_serialization_round_trip() -> void:
	var c1 := _make_test_colonist()
	var c2 := _make_test_colonist()

	Colony.assign_to_squad(c1.colonist_id, "alpha")
	Colony.assign_to_squad(c2.colonist_id, "beta")

	# Colonist serialize/deserialize
	var c1_data := c1.serialize()
	assert_str(c1_data.get("squad_id", "")).is_equal("alpha")

	var c1_restored := _sandbox.make_colonist()
	c1_restored.deserialize(c1_data)
	assert_str(c1_restored.squad_id).is_equal("alpha")

	# Colony serialize/deserialize
	var colony_data := Colony.serialize()
	assert_bool(colony_data.has("squads")).is_true()

	Colony.squads.clear()
	Colony.deserialize(colony_data)

	assert_int(Colony.squads.size()).is_equal(2)
	assert_array(Colony.get_squad_members("alpha")).contains([c1.colonist_id])
	assert_array(Colony.get_squad_members("beta")).contains([c2.colonist_id])
