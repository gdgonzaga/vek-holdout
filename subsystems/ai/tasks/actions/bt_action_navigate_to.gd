## Subsystem: AI Tasks
## Moves the agent towards a target position, node, job, claim, or group using VoxelPathfinder.
@tool
class_name BTActionNavigateTo
extends BTAction

## Blackboard variable storing the target (Vector3, Vector3i, Node3D, Job, Claim, or Group StringName)
@export var target_var: StringName = &"target_pos"

## Distance to target required to consider arrival successful
@export var arrival_distance: float = 1.8

var _target_world_pos: Vector3 = Vector3.ZERO
var _has_target_pos: bool = false
var _has_valid_target: bool = false
## True when _enter resolved no target at all (expected no-op — do NOT call
## _handle_navigation_failure in this case, or it will erase active_job for
## other subtrees sharing the same blackboard).
var _no_target: bool = false
var _requires_adjacent: bool = true
## Meta key on the agent holding the instance id of the NavigateTo/Wander task
## that most recently fed it a path. The agent's path is a single shared slot
## and several task instances (needs branch, work branch, wander) can set it;
## without ownership a failing sibling's _exit wiped the active path every
## tick, which degenerated into claim -> wipe -> has_arrived() -> instant
## "arrive" while the colonist never moved.
const _PATH_OWNER_META := &"bt_nav_path_owner"


func _generate_name() -> String:
	return "Navigate To  target: %s (dist <= %.1f)" % [
		LimboUtility.decorate_var(target_var),
		arrival_distance
	]


func _enter() -> void:
	_has_valid_target = false
	_has_target_pos = false
	_target_world_pos = Vector3.ZERO
	_no_target = false

	if not agent or not blackboard:
		return

	# The task's own variable is authoritative WHEN it exists — including when
	# its value is null: the brain writes target_smart_object = null whenever
	# the winning goal has no smart object, and the generic fallbacks below
	# would otherwise make the needs-branch instance steal the work branch's
	# active_job/active_claim and fight over the agent's single path slot.
	var target: Variant = null
	if blackboard.has_var(target_var):
		target = blackboard.get_var(target_var)
	else:
		if blackboard.has_var(&"target_smart_object"):
			target = blackboard.get_var(&"target_smart_object")
		elif blackboard.has_var(&"active_claim"):
			target = blackboard.get_var(&"active_claim")
		elif blackboard.has_var(&"active_job"):
			target = blackboard.get_var(&"active_job")
		elif blackboard.has_var(&"target_node"):
			target = blackboard.get_var(&"target_node")
		elif blackboard.has_var(&"threat_target"):
			target = blackboard.get_var(&"threat_target")

	if target == null:
		_no_target = true
		return

	_requires_adjacent = true
	var job_candidate: Variant = null
	if target is Job or (target is Object and is_instance_valid(target) and ("job_instance" in target or "def" in target)):
		job_candidate = target
	elif blackboard:
		if blackboard.has_var(&"active_job"):
			job_candidate = blackboard.get_var(&"active_job")
		elif blackboard.has_var(&"active_claim"):
			job_candidate = blackboard.get_var(&"active_claim")

	if job_candidate != null:
		if job_candidate is Job and job_candidate.def != null and "requires_adjacent" in job_candidate.def:
			_requires_adjacent = job_candidate.def.requires_adjacent
		elif job_candidate is Object and is_instance_valid(job_candidate):
			if "job_instance" in job_candidate and job_candidate.job_instance != null:
				var def = job_candidate.job_instance.get("def")
				if def != null and "requires_adjacent" in def:
					_requires_adjacent = def.requires_adjacent
			elif "def" in job_candidate and job_candidate.def != null and "requires_adjacent" in job_candidate.def:
				_requires_adjacent = job_candidate.def.requires_adjacent
			elif job_candidate is DeployJobDef or ("def" in job_candidate and job_candidate.def is DeployJobDef):
				_requires_adjacent = false
		
	var path: Array[Vector3] = _resolve_path_to_target(target)
	
	# Check if already within arrival distance
	if _has_target_pos and agent is Node3D:
		var curr_pos: Vector3 = (agent as Node3D).global_position
		var threshold: float = arrival_distance if _requires_adjacent else 0.45
		if curr_pos.distance_to(_target_world_pos) <= threshold:
			_has_valid_target = true
			return
			
	if path.is_empty():
		return
		
	_has_valid_target = true
	if agent.has_method("set_path"):
		agent.set_path(path)
		if agent is Node:
			(agent as Node).set_meta(_PATH_OWNER_META, get_instance_id())


