extends GdUnitTestSuite

## Colonists look at their work and combat targets: ColonistAnimationController's
## look target (facing + LookLean pitch) and BTActionPerformWork's target choice
## (docs/architecture/colonists.md, "Look at Work and Combat Targets").
## Content-agnostic: jobs and targets are built in memory.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")
const ColonistScene = preload("res://subsystems/colonists/colonist.tscn")
const BTActionPerformWorkScript = preload("res://subsystems/ai/tasks/actions/bt_action_perform_work.gd")

const EPSILON := Vector3(0.001, 0.001, 0.001)

var _sandbox: ColonySandbox
var _blackboard: Blackboard


func before_test() -> void:
	_sandbox = ColonySandbox.new(self)
	_blackboard = Blackboard.new()


func after_test() -> void:
	_sandbox.restore()


# ── ColonistAnimationController ─────────────────────────────────────────────

## A point above the aim origin leans the head back; below leans it forward.
func test_look_point_leans_toward_its_height() -> void:
	var colonist := _sandbox.make_colonist()
	var ctrl := _controller(colonist)
	var lean := ctrl.look_lean
	assert_bool(lean.is_bound()).is_true()

	var skel := lean._skeleton
	var baseline_chest := skel.get_bone_pose_rotation(lean._chest_bone_idx)
	var baseline_head := skel.get_bone_pose_rotation(lean._head_bone_idx)
	var ahead := colonist.get_aim_origin() + ctrl.visuals.global_transform.basis.z.normalized() * 2.0

	var level := _head_forward_offset_looking_at(colonist, ahead, baseline_chest, baseline_head)
	var above := _head_forward_offset_looking_at(colonist, ahead + Vector3.UP * 2.0, baseline_chest, baseline_head)
	var below := _head_forward_offset_looking_at(colonist, ahead + Vector3.DOWN * 2.0, baseline_chest, baseline_head)

	assert_float(above).is_less(level)
	assert_float(below).is_greater(level)


## A node target is looked at through its mesh center, and tracked when it moves.
func test_look_target_tracks_mesh_center_mass() -> void:
	var colonist := _sandbox.make_colonist()
	var ctrl := _controller(colonist)
	var target := _make_mesh_target(Vector3(3.0, 0.0, 0.0), Vector3(0.0, 2.5, 0.0))

	ctrl.set_look_target(target)
	assert_vector(ctrl._resolve_look_point()).is_equal_approx(Vector3(3.0, 2.5, 0.0), EPSILON)

	target.global_position = Vector3(4.0, 0.0, 1.0)
	assert_vector(ctrl._resolve_look_point()).is_equal_approx(Vector3(4.0, 2.5, 1.0), EPSILON)


## Clearing the look target eases the lean back to level.
func test_clearing_look_target_eases_back_to_level() -> void:
	var colonist := _sandbox.make_colonist()
	var ctrl := _controller(colonist)
	var lean := ctrl.look_lean
	var ahead := colonist.get_aim_origin() + ctrl.visuals.global_transform.basis.z.normalized()

	# A long delta fully converges the easing in one frame.
	ctrl.set_look_point(ahead + Vector3.UP)
	ctrl._process(10.0)
	assert_float(rad_to_deg(lean._smoothed_pitch)).is_equal_approx(minf(45.0, lean.max_up_deg), 0.01)

	ctrl.clear_look_target()
	ctrl._process(10.0)
	assert_float(lean._smoothed_pitch).is_equal_approx(0.0, 0.0001)


func test_freed_look_target_clears_itself() -> void:
	var colonist := _sandbox.make_colonist()
	var ctrl := _controller(colonist)
	var target := Node3D.new()
	_sandbox.container.add_child(target)

	ctrl.set_look_target(target)
	target.free()

	assert_that(ctrl._resolve_look_point()).is_null()
	assert_that(ctrl._look_target).is_null()


## Regression guard for the process ordering: with the controller moved ahead of
## the AnimationTree in the scene, only its process_priority keeps the lean
## landing after the tree. At skeleton_updated the Chest must sit its share of
## the applied lean away from the pose the tree wrote.
func test_look_lean_reaches_skinning_after_animation() -> void:
	var colonist: Colonist = ColonistScene.instantiate()
	colonist.move_child(colonist.get_node("ColonistAnimationController"), colonist.get_node("AnimationTree").get_index())
	auto_free(colonist)
	_sandbox.container.add_child(colonist)

	var ctrl := _controller(colonist)
	var lean := ctrl.look_lean
	var skel := lean._skeleton
	var animated_chest: Array[Quaternion] = [Quaternion.IDENTITY]
	var skinned_chest: Array[Quaternion] = [Quaternion.IDENTITY]
	ctrl.anim_tree.mixer_applied.connect(func() -> void:
		animated_chest[0] = skel.get_bone_pose_rotation(lean._chest_bone_idx))
	skel.skeleton_updated.connect(func() -> void:
		skinned_chest[0] = skel.get_bone_pose_rotation(lean._chest_bone_idx))

	var ahead := colonist.get_aim_origin() + ctrl.visuals.global_transform.basis.z.normalized()
	ctrl.set_look_point(ahead + Vector3.UP * tan(deg_to_rad(30.0)))
	lean._smoothed_pitch = deg_to_rad(30.0)
	for _i in range(3):
		await get_tree().process_frame

	# Awaiting process_frame resumes before this frame's _process, so the eased
	# pitch and the recorded poses both belong to the previous frame.
	var expected_deg := rad_to_deg(absf(lean._smoothed_pitch)) * lean.chest_share
	assert_float(expected_deg).is_greater(10.0)
	assert_float(rad_to_deg(skinned_chest[0].angle_to(animated_chest[0]))).is_equal_approx(expected_deg, 0.5)


