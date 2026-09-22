extends GdUnitTestSuite

## Unit tests for the recreation subsystem (ARCH recreation.md): RecreationParams
## capacity math, RecreationComponent slot rationing, the availability-filtered
## smart-object search, ColonistBrain reservation handover, and the
## BTActionUseRecreation session lifecycle.
##
## Content-agnostic per AGENTS.md: every FurnitureDef, RecreationParams and NeedDef
## used here is built in memory. Nothing asserts against data/furniture/*.tres or
## data/needs/*.tres, whose balance values are expected to move.

const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

const BTActionUseRecreationScript = preload("res://subsystems/ai/tasks/actions/bt_action_use_recreation.gd")
const BTTreeFactoryScript = preload("res://subsystems/ai/bt_tree_factory.gd")
const ColonistNeedsScript = preload("res://subsystems/ai/colonist_needs.gd")
const ColonistBrainScript = preload("res://subsystems/ai/colonist_brain.gd")
const NeedDefScript = preload("res://data/schemas/need_def.gd")

const TEST_NEED: StringName = &"recreation"

var _sandbox: ColonySandbox
var _blackboard: Blackboard
var _original_loop_length: float


func before_test() -> void:
	_original_loop_length = TimeSystem._loop_length_seconds
	TimeSystem._loop_length_seconds = TimeSystem.HOURS_PER_DAY

	_sandbox = ColonySandbox.new(self)
	_blackboard = Blackboard.new()
	ColonistNeeds._defs_loaded = false
	ColonistNeeds._cached_need_defs.clear()


func after_test() -> void:
	TimeSystem._loop_length_seconds = _original_loop_length
	_sandbox.restore()
	ColonistNeeds._defs_loaded = false
	ColonistNeeds._cached_need_defs.clear()


# ── RecreationParams ─────────────────────────────────────────────────────────

func test_effective_capacity_without_offsets_is_the_authored_capacity() -> void:
	var params := _make_params(1)
	assert_int(params.effective_capacity()).is_equal(1)

	params.capacity = -1
	assert_int(params.effective_capacity()).is_equal(-1)


func test_authored_offsets_cap_the_effective_capacity() -> void:
	var params := _make_params(4)
	params.use_offsets = [Vector3(0, 0, 1), Vector3(1, 0, 1)]
	assert_int(params.effective_capacity()).is_equal(2)


func test_offsets_bound_an_otherwise_unlimited_capacity() -> void:
	var params := _make_params(-1)
	params.use_offsets = [Vector3(0, 0, 1)]
	assert_int(params.effective_capacity()).is_equal(1)


func test_session_ceiling_never_falls_below_the_floor() -> void:
	var params := _make_params(1)
	params.min_session_game_hours = 8.0
	params.max_session_game_hours = 2.0
	assert_float(params.session_ceiling_game_hours()).is_equal_approx(8.0, 0.001)


# ── FurnitureLayer capability wiring ─────────────────────────────────────────

func test_furniture_layer_attaches_recreation_component_when_params_present() -> void:
	var layer: FurnitureLayer = auto_free(FurnitureLayer.new())
	layer.set_container(_sandbox.container)

	var params := _make_params(2)
	var def := _make_def(params)
	var node: Furniture = layer.spawn(def, Vector3i(0, 0, 0), 0)

	var comp := node.get_node_or_null("RecreationComponent") as RecreationComponent
	assert_object(comp).is_not_null()
	assert_object(comp.params()).is_equal(params)
	assert_int(comp.capacity()).is_equal(2)


# ── RecreationComponent occupancy ────────────────────────────────────────────

func test_exclusive_object_admits_one_colonist_and_rejects_the_next() -> void:
	var comp := _make_recreation_furniture(_make_params(1))
	var first := _make_user()
	var second := _make_user()

	assert_bool(comp.reserve(first)).is_true()
	assert_bool(comp.is_usable_by(second)).is_false()
	assert_bool(comp.reserve(second)).is_false()