func _tick(_delta: float) -> Status:
	if not agent or not _has_valid_target:
		## Only treat this as a real nav failure (and clean up job state) when we
		## actually had a target to navigate to. A null target means the
		## need-satisfier branch has nothing to do — return FAILURE quietly so
		## the BTDynamicSelector falls through to the work subtree without
		## touching active_job / active_claim on the shared blackboard.
		if not _no_target:
			_handle_navigation_failure()
		return FAILURE
		
	# Check distance to target
	if _has_target_pos and agent is Node3D:
		var curr_pos: Vector3 = (agent as Node3D).global_position
		var dist: float = curr_pos.distance_to(_target_world_pos)
		var threshold: float = arrival_distance if _requires_adjacent else 0.45
		if dist <= threshold:
			return SUCCESS
			
	if agent.has_method("has_arrived") and bool(agent.has_arrived()):
		return SUCCESS
		
	return RUNNING


func _exit() -> void:
	# Only the task instance that owns the agent's current path may clear it
	# (see _PATH_OWNER_META). A failing no-target instance — the needs branch
	# under the root BTDynamicSelector re-ticks every frame — must leave the
	# path (and the pathfinder telemetry it didn't produce) alone.
	if agent == null or not _owns_agent_path():
		return
	if agent.has_method("set_path"):
		agent.set_path([])
	if "pathfinder" in agent and agent.pathfinder != null and agent.pathfinder.has_method("clear_diagnostics"):
		agent.pathfinder.clear_diagnostics()


## True when this instance was the last task to feed the agent a path.
func _owns_agent_path() -> bool:
	return agent is Node \
			and (agent as Node).has_meta(_PATH_OWNER_META) \
			and (agent as Node).get_meta(_PATH_OWNER_META) == get_instance_id()


