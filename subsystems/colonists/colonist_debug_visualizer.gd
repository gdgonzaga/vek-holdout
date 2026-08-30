class_name ColonistDebugVisualizer
extends Node3D

## Visual debug overlay for Colonists: renders 3D state billboard and path wireframes.
## Automatically strips itself if not in debug mode (OS.is_debug_build() == false).

@export var enabled: bool = true
@export var label_height_offset: float = 2.2
@export var path_color: Color = Color(0.0, 0.8, 1.0, 1.0)      ## Cyan
@export var target_color: Color = Color(1.0, 0.6, 0.0, 1.0)    ## Orange

## How long pathfinder telemetry (A* boxes, ring candidates, status) stays
## drawable after the query that produced it.
const _TELEMETRY_TTL_SEC: float = 5.0

var _parent_body: CharacterBody3D
var _bt_player: BTPlayer
var _brain: ColonistBrain
var _pathfinder: VoxelPathfinder
var _step_climber: StepClimber
var _nav_agent: NavigationAgent3D
var _label: Label3D
var _mesh_instance: MeshInstance3D
var _immediate_mesh: ImmediateMesh
var _material: StandardMaterial3D


func _ready() -> void:
	if not OS.is_debug_build() or not enabled:
		queue_free()
		return
	_parent_body = get_parent() as CharacterBody3D
	if _parent_body == null:
		push_warning("ColonistDebugVisualizer must be a child of a CharacterBody3D.")
		queue_free()
		return

	# Resolve BTPlayer & ColonistBrain
	_bt_player = _parent_body.get_node_or_null("BTPlayer") as BTPlayer
	if _bt_player == null:
		_bt_player = _parent_body.find_child("BTPlayer", false, false) as BTPlayer
	_brain = _parent_body.get_node_or_null("ColonistBrain") as ColonistBrain

	# Resolve VoxelPathfinder child
	if "pathfinder" in _parent_body and _parent_body.pathfinder != null:
		_pathfinder = _parent_body.pathfinder
	else:
		_pathfinder = _parent_body.get_node_or_null("VoxelPathfinder") as VoxelPathfinder
	if _pathfinder == null:
		var pfs := _parent_body.find_children("", "VoxelPathfinder", true, false)
		if not pfs.is_empty():
			_pathfinder = pfs[0] as VoxelPathfinder

	# Resolve StepClimber child
	_step_climber = _parent_body.get_node_or_null("StepClimber") as StepClimber
	if _step_climber == null:
		var scs := _parent_body.find_children("", "StepClimber", true, false)
		if not scs.is_empty():
			_step_climber = scs[0] as StepClimber

	# Fallback search for any NavigationAgent3D
	var agents := _parent_body.find_children("", "NavigationAgent3D", true, false)
	if not agents.is_empty():
		_nav_agent = agents[0] as NavigationAgent3D

	_setup_billboard_label()
	_setup_path_mesh()


func _process(_delta: float) -> void:
	if not OS.is_debug_build() or _parent_body == null:
		return

	_update_label()
	_draw_navigation_path()


func _telemetry_is_fresh() -> bool:
	if _pathfinder == null or _pathfinder.last_query_time < 0.0:
		return false
	var now := float(Time.get_ticks_msec()) * 0.001
	return now - _pathfinder.last_query_time < _TELEMETRY_TTL_SEC


func _setup_billboard_label() -> void:
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 18
	_label.pixel_size = 0.0035
	_label.outline_size = 4
	_label.modulate = Color.YELLOW
	_label.position = Vector3(0, label_height_offset, 0)
	add_child(_label)


func _setup_path_mesh() -> void:
	_immediate_mesh = ImmediateMesh.new()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	_mesh_instance.material_override = _material
	_mesh_instance.top_level = true
	add_child(_mesh_instance)
	if is_inside_tree():
		_mesh_instance.global_position = Vector3.ZERO