# ── BTActionPerformWork look target ─────────────────────────────────────────

func test_work_on_node_target_looks_at_it_until_exit() -> void:
	var colonist := _sandbox.make_colonist()
	var target := _make_mesh_target(Vector3(2.0, 0.0, 0.0), Vector3(0.0, 0.5, 0.0))
	var task := _start_work(colonist, _make_job(JobDef.new(), target))

	assert_object(_controller(colonist)._look_target).is_same(target)
	task.abort()
	assert_that(_controller(colonist)._look_target).is_null()


func test_work_on_component_target_looks_at_its_parent() -> void:
	var colonist := _sandbox.make_colonist()
	var furniture := _make_mesh_target(Vector3(2.0, 0.0, 0.0), Vector3(0.0, 0.5, 0.0))
	var component := Node.new()
	furniture.add_child(component)
	_start_work(colonist, _make_job(JobDef.new(), component))

	assert_object(_controller(colonist)._look_target).is_same(furniture)


func test_work_without_node_looks_at_job_location() -> void:
	var colonist := _sandbox.make_colonist()
	var job := _make_job(JobDef.new(), null)
	job.location = Vector3(2.5, 0.5, 0.5)
	_start_work(colonist, job)

	var ctrl := _controller(colonist)
	assert_bool(ctrl._has_look_point).is_true()
	assert_vector(ctrl._look_point).is_equal_approx(Vector3(2.5, 0.5, 0.5), EPSILON)


## Multi-site legs report only a floor position: face it level, even when the
## job also names a (different) final target node.
func test_work_on_multi_site_leg_faces_site_at_aim_height() -> void:
	var colonist := _sandbox.make_colonist()
	var def := StubSiteJobDef.new()
	def.site = Vector3(3.0, 0.0, -1.0)
	var elsewhere := _make_mesh_target(Vector3(-5.0, 0.0, 0.0), Vector3.ZERO)
	_start_work(colonist, _make_job(def, elsewhere))

	var ctrl := _controller(colonist)
	assert_bool(ctrl._has_look_point).is_true()
	var aim_y := colonist.get_aim_origin().y
	assert_vector(ctrl._look_point).is_equal_approx(Vector3(3.0, aim_y, -1.0), EPSILON)


# ── Helpers ─────────────────────────────────────────────────────────────────

class StubSiteJobDef extends JobDef:
	var site: Vector3 = Vector3.ZERO

	func work_site(_actor: Node, _job: Variant) -> Variant:
		return site


## Auxiliary: The colonist's animation controller
func _controller(colonist: Colonist) -> ColonistAnimationController:
	return colonist.get_node("ColonistAnimationController") as ColonistAnimationController


## Auxiliary: A Node3D at pos carrying a unit box mesh at a local offset
func _make_mesh_target(pos: Vector3, mesh_offset: Vector3) -> Node3D:
	var target: Node3D = auto_free(Node3D.new())
	_sandbox.container.add_child(target)
	target.global_position = pos
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = BoxMesh.new()
	target.add_child(mesh_node)
	mesh_node.position = mesh_offset
	return target


## Auxiliary: A long-running job on def targeting node (or no node)
func _make_job(def: JobDef, node: Node) -> Job:
	def.work_duration = 5.0
	var job := Job.new()
	job.def = def
	job.target_node = node
	return job


## Auxiliary: Runs PerformWork's first tick on job so its _enter has chosen a look target
func _start_work(colonist: Colonist, job: Job) -> BTAction:
	_blackboard.set_var(&"active_job", job)
	var task: BTAction = auto_free(BTActionPerformWorkScript.new()) as BTAction
	task.initialize(colonist, _blackboard, colonist)
	assert_int(task.execute(0.1)).is_equal(BTAction.RUNNING)
	return task


## Auxiliary: Resets Chest/Head, looks at point with a converged lean, and returns
## how far the head sits ahead of the hips along the model's facing.
func _head_forward_offset_looking_at(colonist: Colonist, point: Vector3, baseline_chest: Quaternion, baseline_head: Quaternion) -> float:
	var ctrl := _controller(colonist)
	var skel := ctrl.look_lean._skeleton
	skel.set_bone_pose_rotation(ctrl.look_lean._chest_bone_idx, baseline_chest)
	skel.set_bone_pose_rotation(ctrl.look_lean._head_bone_idx, baseline_head)
	ctrl.set_look_point(point)
	# A long delta fully converges the easing; the point lies straight ahead, so facing doesn't turn.
	ctrl._process(10.0)
	var head_world := skel.global_transform * skel.get_bone_global_pose(ctrl.look_lean._head_bone_idx).origin
	var hips_world := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Hips")).origin
	return (head_world - hips_world).dot(ctrl.visuals.global_transform.basis.z.normalized())