func test_holder_still_sees_the_object_as_usable() -> void:
	# Load-bearing: ColonistBrain re-scores its own current target every cycle. A
	# component that reported "full" to its own occupant would zero that goal's
	# score and make the colonist thrash between goals.
	var comp := _make_recreation_furniture(_make_params(1))
	var user := _make_user()

	assert_bool(comp.reserve(user)).is_true()
	assert_bool(comp.is_usable_by(user)).is_true()
	assert_bool(comp.reserve(user)).is_true()


func test_unlimited_capacity_never_rejects() -> void:
	var comp := _make_recreation_furniture(_make_params(-1))
	for i in range(5):
		assert_bool(comp.reserve(_make_user())).is_true()


func test_release_frees_a_slot_for_another_colonist() -> void:
	var comp := _make_recreation_furniture(_make_params(1))
	var first := _make_user()
	var second := _make_user()

	comp.reserve(first)
	comp.release(first)

	assert_bool(comp.is_usable_by(second)).is_true()
	assert_bool(comp.reserve(second)).is_true()


func test_begin_use_promotes_a_reservation_and_end_use_frees_it() -> void:
	var comp := _make_recreation_furniture(_make_params(1))
	var user := _make_user()

	comp.reserve(user)
	assert_bool(comp.begin_use(user)).is_true()
	assert_bool(comp.holds_slot(user)).is_true()

	comp.end_use(user)
	assert_bool(comp.holds_slot(user)).is_false()


func test_arrival_cannot_overfill_an_object_whose_slots_were_taken() -> void:
	var comp := _make_recreation_furniture(_make_params(1))
	var walker := _make_user()
	var squatter := _make_user()

	comp.reserve(squatter)
	comp.begin_use(squatter)

	assert_bool(comp.begin_use(walker)).is_false()


func test_use_position_defaults_to_the_furniture_origin() -> void:
	var comp := _make_recreation_furniture(_make_params(1))
	var furniture := comp.get_parent() as Node3D
	furniture.global_position = Vector3(3.0, 1.0, 4.0)

	assert_vector(comp.use_position_for(_make_user())).is_equal_approx(Vector3(3.0, 1.0, 4.0), Vector3.ONE * 0.01)


func test_authored_offset_is_rotated_by_the_furniture_transform() -> void:
	var params := _make_params(1)
	params.use_offsets = [Vector3(0, 0, 1)]
	var comp := _make_recreation_furniture(params)
	var furniture := comp.get_parent() as Node3D
	furniture.global_position = Vector3(2.0, 0.0, 2.0)
	furniture.rotation_degrees = Vector3(0.0, 90.0, 0.0)

	# +Z local becomes +X world at 90 degrees of yaw.
	assert_vector(comp.use_position_for(_make_user())).is_equal_approx(Vector3(3.0, 0.0, 2.0), Vector3.ONE * 0.01)


# ── AIUtils availability filter ──────────────────────────────────────────────

func test_group_search_skips_objects_that_refuse_the_colonist() -> void:
	var group: StringName = &"test_occupiable_group"
	var user := _make_user()

	# A capacity-0 object refuses everyone; the far one is the only valid answer.
	var near := _make_recreation_furniture(_make_params(0), group)
	(near.get_parent() as Node3D).global_position = Vector3(1.0, 0.0, 0.0)
	var far := _make_recreation_furniture(_make_params(1), group)
	(far.get_parent() as Node3D).global_position = Vector3(20.0, 0.0, 0.0)

	var found: Node3D = AIUtils.find_nearest_in_group_where(
		get_tree(), group, Vector3.ZERO,
		func(node: Node3D) -> bool: return _node_is_usable_by(node, user)
	)
	assert_object(found).is_equal(far.get_parent())


# ── ColonistBrain reservation handover ───────────────────────────────────────