func _resolve_path_to_target(target: Variant) -> Array[Vector3]:
	if not (agent is Node3D):
		return []
		
	var agent_pos: Vector3 = (agent as Node3D).global_position
	
	# Group name string / StringName resolution
	if target is StringName or target is String:
		var group_name := StringName(str(target))
		if agent.get_tree():
			var nodes := agent.get_tree().get_nodes_in_group(group_name)
			var closest: Node3D = null
			var min_d_sq := INF
			for n in nodes:
				if is_instance_valid(n) and not n.is_queued_for_deletion() and n is Node3D:
					var d_sq := agent_pos.distance_squared_to((n as Node3D).global_position)
					if d_sq < min_d_sq:
						min_d_sq = d_sq
						closest = n as Node3D
			if closest != null:
				target = closest
	
	# Extract target position
	if target is Vector3:
		_target_world_pos = target
		_has_target_pos = true
	elif target is Vector3i:
		_target_world_pos = Vector3(target) + Vector3(0.5, 0.5, 0.5)
		_has_target_pos = true
	elif target is Node3D and is_instance_valid(target):
		_target_world_pos = (target as Node3D).global_position
		_has_target_pos = true
	elif target is Object and is_instance_valid(target):
		if "target_pos" in target and target.target_pos is Vector3:
			_target_world_pos = target.target_pos
			_has_target_pos = true
		elif "world_position" in target and target.world_position is Vector3:
			_target_world_pos = target.world_position
			_has_target_pos = true
		elif "target_position" in target and target.target_position is Vector3:
			_target_world_pos = target.target_position
			_has_target_pos = true
		elif "target_node" in target and target.target_node != null and is_instance_valid(target.target_node):
			var node3d: Node3D = target.target_node as Node3D
			if node3d != null:
				_target_world_pos = node3d.global_position
				_has_target_pos = true
		elif "location" in target and target.location is Vector3:
			_target_world_pos = target.location
			_has_target_pos = true
		elif "anchor_cell" in target and target.anchor_cell is Vector3i and target.anchor_cell != Vector3i.MAX:
			_target_world_pos = Vector3(target.anchor_cell) + Vector3(0.5, 0.5, 0.5)
			_has_target_pos = true
			
	if not ("pathfinder" in agent) or agent.pathfinder == null:
		return []
		
	var pathfinder = agent.pathfinder
	if target is Node3D and is_instance_valid(target) and target.has_method("get_footprint_cells"):
		var fp: Array = target.get_footprint_cells()
		if not fp.is_empty():
			return pathfinder.find_path_to_footprint_adjacent(agent_pos, fp)
	elif target is Object and is_instance_valid(target) and "target_node" in target and target.target_node != null:
		var tn = target.target_node
		if is_instance_valid(tn) and tn.has_method("get_footprint_cells"):
			var fp_job: Array = tn.get_footprint_cells()
			if not fp_job.is_empty():
				return pathfinder.find_path_to_footprint_adjacent(agent_pos, fp_job)
				
	if _has_target_pos:
		if _requires_adjacent:
			return pathfinder.find_path_to_adjacent(agent_pos, _target_world_pos)
		else:
			return pathfinder.find_path_world(agent_pos, _target_world_pos)
		
	return []


func _handle_navigation_failure() -> void:
	if not agent or not blackboard:
		return

	var colonist_id: String = ""
	if agent is Colonist:
		colonist_id = (agent as Colonist).colonist_id
	elif "colonist_id" in agent:
		colonist_id = str(agent.colonist_id)

	var job_id: String = ""
	
	# 1. Release active claim
	if blackboard.has_var(&"active_claim"):
		var claim: Variant = blackboard.get_var(&"active_claim")
		if claim != null and is_instance_valid(claim):
			if "job_instance" in claim and claim.job_instance != null and is_instance_valid(claim.job_instance):
				job_id = str(claim.job_instance.id)
			if claim.has_method("abandon"):
				claim.abandon()
		blackboard.erase_var(&"active_claim")

	# 2. Release active job
	if blackboard.has_var(&"active_job"):
		var job: Variant = blackboard.get_var(&"active_job")
		if job != null and is_instance_valid(job):
			if job_id == "" and "id" in job:
				job_id = str(job.id)
			if job.has_method("abandon_claim") and colonist_id != "":
				job.abandon_claim(colonist_id)
			elif agent is Colonist and job.has_method("unassign"):
				job.unassign(agent as Colonist)
		blackboard.erase_var(&"active_job")

	if blackboard.has_var(target_var):
		blackboard.erase_var(target_var)

	if agent is Colonist:
		(agent as Colonist).current_job = null

	# 3. Register blacklist on JobBoard
	if job_id != "" and colonist_id != "":
		var colony: Node = agent.get_node_or_null("/root/Colony")
		if colony != null and "job_board" in colony and colony.job_board != null:
			colony.job_board.blacklist_job_for(job_id, colonist_id, 10.0)

	# 4. Trigger immediate goal re-evaluation
	var brain: ColonistBrain = null
	if agent is Node:
		brain = (agent as Node).get_node_or_null("ColonistBrain") as ColonistBrain
		if not brain and "brain" in agent:
			brain = agent.brain
	if brain != null:
		brain.evaluate_goals()