func _update_label() -> void:
	if _label == null or _parent_body == null:
		return
	var text_lines: Array[String] = []

	# 1. State + Job info
	var name_str: String = str(_parent_body.get("display_name")) if "display_name" in _parent_body and not str(_parent_body.display_name).is_empty() else _parent_body.name
	var state_str: String = _resolve_colonist_state()
	text_lines.append("%s [%s]" % [name_str, state_str])

	var job_str: String = _resolve_colonist_job()
	if not job_str.is_empty():
		text_lines.append(job_str)

	# 2. Locomotion / Path Info
	var path_info: String = _resolve_path_info()
	if not path_info.is_empty():
		text_lines.append(path_info)

	# 3. Path & Start/Goal Cells
	if _pathfinder != null and _telemetry_is_fresh() and _pathfinder.last_query_start != Vector3i.MAX:
		var s_w: String = "OK" if _pathfinder.is_walkable(_pathfinder.last_query_start) else "BLOCKED"
		var t_w: String = "OK" if _pathfinder.is_walkable(_pathfinder.last_query_target) else "BLOCKED"
		text_lines.append("A*: %s | %s[%s] -> %s[%s]" % [
			_pathfinder.last_status,
			str(_pathfinder.last_query_start), s_w,
			str(_pathfinder.last_query_target), t_w
		])

	# 4. Physics & StepClimber
	var on_floor_str := "ON" if _parent_body.is_on_floor() else "AIR"
	var climber_status := (" | %s" % _step_climber.last_probe_status) if _step_climber != null and not _step_climber.last_probe_status.is_empty() and _step_climber.last_probe_status != "IDLE" else ""
	text_lines.append("Phys: Floor %s (Vel: %.1f, %.1f)%s" % [
		on_floor_str,
		_parent_body.velocity.x, _parent_body.velocity.z,
		climber_status
	])

	# 5. Inventory
	var carry_str: String = _resolve_carried_items()
	if not carry_str.is_empty():
		text_lines.append("Carry: %s" % carry_str)

	_label.text = "\n".join(text_lines)


func _resolve_colonist_state() -> String:
	var path: Array = _parent_body.get("_path") if "_path" in _parent_body else []
	var path_idx: int = int(_parent_body.get("_path_index")) if "_path_index" in _parent_body else 0
	if not path.is_empty() and path_idx < path.size():
		return "MOVE (wp %d/%d)" % [path_idx + 1, path.size()]

	if _bt_player != null and _bt_player.blackboard != null:
		if _bt_player.blackboard.has_var(&"current_goal"):
			var goal: StringName = _bt_player.blackboard.get_var(&"current_goal")
			if goal == &"work":
				# active_job lives in the work subtree's scope and is absent
				# between cycles — read only when present.
				if _bt_player.blackboard.has_var(&"active_job"):
					var active_job = _bt_player.blackboard.get_var(&"active_job")
					if active_job != null and "completed_units" in active_job and "total_units" in active_job:
						return "WORK (%d/%d)" % [active_job.completed_units, active_job.total_units]
				return "WORK"
			elif goal != &"none":
				return String(goal).to_upper()

	return "IDLE"


func _resolve_colonist_job_compact() -> String:
	var job_obj = null
	if _bt_player != null and _bt_player.blackboard != null and _bt_player.blackboard.has_var(&"active_job"):
		job_obj = _bt_player.blackboard.get_var(&"active_job")

	if job_obj == null:
		for prop in ["current_job", "_current_job", "job", "_job"]:
			if prop in _parent_body:
				job_obj = _parent_body.get(prop)
				if job_obj != null:
					break

	if job_obj == null:
		return ""
	var title: String = ""
	if "title" in job_obj and not str(job_obj.title).is_empty():
		title = str(job_obj.title)
	elif "labor_id" in job_obj and not str(job_obj.labor_id).is_empty():
		title = str(job_obj.labor_id).capitalize()
	else:
		title = "Job"

	var target_str := ""
	if "anchor_cell" in job_obj and job_obj.anchor_cell != Vector3i.ZERO:
		target_str = " @ %s" % str(job_obj.anchor_cell)
	elif "target_node" in job_obj and job_obj.target_node != null and is_instance_valid(job_obj.target_node):
		target_str = " -> %s" % job_obj.target_node.name
	elif "world_position" in job_obj and job_obj.world_position != Vector3.ZERO:
		target_str = " @ (%.1f, %.1f, %.1f)" % [job_obj.world_position.x, job_obj.world_position.y, job_obj.world_position.z]
	elif "location" in job_obj and job_obj.location != Vector3.ZERO:
		target_str = " @ (%.1f, %.1f, %.1f)" % [job_obj.location.x, job_obj.location.y, job_obj.location.z]

	return "Job: %s%s" % [title, target_str]


