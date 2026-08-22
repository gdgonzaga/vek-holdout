class_name ColonistDebugVisualizer
extends Node3D

## Visual debug overlay for Colonists: renders 3D state billboard and path wireframes.
## Automatically strips itself if not in debug mode (OS.is_debug_build() == false).

@export var enabled: bool = true
@export var label_height_offset: float = 2.2
@export var path_color: Color = Color(0.0, 0.8, 1.0, 1.0)      ## Cyan
@export var target_color: Color = Color(1.0, 0.6, 0.0, 1.0)    ## Orange

var _parent_body: CharacterBody3D
var _colonist_ai: Node
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

	# Resolve ColonistAI child
	_colonist_ai = _parent_body.get_node_or_null("ColonistAI")
	if _colonist_ai == null:
		_colonist_ai = _parent_body.find_child("ColonistAI", false, false)

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


func _setup_billboard_label() -> void:
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true  # Visible through terrain/mined blocks
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
	_material.albedo_color = Color.WHITE
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = true  # Always visible through terrain
	_material.render_priority = 10
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _immediate_mesh
	_mesh_instance.material_override = _material
	_mesh_instance.top_level = true  # Global world coordinates
	add_child(_mesh_instance)


func _update_label() -> void:
	if _label == null or not is_instance_valid(_parent_body):
		return

	var text_lines: Array[String] = []

	# 1. Colonist Identity & HP
	var colonist_name: String = str(_parent_body.get("display_name")) if "display_name" in _parent_body and not str(_parent_body.get("display_name")).is_empty() else _parent_body.name
	var hp: int = _parent_body.get_hp() if _parent_body.has_method("get_hp") else (int(_parent_body.get("_current_hp")) if "_current_hp" in _parent_body else -1)
	var max_hp: int = _parent_body.get_max_hp() if _parent_body.has_method("get_max_hp") else 100
	if hp >= 0:
		text_lines.append("%s (HP: %d/%d)" % [colonist_name, hp, max_hp])
	else:
		text_lines.append(colonist_name)

	# 2. State
	var state_str: String = _resolve_colonist_state()
	text_lines.append("State: %s" % state_str)

	# 3. Assigned Job / Target / Leg
	var job_str: String = _resolve_colonist_job()
	if not job_str.is_empty():
		text_lines.append(job_str)

	# 4. Path & Navigation Info
	var path_info: String = _resolve_path_info()
	if not path_info.is_empty():
		text_lines.append(path_info)

	# 5. Diagnostic: Pathfinder Telemetry
	if _pathfinder != null:
		text_lines.append("A*: %s" % _pathfinder.last_status)
		if _pathfinder.last_query_start != Vector3i.MAX:
			var s_w: String = "OK" if _pathfinder.is_walkable(_pathfinder.last_query_start) else "BLOCKED"
			var t_w: String = "OK" if _pathfinder.is_walkable(_pathfinder.last_query_target) else "BLOCKED"
			text_lines.append("Cells: Start %s [%s] | Goal %s [%s]" % [
				str(_pathfinder.last_query_start), s_w,
				str(_pathfinder.last_query_target), t_w
			])

	# 6. Diagnostic: StepClimber Telemetry
	if _step_climber != null and not _step_climber.last_probe_status.is_empty():
		text_lines.append("Climber: %s" % _step_climber.last_probe_status)

	# 7. Physics & Inventory
	var phys_info: String = "Floor: %s | Vel: (%.1f, %.1f, %.1f)" % [
		str(_parent_body.is_on_floor()),
		_parent_body.velocity.x,
		_parent_body.velocity.y,
		_parent_body.velocity.z
	]
	text_lines.append(phys_info)

	var carry_str: String = _resolve_carried_items()
	if not carry_str.is_empty():
		text_lines.append("Carry: %s" % carry_str)

	_label.text = "\n".join(text_lines)