func test_brain_skips_a_fully_occupied_recreation_object() -> void:
	var group := RecreationComponent.REQUIRED_GROUP
	var occupied := _make_recreation_furniture(_make_params(1), group)
	(occupied.get_parent() as Node3D).global_position = Vector3(2.0, 0.0, 0.0)
	occupied.reserve(_make_user())

	var brain := _install_brain_with_need(group)
	brain.evaluate_goals()

	# The only candidate is full, so the need is unfulfillable and scores 0.0 —
	# the brain falls back to work rather than sending a second colonist over.
	assert_str(String(brain.bt_player.blackboard.get_var(&"current_goal"))).is_equal("work")
	assert_object(brain.bt_player.blackboard.get_var(&"target_smart_object")).is_null()


func test_brain_reserves_the_winning_target_and_publishes_a_stand_position() -> void:
	var group := RecreationComponent.REQUIRED_GROUP
	var comp := _make_recreation_furniture(_make_params(1), group)
	var furniture := comp.get_parent() as Node3D
	furniture.global_position = Vector3(2.0, 0.0, 0.0)

	var brain := _install_brain_with_need(group)
	brain.evaluate_goals()

	assert_str(String(brain.bt_player.blackboard.get_var(&"current_goal"))).is_equal(String(TEST_NEED))
	assert_object(brain.bt_player.blackboard.get_var(&"target_smart_object")).is_equal(furniture)
	assert_bool(comp.holds_slot(brain.get_parent())).is_true()

	var stand_pos: Variant = brain.bt_player.blackboard.get_var(&"target_stand_pos")
	assert_bool(stand_pos is Vector3).is_true()
	assert_vector(stand_pos as Vector3).is_equal_approx(Vector3(2.0, 0.0, 0.0), Vector3.ONE * 0.01)


func test_brain_releases_its_claim_when_it_leaves_the_tree() -> void:
	var group := RecreationComponent.REQUIRED_GROUP
	var comp := _make_recreation_furniture(_make_params(1), group)
	(comp.get_parent() as Node3D).global_position = Vector3(2.0, 0.0, 0.0)

	var brain := _install_brain_with_need(group)
	brain.evaluate_goals()
	var colonist := brain.get_parent()
	assert_bool(comp.holds_slot(colonist)).is_true()

	colonist.remove_child(brain)
	assert_bool(comp.holds_slot(colonist)).is_false()


# ── BTActionUseRecreation ────────────────────────────────────────────────────

func test_session_accrues_the_need_at_the_authored_rate() -> void:
	var params := _make_params(1)
	params.recreation_per_game_hour = 0.1
	params.min_session_game_hours = 10.0
	var ctx := _make_session(params, 0.0)

	assert_int(ctx.task.execute(1.0)).is_equal(BTAction.RUNNING)
	assert_float(ctx.colonist.needs.get_need(TEST_NEED)).is_equal_approx(0.1, 0.01)

	assert_int(ctx.task.execute(1.0)).is_equal(BTAction.RUNNING)
	assert_float(ctx.colonist.needs.get_need(TEST_NEED)).is_equal_approx(0.2, 0.01)


func test_session_holds_the_colonist_for_the_authored_minimum() -> void:
	var params := _make_params(1)
	params.recreation_per_game_hour = 1.0
	params.min_session_game_hours = 3.0
	var ctx := _make_session(params, 0.9)

	# The need tops out on the first tick, but the commitment floor keeps the
	# colonist in place instead of producing a visible one-frame twitch.
	assert_int(ctx.task.execute(1.0)).is_equal(BTAction.RUNNING)
	assert_float(ctx.colonist.needs.get_need(TEST_NEED)).is_equal_approx(1.0, 0.01)
	assert_int(ctx.task.execute(1.0)).is_equal(BTAction.RUNNING)
	assert_int(ctx.task.execute(1.5)).is_equal(BTAction.SUCCESS)


func test_session_hard_stops_at_the_ceiling_with_the_need_unfilled() -> void:
	var params := _make_params(1)
	params.recreation_per_game_hour = 0.01
	params.min_session_game_hours = 1.0
	params.max_session_game_hours = 3.0
	var ctx := _make_session(params, 0.0)

	assert_int(ctx.task.execute(2.0)).is_equal(BTAction.RUNNING)
	assert_int(ctx.task.execute(1.5)).is_equal(BTAction.SUCCESS)
	assert_float(ctx.colonist.needs.get_need(TEST_NEED)).is_less(1.0)