func _resolve_colonist_job() -> String:
	var job_obj = null
	if _bt_player != null and _bt_player.blackboard != null and _bt_player.blackboard.has_var(&"active_job"):
		job_obj = _bt_player.blackboard.get_var(&"active_job")

	if job_obj == null:
		for prop in ["current_job", "_current_job", "job", "_job"]:
			if prop in _parent_body:
				job_obj = _parent_body.get(prop)
				if job_obj != null:
					break

	var lines: Array[String] = []

	if job_obj != null:
		var title: String = ""
		if "title" in job_obj and not str(job_obj.title).is_empty():
			title = str(job_obj.title)
		elif "labor_id" in job_obj and not str(job_obj.labor_id).is_empty():
			title = str(job_obj.labor_id).capitalize()
		elif "def" in job_obj and job_obj.def != null and "display_name" in job_obj.def:
			title = str(job_obj.def.display_name)
		else:
			title = job_obj.get_class() if job_obj is Object else "Job"

		var id_str: String = ""
		if "id" in job_obj and not str(job_obj.id).is_empty():
			id_str = " [%s]" % str(job_obj.id).left(6)

		lines.append("Job: %s%s" % [title, id_str])

		if "anchor_cell" in job_obj and job_obj.anchor_cell != Vector3i.ZERO:
			lines.append("Anchor: %s" % str(job_obj.anchor_cell))
		elif "world_position" in job_obj and job_obj.world_position != Vector3.ZERO:
			lines.append("Target Pos: (%.1f, %.1f, %.1f)" % [job_obj.world_position.x, job_obj.world_position.y, job_obj.world_position.z])
		elif "location" in job_obj and job_obj.location != Vector3.ZERO:
			lines.append("Target Pos: (%.1f, %.1f, %.1f)" % [job_obj.location.x, job_obj.location.y, job_obj.location.z])
		elif "target_node" in job_obj and job_obj.target_node != null and is_instance_valid(job_obj.target_node):
			lines.append("Target: %s" % job_obj.target_node.name)

	return "\n".join(lines)


func _resolve_path_info() -> String:
	var path: Array = _parent_body.get("_path") if "_path" in _parent_body else []
	var path_idx: int = int(_parent_body.get("_path_index")) if "_path_index" in _parent_body else 0

	if not path.is_empty():
		if path_idx < path.size():
			var curr_wp: Vector3 = path[path_idx]
			var final_wp: Vector3 = path[-1]
			var dist_wp: float = _parent_body.global_position.distance_to(curr_wp)
			var dist_final: float = _parent_body.global_position.distance_to(final_wp)
			return "Wp %d/%d (%.1fm) | Dest: %.1fm" % [path_idx + 1, path.size(), dist_wp, dist_final]
		return "Path: Arrived"

	if _nav_agent != null:
		var reachable: String = "YES" if _nav_agent.is_target_reachable() else "NO"
		var finished: String = "YES" if _nav_agent.is_navigation_finished() else "NO"
		var dist_to_target: float = _parent_body.global_position.distance_to(_nav_agent.target_position)
		return "Reachable: %s | Finished: %s | Dist: %.2fm" % [reachable, finished, dist_to_target]

	return ""


func _resolve_carried_items() -> String:
	if not ("inventory" in _parent_body) or _parent_body.inventory == null:
		return ""
	var items: Dictionary = _parent_body.inventory.items
	var entries: Array[String] = []
	for item_id in items:
		var count: int = int(items[item_id])
		if count > 0:
			entries.append("%s x%d" % [item_id, count])
	return ", ".join(entries)