## Inspects ColonistAI or parent body and child nodes for state variables
func _resolve_colonist_state() -> String:
	if _colonist_ai != null and is_instance_valid(_colonist_ai):
		var state_val = _colonist_ai.get("_state")
		if state_val != null:
			match int(state_val):
				0:
					return "IDLE"
				1:
					var path: Array = _parent_body.get("_path") if "_path" in _parent_body else []
					var path_idx: int = int(_parent_body.get("_path_index")) if "_path_index" in _parent_body else 0
					if not path.is_empty() and path_idx < path.size():
						return "MOVE (wp %d/%d)" % [path_idx + 1, path.size()]
					return "MOVE"
				2:
					var elapsed: float = float(_colonist_ai.get("_work_elapsed"))
					var dur: float = float(_colonist_ai.get("_work_duration"))
					if dur > 0.0:
						return "WORK (%.1fs / %.1fs)" % [elapsed, dur]
					return "WORK"
				_:
					return "STATE_%d" % int(state_val)

	for prop in ["current_state", "_current_state", "state", "_state", "action_state", "_action_state", "status"]:
		if prop in _parent_body:
			var val = _parent_body.get(prop)
			if val != null:
				return str(val)

	for child_name in ["StateMachine", "FSM", "State", "Brain", "JobController"]:
		var child := _parent_body.find_child(child_name, false, false)
		if child != null:
			for prop in ["current_state", "state", "_state", "state_name", "active_state"]:
				if prop in child:
					var val = child.get(prop)
					if val != null:
						return "%s (%s)" % [str(val), child_name]

	return "UNKNOWN"


## Inspects parent for active job, leg, and target coordinates
func _resolve_colonist_job() -> String:
	var job_obj = null
	for prop in ["current_job", "_current_job", "job", "_job", "active_job"]:
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
		elif "location" in job_obj and job_obj.location != Vector3.ZERO:
			lines.append("Target Pos: (%.1f, %.1f, %.1f)" % [job_obj.location.x, job_obj.location.y, job_obj.location.z])
		elif "target_node" in job_obj and job_obj.target_node != null and is_instance_valid(job_obj.target_node):
			lines.append("Target: %s" % job_obj.target_node.name)

	# Active Leg info from ColonistAI
	if _colonist_ai != null and is_instance_valid(_colonist_ai):
		var leg = _colonist_ai.get("_leg")
		if leg != null:
			var leg_str: String = ""
			var kind_name: String = _format_leg_kind(int(leg.kind)) if "kind" in leg else ""
			if "target_node" in leg and leg.target_node != null and is_instance_valid(leg.target_node):
				leg_str = "Leg: %s -> %s" % [kind_name, leg.target_node.name]
			elif "location" in leg and leg.location != Vector3.ZERO:
				leg_str = "Leg: %s @ (%.1f, %.1f, %.1f)" % [kind_name, leg.location.x, leg.location.y, leg.location.z]
			if not leg_str.is_empty():
				lines.append(leg_str)

	return "\n".join(lines)