func test_successful_session_clears_the_goal_for_re_arbitration() -> void:
	var params := _make_params(1)
	params.recreation_per_game_hour = 1.0
	params.min_session_game_hours = 0.5
	var ctx := _make_session(params, 0.0)

	assert_int(ctx.task.execute(1.0)).is_equal(BTAction.SUCCESS)
	assert_str(String(_blackboard.get_var(&"current_goal"))).is_equal("none")
	assert_object(_blackboard.get_var(&"target_smart_object")).is_null()
	assert_object(_blackboard.get_var(&"target_stand_pos")).is_null()


func test_session_fails_when_the_colonist_is_outside_the_use_radius() -> void:
	var params := _make_params(1)
	params.use_radius = 1.5
	var ctx := _make_session(params, 0.0)
	ctx.colonist.global_position = Vector3(20.0, 0.0, 0.0)

	assert_int(ctx.task.execute(0.1)).is_equal(BTAction.FAILURE)


func test_interrupted_session_releases_the_slot() -> void:
	# A leaked slot would permanently shrink the colony's usable furniture, so
	# _exit must free it on the failure path too, not just on success.
	var params := _make_params(1)
	params.recreation_per_game_hour = 0.01
	params.min_session_game_hours = 60.0
	var ctx := _make_session(params, 0.0)

	assert_int(ctx.task.execute(0.5)).is_equal(BTAction.RUNNING)
	assert_bool(ctx.component.holds_slot(ctx.colonist)).is_true()

	ctx.colonist.global_position = Vector3(20.0, 0.0, 0.0)
	assert_int(ctx.task.execute(0.1)).is_equal(BTAction.FAILURE)
	assert_bool(ctx.component.holds_slot(ctx.colonist)).is_false()


# ── Tree wiring parity ───────────────────────────────────────────────────────

func test_tree_factory_emits_goal_gated_sleep_and_recreation_branches() -> void:
	# Guards the landmine in suite_ai_tasks_test: that suite re-saves
	# colonist_root.tres from this factory, so a branch missing here is silently
	# deleted from the shipped tree on the next test run.
	var tree: BehaviorTree = BTTreeFactoryScript.create_colonist_root_tree()
	var root: BTDynamicSelector = tree.root_task as BTDynamicSelector
	assert_object(root).is_not_null()

	assert_object(_find_goal_gated_branch(root, &"sleep")).is_not_null()
	var rec_branch := _find_goal_gated_branch(root, TEST_NEED)
	assert_object(rec_branch).is_not_null()
	assert_bool(rec_branch.children[2] is BTActionUseRecreation).is_true()


# ===================
# Auxiliary Functions
# ===================

func _make_params(capacity: int) -> RecreationParams:
	## Auxiliary: In-memory capability params with predictable timings.
	var params: RecreationParams = auto_free(RecreationParams.new())
	params.capacity = capacity
	params.recreation_per_game_hour = 0.1
	params.min_session_game_hours = 1.0
	params.max_session_game_hours = 5.0
	params.use_radius = 1.5
	return params


func _make_def(params: RecreationParams, group: StringName = RecreationComponent.REQUIRED_GROUP) -> FurnitureDef:
	## Auxiliary: Throwaway FurnitureDef carrying the capability and its tag.
	var def: FurnitureDef = auto_free(FurnitureDef.new())
	def.id = "test_recreation_object"
	def.dimensions = Vector3i.ONE
	def.mesh = BoxMesh.new()
	# Always carries the required tag so the component's authoring warning stays
	# quiet; suites that search an isolated group get that one appended.
	def.tags = [String(RecreationComponent.REQUIRED_GROUP)]
	if group != RecreationComponent.REQUIRED_GROUP:
		def.tags.append(String(group))
	def.recreation_params = params
	return def