func _draw_navigation_path() -> void:
	if _immediate_mesh == null:
		return
	_immediate_mesh.clear_surfaces()

	var colonist_pos: Vector3 = _parent_body.global_position
	var path: Array = _parent_body.get("_path") if "_path" in _parent_body else []
	var path_idx: int = int(_parent_body.get("_path_index")) if "_path_index" in _parent_body else 0
	var target_pos: Vector3 = Vector3.ZERO

	if _bt_player != null and _bt_player.blackboard != null:
		if _bt_player.blackboard.has_var(&"target_pos"):
			var tp = _bt_player.blackboard.get_var(&"target_pos")
			if tp is Vector3 and tp != Vector3.ZERO:
				target_pos = tp
		if target_pos == Vector3.ZERO and _bt_player.blackboard.has_var(&"target_smart_object"):
			var obj = _bt_player.blackboard.get_var(&"target_smart_object")
			if obj is Node3D and is_instance_valid(obj):
				target_pos = obj.global_position

	if target_pos == Vector3.ZERO and _pathfinder != null and _telemetry_is_fresh() and _pathfinder.last_query_target != Vector3i.MAX:
		target_pos = Vector3(_pathfinder.last_query_target) + Vector3(0.5, 0.0, 0.5)

	# Draw active locomotion path
	if not path.is_empty() and path_idx < path.size():
		var prev_point := colonist_pos
		_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		_immediate_mesh.surface_set_color(path_color)
		for i in range(path_idx, path.size()):
			var wp: Vector3 = path[i]
			_immediate_mesh.surface_add_vertex(prev_point)
			_immediate_mesh.surface_add_vertex(wp)
			prev_point = wp
		_immediate_mesh.surface_end()

		for i in range(path_idx, path.size()):
			_draw_waypoint_marker(path[i], path_color)

	if target_pos != Vector3.ZERO:
		_draw_target_marker(target_pos)

	if _pathfinder != null and _telemetry_is_fresh():
		if _pathfinder.last_query_start != Vector3i.MAX:
			_draw_cell_box(_pathfinder.last_query_start, Color.GREEN)
		if _pathfinder.last_query_target != Vector3i.MAX:
			_draw_cell_box(_pathfinder.last_query_target, Color.RED)
		for candidate in _pathfinder.last_stand_candidates:
			if candidate is Dictionary and candidate.has("cell"):
				var cell: Vector3i = candidate.get("cell", Vector3i.ZERO)
				var color: Color = Color.YELLOW if candidate.get("chosen", false) else Color.ORANGE
				_draw_cell_box(cell, color)


func _draw_cell_box(cell: Vector3i, color: Color) -> void:
	var pos := Vector3(cell)
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 0, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 0, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 0, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 0, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 1, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 1, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 1, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 1, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 1, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 1, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 1, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 1, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 1, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 0, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 1, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 0, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 1, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 1, 1))
	_immediate_mesh.surface_end()


func _draw_waypoint_marker(pos: Vector3, color: Color) -> void:
	var s: float = 0.15
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_immediate_mesh.surface_set_color(color)
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, 0.05, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, 0.05, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0.05, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0.05, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, s * 2.0, 0))
	_immediate_mesh.surface_end()


func _draw_target_marker(pos: Vector3) -> void:
	var s: float = 0.35
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_immediate_mesh.surface_set_color(target_color)
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, 0.05, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, 0.05, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, 0.05, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, 0.05, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, 0.05, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, 0.05, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, 0.05, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, 0.05, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, s * 2.0, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, s * 2.0, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, s * 2.0, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, s * 2.0, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, s * 2.0, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, s * 2.0, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, s * 2.0, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, s * 2.0, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, 0.05, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, s * 2.0, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, 0.05, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, s * 2.0, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, 0.05, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, s * 2.0, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, 0.05, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, s * 2.0, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s * 1.5, 0.05, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s * 1.5, 0.05, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0.05, -s * 1.5))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0.05, s * 1.5))
	_immediate_mesh.surface_end()