func _format_leg_kind(kind: int) -> String:
	match kind:
		1:
			return "FETCH"
		2:
			return "DELIVER"
		_:
			return "Kind %d" % kind if kind != 0 else "MOVE"


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

	# 1. Resolve Target Position
	if _colonist_ai != null and is_instance_valid(_colonist_ai):
		var leg = _colonist_ai.get("_leg")
		if leg != null:
			if "location" in leg and leg.location != Vector3.ZERO:
				target_pos = leg.location
			elif "target_node" in leg and leg.target_node != null and is_instance_valid(leg.target_node) and leg.target_node is Node3D:
				target_pos = (leg.target_node as Node3D).global_position

	if target_pos == Vector3.ZERO and "current_job" in _parent_body and _parent_body.current_job != null:
		var job = _parent_body.current_job
		if "location" in job and job.location != Vector3.ZERO:
			target_pos = job.location
		elif "anchor_cell" in job and job.anchor_cell != Vector3i.ZERO:
			target_pos = Vector3(job.anchor_cell) + Vector3(0.5, 0.5, 0.5)
		elif "target_node" in job and job.target_node != null and is_instance_valid(job.target_node) and job.target_node is Node3D:
			target_pos = (job.target_node as Node3D).global_position

	if target_pos == Vector3.ZERO and _pathfinder != null and _pathfinder.last_query_target != Vector3i.MAX:
		target_pos = Vector3(_pathfinder.last_query_target) + Vector3(0.5, 0.5, 0.5)

	if target_pos == Vector3.ZERO and not path.is_empty():
		target_pos = path[-1]

	# 2. Fallback to NavigationAgent3D
	if path.is_empty() and _nav_agent != null:
		var nav_path: PackedVector3Array = _nav_agent.get_current_navigation_path()
		if not nav_path.is_empty():
			for p in nav_path:
				path.append(p)
			path_idx = 0
		if target_pos == Vector3.ZERO:
			target_pos = _nav_agent.target_position

	# 3. Draw Direct Tether Line linking Colonist directly to Target
	if target_pos != Vector3.ZERO and colonist_pos.distance_to(target_pos) > 0.3:
		_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		var tether_color := target_color
		if _pathfinder != null and _pathfinder.last_query_target != Vector3i.MAX and not _pathfinder.is_walkable(_pathfinder.last_query_target):
			tether_color = Color(1.0, 0.2, 0.2, 0.9) # Red if target is unwalkable/blocked
		elif path.is_empty():
			tether_color = Color(1.0, 0.4, 0.0, 0.9) # Orange warning if no path exists
		else:
			tether_color = Color(target_color.r, target_color.g, target_color.b, 0.75)

		_immediate_mesh.surface_set_color(tether_color)
		_immediate_mesh.surface_add_vertex(colonist_pos + Vector3.UP * 0.8)
		_immediate_mesh.surface_set_color(tether_color)
		_immediate_mesh.surface_add_vertex(target_pos + Vector3.UP * 0.5)
		_immediate_mesh.surface_end()

	# 4. Draw Waypoint Path Wireframe (if path exists)
	if not path.is_empty() and path_idx < path.size():
		# Remaining active path on ground
		_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		_immediate_mesh.surface_set_color(path_color)
		_immediate_mesh.surface_add_vertex(colonist_pos + Vector3.UP * 0.15)
		for i in range(path_idx, path.size()):
			var pt: Vector3 = path[i]
			_immediate_mesh.surface_set_color(path_color)
			_immediate_mesh.surface_add_vertex(pt + Vector3.UP * 0.15)
		_immediate_mesh.surface_end()

		# Passed waypoints in dim color
		if path_idx > 0:
			_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
			var dim_color := Color(0.4, 0.4, 0.4, 0.5)
			for i in range(0, mini(path_idx + 1, path.size())):
				var pt: Vector3 = path[i]
				_immediate_mesh.surface_set_color(dim_color)
				_immediate_mesh.surface_add_vertex(pt + Vector3.UP * 0.08)
			_immediate_mesh.surface_end()

		# Waypoint markers
		for i in range(path_idx, path.size()):
			_draw_waypoint_marker(path[i], path_color)

	# 5. Draw 3D Target Marker
	if target_pos != Vector3.ZERO:
		_draw_target_marker(target_pos)

	# 6. Diagnostic: Draw A* Start / Goal Cell Wireframes
	if _pathfinder != null:
		if _pathfinder.last_query_start != Vector3i.MAX:
			var s_color := Color(0.1, 1.0, 0.1, 0.7) if _pathfinder.is_walkable(_pathfinder.last_query_start) else Color(1.0, 0.1, 0.1, 0.7)
			_draw_cell_box(_pathfinder.last_query_start, s_color)
		if _pathfinder.last_query_target != Vector3i.MAX and _pathfinder.last_query_target != _pathfinder.last_query_start:
			var t_color := Color(0.1, 1.0, 0.1, 0.7) if _pathfinder.is_walkable(_pathfinder.last_query_target) else Color(1.0, 0.1, 0.1, 0.7)
			_draw_cell_box(_pathfinder.last_query_target, t_color)

	# 7. Diagnostic: Draw StepClimber Probes
	if _step_climber != null:
		var now := float(Time.get_ticks_msec()) * 0.001
		if now - _step_climber.last_probe_time < 2.0 and _step_climber.last_raised_origin != Vector3.ZERO:
			var is_overhang: bool = "FAIL_OVERHANG" in _step_climber.last_probe_status
			var probe_color := Color.RED if is_overhang else Color.GREEN
			_draw_probe_box(_step_climber.last_raised_origin, _step_climber.last_shape_radius, _step_climber.last_shape_height, probe_color)
			
			if _step_climber.last_over_origin != Vector3.ZERO:
				_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
				_immediate_mesh.surface_set_color(Color.YELLOW)
				_immediate_mesh.surface_add_vertex(_step_climber.last_raised_origin)
				_immediate_mesh.surface_add_vertex(_step_climber.last_over_origin)
				_immediate_mesh.surface_end()
			
			if _step_climber.last_landing_origin != Vector3.ZERO:
				var is_ok: bool = "OK" in _step_climber.last_probe_status
				var land_color := Color.CYAN if is_ok else Color.MAGENTA
				_draw_probe_box(_step_climber.last_landing_origin, _step_climber.last_shape_radius, _step_climber.last_shape_height, land_color)