func _make_recreation_furniture(
		params: RecreationParams,
		group: StringName = RecreationComponent.REQUIRED_GROUP
) -> RecreationComponent:
	## Auxiliary: Builds a Furniture + RecreationComponent pair and returns the
	## component. def/def_id are assigned before add_child so Furniture._ready
	## registers the tag group.
	var def := _make_def(params, group)
	var node: Furniture = auto_free(Furniture.new())
	node.def = def
	node.def_id = def.id
	var comp := RecreationComponent.new()
	comp.name = "RecreationComponent"
	node.add_child(comp)
	add_child(node)
	return comp


func _make_user() -> Node3D:
	## Auxiliary: A stand-in claimant. Occupancy only needs node identity.
	var user: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(user)
	return user


func _node_is_usable_by(node: Node, user: Node) -> bool:
	## Auxiliary: Mirrors ColonistBrain's IOccupiable probe for the AIUtils test.
	for child in node.get_children():
		if child.has_method(&"is_usable_by"):
			return bool(child.call(&"is_usable_by", user))
	return true


func _install_brain_with_need(target_group: StringName) -> ColonistBrain:
	## Auxiliary: Stands up a colonist-shaped node with a fully depleted synthetic
	## need pointed at target_group, so arbitration has exactly one thing to want.
	ColonistNeeds._cached_need_defs.clear()
	ColonistNeeds._defs_loaded = true

	var mock_def: Resource = auto_free(NeedDefScript.new()) as Resource
	mock_def.id = TEST_NEED
	mock_def.goal_name = TEST_NEED
	mock_def.target_group = target_group
	mock_def.decay_per_game_hour = 0.0
	var curve: Curve = Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(1, 1))
	mock_def.response_curve = curve
	ColonistNeeds._cached_need_defs[TEST_NEED] = mock_def

	var colonist: Node3D = auto_free(Node3D.new()) as Node3D
	add_child(colonist)

	var needs: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	needs.name = "ColonistNeeds"
	colonist.add_child(needs)

	# auto_free covers the detach case in the _exit_tree release test, where the
	# brain is deliberately removed from its parent and would otherwise leak.
	var brain: ColonistBrain = auto_free(ColonistBrainScript.new()) as ColonistBrain
	var bt_player: BTPlayer = auto_free(BTPlayer.new()) as BTPlayer
	bt_player.blackboard = Blackboard.new()
	brain.bt_player = bt_player
	colonist.add_child(brain)
	brain._ready()

	needs.set_need(TEST_NEED, 0.0)
	return brain


func _make_session(params: RecreationParams, starting_need: float) -> Dictionary:
	## Auxiliary: Places a real colonist adjacent to a recreation object, reserves
	## a slot, and enters BTActionUseRecreation — the state every session test
	## starts from.
	var comp := _make_recreation_furniture(params)
	var furniture := comp.get_parent() as Node3D
	furniture.global_position = Vector3.ZERO

	var colonist: Colonist = _sandbox.make_colonist()
	colonist.global_position = Vector3(0.5, 0.0, 0.0)
	colonist.needs.set_need(TEST_NEED, starting_need)
	comp.reserve(colonist)

	var task: BTAction = auto_free(BTActionUseRecreationScript.new()) as BTAction
	task.need_id = TEST_NEED
	_blackboard.set_var(&"current_goal", TEST_NEED)
	_blackboard.set_var(&"target_smart_object", furniture)
	_blackboard.set_var(&"target_stand_pos", furniture.global_position)
	task.initialize(colonist, _blackboard, colonist)

	return {"task": task, "colonist": colonist, "component": comp}


func _find_goal_gated_branch(root: BTDynamicSelector, expected_goal: StringName) -> BTSequence:
	## Auxiliary: Returns the branch whose first child gates on expected_goal.
	for child in root.children:
		var seq := child as BTSequence
		if seq == null or seq.children.is_empty():
			continue
		var guard := seq.children[0] as BTConditionGoalIs
		if guard != null and guard.expected_goal == expected_goal:
			return seq
	return null