func _draw_cell_box(cell: Vector3i, color: Color) -> void:
	var pos := Vector3(cell)
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_immediate_mesh.surface_set_color(color)
	# Bottom square
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 0, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 0, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 0, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 0, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, 0))
	# Top square
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 1, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 1, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 1, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 1, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 1, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 1, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 1, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 1, 0))
	# Pillars
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 1, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 0, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 1, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 0, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(1, 1, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, 1))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 1, 1))
	_immediate_mesh.surface_end()


func _draw_probe_box(origin: Vector3, radius: float, height: float, color: Color) -> void:
	var half_h := height * 0.5
	var r := radius
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_immediate_mesh.surface_set_color(color)
	# Bottom cross/square
	_immediate_mesh.surface_add_vertex(origin + Vector3(-r, -half_h, -r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(r, -half_h, -r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(r, -half_h, -r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(r, -half_h, r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(r, -half_h, r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(-r, -half_h, r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(-r, -half_h, r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(-r, -half_h, -r))
	# Top cross/square
	_immediate_mesh.surface_add_vertex(origin + Vector3(-r, half_h, -r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(r, half_h, -r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(r, half_h, -r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(r, half_h, r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(r, half_h, r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(-r, half_h, r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(-r, half_h, r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(-r, half_h, -r))
	# Vertical edges
	_immediate_mesh.surface_add_vertex(origin + Vector3(-r, -half_h, -r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(-r, half_h, -r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(r, -half_h, -r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(r, half_h, -r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(r, -half_h, r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(r, half_h, r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(-r, -half_h, r))
	_immediate_mesh.surface_add_vertex(origin + Vector3(-r, half_h, r))
	_immediate_mesh.surface_end()


func _draw_waypoint_marker(pos: Vector3, color: Color) -> void:
	var s: float = 0.15
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_immediate_mesh.surface_set_color(color)
	# Horizontal cross
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, 0.05, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, 0.05, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0.05, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0.05, s))
	# Vertical tick
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, s * 2.0, 0))
	_immediate_mesh.surface_end()


func _draw_target_marker(pos: Vector3) -> void:
	var s: float = 0.35
	_immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_immediate_mesh.surface_set_color(target_color)
	# Bottom square
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, 0.05, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, 0.05, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, 0.05, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, 0.05, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, 0.05, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, 0.05, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, 0.05, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, 0.05, -s))
	# Top square
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, s * 2.0, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, s * 2.0, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, s * 2.0, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, s * 2.0, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, s * 2.0, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, s * 2.0, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, s * 2.0, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, s * 2.0, -s))
	# Vertical pillars
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, 0.05, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, s * 2.0, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, 0.05, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, s * 2.0, -s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, 0.05, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s, s * 2.0, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, 0.05, s))
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s, s * 2.0, s))
	# Crosshair on ground
	_immediate_mesh.surface_add_vertex(pos + Vector3(-s * 1.5, 0.05, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(s * 1.5, 0.05, 0))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0.05, -s * 1.5))
	_immediate_mesh.surface_add_vertex(pos + Vector3(0, 0.05, s * 1.5))
	_immediate_mesh.surface_end()
