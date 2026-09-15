class_name AreaDesignationController
extends Node3D
## Controller for 3D Area Designation mode (ARCH "Areas").
##
## Active when Player.mode == AREA_DESIGNATION. Casts a screen-center raycast onto
## ground terrain to resolve standable voxel cells. Two ground clicks designate
## opposite corners of an axis-aligned 3D box, including any difference in Y levels.
## Dispatches actions according to active_tool: persistent Area creation, painting,
## and erasing, or one-time batch flora orders (Chop, Forage, Remove, Cancel).

enum Stage {
	IDLE,
	CORNER_A_PICKED,
}

const _RAY_DISTANCE := 30.0

# Runtime-wired dependencies
var grid_adapter: VoxelGridAdapter
var furniture_layer: FurnitureLayer
var exclude_bodies: Array[PhysicsBody3D] = []

@export var camera_path: NodePath = ^""

var active_tool: String = "create_area"
var target_area_id: String = ""

var _ghost: GhostPreview
var _highlight_root: Node3D
var _camera: Camera3D
var _active: bool = false
var _stage: Stage = Stage.IDLE
var _corner_a: Vector3i = Vector3i.ZERO
var _current_stand_cell: Vector3i = Vector3i.ZERO
var _has_valid_target: bool = false


# =================
# Primary Functions
# =================

func _ready() -> void:
	_ghost = get_node_or_null("GhostPreview") as GhostPreview
	_highlight_root = Node3D.new()
	_highlight_root.name = "AreaHighlights"
	add_child(_highlight_root)
	if camera_path != ^"" and has_node(camera_path):
		_camera = get_node(camera_path)
	EventBus.area_designation_toggled.connect(_on_area_designation_toggled)
	EventBus.area_designation_tool_selected.connect(_on_tool_selected)
	# 1. State Initialization: Updates ghost visibility based on starting active flag.
	_update_activation()


func set_active(active: bool) -> void:
	_active = active
	_stage = Stage.IDLE
	if active:
		EventBus.area_designation_stage_changed.emit("pick corner A")
		# 1. Tool Readout Broadcast: Emits current tool label for HUD header display.
		_broadcast_current_tool()
		# 2. In-World Highlight Refresh: Re-renders area boxes if paint or erase is active.
		_update_area_highlights()
	else:
		_has_valid_target = false
		# 1. In-World Highlight Teardown: Clears persistent area boxes when deactivated.
		_clear_area_highlights()
	# 3. Activation Refresh: Applies active state to ghost preview visibility.
	_update_activation()


func set_tool(tool_id: String, area_id: String = "") -> void:
	active_tool = tool_id
	target_area_id = area_id
	_stage = Stage.IDLE
	# 1. Tool Readout Broadcast: Emits updated tool label for HUD header display.
	_broadcast_current_tool()
	# 2. In-World Highlight Refresh: Displays existing boxes if an area is being modified.
	_update_area_highlights()


func set_camera(camera: Camera3D) -> void:
	_camera = camera


func add_exclude_body(body: PhysicsBody3D) -> void:
	if body != null and not exclude_bodies.has(body):
		exclude_bodies.append(body)


func _on_area_designation_toggled(active: bool) -> void:
	# 1. Mode State Application: Synchronizes controller activation with EventBus toggle.
	set_active(active)


func _on_tool_selected(tool_id: String, area_id: String) -> void:
	# 1. Tool Configuration: Applies the newly selected tool and target area ID.
	set_tool(tool_id, area_id)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if UiGate.is_input_blocked():
		return

	if event is InputEventMouseButton and event.pressed:
		var mouse_event := event as InputEventMouseButton
		var btn: int = mouse_event.button_index

		if btn == MOUSE_BUTTON_LEFT:
			# 1. Designation Click Handling: Handles corner picking or committing on LMB press.
			_handle_left_click()
			get_viewport().set_input_as_handled()
			return
		elif btn == MOUSE_BUTTON_RIGHT:
			if _stage == Stage.CORNER_A_PICKED:
				# 1. Stage Cancellation: Resets corner A selection and reverts to initial picking stage.
				_handle_right_click()
				get_viewport().set_input_as_handled()
				return


func _physics_process(_delta: float) -> void:
	if not _active:
		if _ghost != null and _ghost.visible:
			_ghost.hide_()
		_has_valid_target = false
		return

	# 1. Dependency Fallback: Ensures active Camera3D is resolved.
	_resolve_camera_fallback()
	# 2. Dependency Fallback: Ensures active VoxelGridAdapter is resolved.
	_resolve_grid_adapter_fallback()

	if _camera == null or grid_adapter == null:
		_has_valid_target = false
		return

	# 3. Collision Exclusion: Ensures local player capsule is excluded from raycast.
	_resolve_player_exclusion_fallback()

	# 4. Raycast Evaluation: Projects screen-center raycast to find terrain voxel collision.
	var hit: Dictionary = _perform_screen_raycast()
	if not hit.get("hit", false):
		if _ghost != null:
			_ghost.hide_()
		_has_valid_target = false
		return

	# 5. Position Resolution: Resolves world hit position from smooth or blocky collision data.
	var hit_pos: Vector3 = _extract_hit_world_position(hit)
	# 6. Stand Cell Query: Snaps hit coordinate to the walkable standable cell at the column.
	_current_stand_cell = _query_stand_cell(hit_pos)
	_has_valid_target = true

	# 7. Preview Mesh Update: Computes bounding coordinates and renders preview ghost box.
	_update_preview_ghost()


static func compute_area_bounds(corner_a: Vector3i, corner_b: Vector3i) -> Dictionary:
	var min_x := mini(corner_a.x, corner_b.x)
	var max_x := maxi(corner_a.x, corner_b.x)
	var min_y := mini(corner_a.y, corner_b.y)
	var max_y := maxi(corner_a.y, corner_b.y)
	var min_z := mini(corner_a.z, corner_b.z)
	var max_z := maxi(corner_a.z, corner_b.z)
	var min_cell := Vector3i(min_x, min_y, min_z)
	var max_cell := Vector3i(max_x, max_y, max_z)
	return {
		"min_cell": min_cell,
		"max_cell": max_cell,
	}


# ===================
# Auxiliary Functions
# ===================

func _update_activation() -> void:
	## Auxiliary: Syncs the ghost preview node visibility with active status.
	if not is_node_ready():
		return
	if not _active:
		if _ghost != null:
			_ghost.hide_()
		_has_valid_target = false


func _broadcast_current_tool() -> void:
	## Auxiliary: Emits tool readout signal to update HUD title and instruction labels.
	var label: String = _get_tool_label(active_tool, target_area_id)
	EventBus.area_designation_tool_changed.emit(active_tool, label)


func _get_tool_label(tool_id: String, area_id: String) -> String:
	## Auxiliary: Resolves human-readable display label for the given tool and target area.
	match tool_id:
		"remove_plant":
			return "Remove Plants"
		"chop_tree":
			return "Chop Trees"
		"forage":
			return "Forage"
		"cancel_orders":
			return "Cancel Orders"
		"create_area":
			return "New Area"
		"paint_area":
			var area_name: String = _get_area_display_name(area_id)
			return "Paint Area (%s)" % area_name
		"erase_area":
			var area_name: String = _get_area_display_name(area_id)
			return "Erase Area (%s)" % area_name
		_:
			return "Area Designation"


func _get_area_display_name(area_id: String) -> String:
	## Auxiliary: Looks up the display name of an area by ID, defaulting to Area.
	if Colony != null and Colony.area_manager != null and area_id != "":
		var area: Area = Colony.area_manager.get_area(area_id)
		if area != null:
			return area.display_name
	return "Area"


func _handle_left_click() -> void:
	## Auxiliary: Advances the two-click designation stage or commits the active tool.
	if not _has_valid_target:
		return

	if _stage == Stage.IDLE:
		_corner_a = _current_stand_cell
		_stage = Stage.CORNER_A_PICKED
		EventBus.area_designation_stage_changed.emit("pick corner B")
	elif _stage == Stage.CORNER_A_PICKED:
		var bounds: Dictionary = compute_area_bounds(_corner_a, _current_stand_cell)
		var min_c: Vector3i = bounds["min_cell"]
		var max_c: Vector3i = bounds["max_cell"]
		# 1. Tool Commit Execution: Dispatches bounding box to the active tool implementation.
		_commit_tool_action(min_c, max_c)
		_stage = Stage.IDLE
		EventBus.area_designation_stage_changed.emit("pick corner A")


func _handle_right_click() -> void:
	## Auxiliary: Cancels locked corner A selection and reverts to stage IDLE.
	_stage = Stage.IDLE
	EventBus.area_designation_stage_changed.emit("pick corner A")


func _commit_tool_action(min_c: Vector3i, max_c: Vector3i) -> void:
	## Auxiliary: Dispatches the designated bounding volume to the corresponding tool handler.
	match active_tool:
		"create_area":
			# 1. Area Creation: Registers a new persistent area enclosing the bounding volume.
			_commit_create_area(min_c, max_c)
		"paint_area":
			# 1. Area Expansion: Appends the bounding volume to the targeted area.
			_commit_paint_area(min_c, max_c)
		"erase_area":
			# 1. Area Subtraction: Carves out the bounding volume from the targeted area.
			_commit_erase_area(min_c, max_c)
		"chop_tree":
			# 1. Batch Tree Marking: Flags matching trees in the volume for harvesting.
			_commit_chop_trees(min_c, max_c)
		"forage":
			# 1. Batch Foraging Marking: Flags fruit-bearing bushes in the volume for foraging.
			_commit_forage(min_c, max_c)
		"remove_plant":
			# 1. Batch Plant Removal: Flags all wild flora in the volume for clearing.
			_commit_remove_plants(min_c, max_c)
		"cancel_orders":
			# 1. Order Cancellation: Unmarks any harvestable flora in the volume.
			_commit_cancel_orders(min_c, max_c)


func _commit_create_area(min_c: Vector3i, max_c: Vector3i) -> void:
	## Auxiliary: Creates a new area spanning the specified bounding coordinates.
	if Colony == null or Colony.area_manager == null:
		return
	var created_area: Area = Colony.area_manager.create_area(min_c, max_c)
	GameLog.info("Created area '%s'" % created_area.display_name)


func _commit_paint_area(min_c: Vector3i, max_c: Vector3i) -> void:
	## Auxiliary: Adds a box to the target area and updates highlight meshes.
	if Colony == null or Colony.area_manager == null or target_area_id == "":
		return
	var updated_area: Area = Colony.area_manager.paint_area(target_area_id, min_c, max_c)
	if updated_area != null:
		GameLog.info("Painted area '%s'" % updated_area.display_name)
		# 1. In-World Highlight Refresh: Re-renders updated boxes of the painted area.
		_update_area_highlights()


func _commit_erase_area(min_c: Vector3i, max_c: Vector3i) -> void:
	## Auxiliary: Erases the bounding box from the target area, deleting if empty.
	if Colony == null or Colony.area_manager == null or target_area_id == "":
		return
	var updated_area: Area = Colony.area_manager.erase_area(target_area_id, min_c, max_c)
	if updated_area != null:
		GameLog.info("Erased from area '%s'" % updated_area.display_name)
		# 1. In-World Highlight Refresh: Re-renders remaining boxes of the erased area.
		_update_area_highlights()
	else:
		GameLog.info("Area deleted (no remaining boxes)")
		target_area_id = ""
		# 2. In-World Highlight Teardown: Clears all boxes since area was fully removed.
		_clear_area_highlights()


func _commit_chop_trees(min_c: Vector3i, max_c: Vector3i) -> void:
	## Auxiliary: Designates tree flora within the volume with chop orders.
	var fl: FurnitureLayer = _resolve_furniture_layer()
	if fl == null:
		return
	var flora_list: Array[WildFlora] = fl.get_wild_flora_in_box(min_c, max_c)
	var count: int = 0
	for flora in flora_list:
		if _is_tree_flora(flora):
			var harvestable := flora.get_node_or_null("Harvestable") as Harvestable
			if harvestable != null:
				harvestable.set_order_type("chop")
				harvestable.set_marked(true)
				count += 1
	GameLog.info("Designated %d trees for chop" % count)


func _commit_forage(min_c: Vector3i, max_c: Vector3i) -> void:
	## Auxiliary: Designates fruit-bearing bushes within the volume with forage orders.
	var fl: FurnitureLayer = _resolve_furniture_layer()
	if fl == null:
		return
	var flora_list: Array[WildFlora] = fl.get_wild_flora_in_box(min_c, max_c)
	var count: int = 0
	for flora in flora_list:
		if _is_forageable_flora(flora):
			var harvestable := flora.get_node_or_null("Harvestable") as Harvestable
			if harvestable != null:
				harvestable.set_order_type("forage")
				harvestable.set_marked(true)
				count += 1
	GameLog.info("Designated %d bushes for forage" % count)


func _commit_remove_plants(min_c: Vector3i, max_c: Vector3i) -> void:
	## Auxiliary: Designates all wild flora within the volume with removal orders.
	var fl: FurnitureLayer = _resolve_furniture_layer()
	if fl == null:
		return
	var flora_list: Array[WildFlora] = fl.get_wild_flora_in_box(min_c, max_c)
	var count: int = 0
	for flora in flora_list:
		var harvestable := flora.get_node_or_null("Harvestable") as Harvestable
		if harvestable != null:
			harvestable.set_order_type("remove")
			harvestable.set_marked(true)
			count += 1
	GameLog.info("Designated %d plants for removal" % count)


func _commit_cancel_orders(min_c: Vector3i, max_c: Vector3i) -> void:
	## Auxiliary: Cancels any active harvestable orders within the volume.
	var fl: FurnitureLayer = _resolve_furniture_layer()
	if fl == null:
		return
	var all_furniture: Array[Furniture] = fl.get_furniture_in_box(min_c, max_c)
	var count: int = 0
	for furniture in all_furniture:
		var harvestable := furniture.get_node_or_null("Harvestable") as Harvestable
		if harvestable != null and harvestable.is_marked_for_harvest():
			harvestable.set_marked(false)
			count += 1
	GameLog.info("Cancelled %d orders" % count)


func _is_tree_flora(flora: WildFlora) -> bool:
	## Auxiliary: Evaluates whether the given flora possesses tree or timber tags.
	return flora.has_tag("tree") or flora.has_tag("timber") or flora.has_tag("wood")


func _is_forageable_flora(flora: WildFlora) -> bool:
	## Auxiliary: Evaluates whether the given flora currently has fruit ready to forage.
	if flora == null or flora.is_queued_for_deletion():
		return false
	return flora.can_forage()


func _update_area_highlights() -> void:
	## Auxiliary: Rebuilds translucent 3D box meshes representing the target area's footprint.
	_clear_area_highlights()
	if Colony == null or Colony.area_manager == null or target_area_id == "":
		return
	if active_tool != "paint_area" and active_tool != "erase_area":
		return

	var area: Area = Colony.area_manager.get_area(target_area_id)
	if area == null:
		return

	var highlight_color := Color(0.2, 0.6, 1.0, 0.35) if active_tool == "paint_area" else Color(1.0, 0.4, 0.2, 0.35)
	for box in area.boxes:
		var min_c: Vector3i = box.get("min", Vector3i.ZERO)
		var max_c: Vector3i = box.get("max", Vector3i.ZERO)
		var mesh_instance: MeshInstance3D = _create_box_mesh_instance(min_c, max_c, highlight_color)
		_highlight_root.add_child(mesh_instance)


func _clear_area_highlights() -> void:
	## Auxiliary: Removes all currently displayed area highlight meshes.
	if _highlight_root == null:
		return
	for child in _highlight_root.get_children():
		child.queue_free()


func _create_box_mesh_instance(min_c: Vector3i, max_c: Vector3i, color: Color) -> MeshInstance3D:
	## Auxiliary: Constructs a translucent MeshInstance3D spanning the given cell volume.
	var size := Vector3(
		float(max_c.x - min_c.x + 1),
		float(max_c.y - min_c.y + 1),
		float(max_c.z - min_c.z + 1)
	)
	var center := Vector3(min_c) + size / 2.0

	var box_mesh := BoxMesh.new()
	box_mesh.size = size

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color

	var inst := MeshInstance3D.new()
	inst.mesh = box_mesh
	inst.material_override = mat
	inst.global_position = center
	return inst


func _resolve_camera_fallback() -> void:
	## Auxiliary: Resolves default viewport camera if not explicitly injected.
	if _camera == null:
		_camera = get_viewport().get_camera_3d()


func _resolve_grid_adapter_fallback() -> void:
	## Auxiliary: Resolves parent Map's VoxelGridAdapter if not explicitly injected.
	if grid_adapter == null:
		var parent_node := get_parent()
		if parent_node != null and parent_node.has_method("get_blocky_grid"):
			grid_adapter = VoxelGridAdapter.new()
			grid_adapter.set_grid(parent_node.call("get_blocky_grid"))
			if parent_node.has_method("get_smooth_grid"):
				grid_adapter.set_smooth_grid(parent_node.call("get_smooth_grid"))


func _resolve_furniture_layer() -> FurnitureLayer:
	## Auxiliary: Resolves FurnitureLayer dependency from property or scene tree.
	if furniture_layer != null:
		return furniture_layer
	var parent_node := get_parent()
	if parent_node != null:
		var build_ctrl := parent_node.find_child("BuildController", true, false) as BuildController
		if build_ctrl != null and build_ctrl.furniture_layer != null:
			furniture_layer = build_ctrl.furniture_layer
			return furniture_layer
	var scene_root := get_tree().current_scene if get_tree() != null else null
	if scene_root != null:
		var build_ctrl := scene_root.find_child("BuildController", true, false) as BuildController
		if build_ctrl != null and build_ctrl.furniture_layer != null:
			furniture_layer = build_ctrl.furniture_layer
			return furniture_layer
	return furniture_layer


func _resolve_player_exclusion_fallback() -> void:
	## Auxiliary: Finds and excludes local player body from raycast collisions.
	if exclude_bodies.is_empty():
		var player_body := GameState.get_local_player() as PhysicsBody3D
		if player_body == null and get_parent() != null:
			player_body = get_parent().find_child("Player", true, false) as PhysicsBody3D
		if player_body != null:
			add_exclude_body(player_body)


func _exclude_rids() -> Array:
	## Auxiliary: Converts registered exclude bodies into an array of RIDs for physics queries.
	var rids: Array = []
	for body in exclude_bodies:
		if is_instance_valid(body):
			rids.append(body.get_rid())
	return rids


func _perform_screen_raycast() -> Dictionary:
	## Auxiliary: Performs a screen-center raycast through the voxel grid adapter.
	var center := get_viewport().get_visible_rect().size / 2.0
	var origin := _camera.project_ray_origin(center)
	var dir := _camera.project_ray_normal(center)
	return grid_adapter.raycast_to_voxel(origin, dir, _RAY_DISTANCE, _exclude_rids())


func _extract_hit_world_position(hit: Dictionary) -> Vector3:
	## Auxiliary: Extracts exact world coordinate from smooth hit point or blocky cell center.
	var surface: String = hit.get("surface", "")
	if surface == "smooth":
		return hit.get("smooth_point", Vector3.ZERO) as Vector3
	var cell: Vector3i = hit.get("position", Vector3i.ZERO) as Vector3i
	return Vector3(float(cell.x) + 0.5, float(cell.y) + 0.5, float(cell.z) + 0.5)


func _query_stand_cell(world_pos: Vector3) -> Vector3i:
	## Auxiliary: Queries Colony autoload for the walkable stand cell at the column.
	if Colony != null:
		return Colony.find_stand_cell(world_pos)
	return Vector3i(int(floor(world_pos.x)), int(floor(world_pos.y)), int(floor(world_pos.z)))


func _update_preview_ghost() -> void:
	## Auxiliary: Updates GhostPreview position and dimensions to reflect current selection.
	if _ghost == null:
		return
	var corner_start := _corner_a if _stage == Stage.CORNER_A_PICKED else _current_stand_cell
	var bounds: Dictionary = compute_area_bounds(corner_start, _current_stand_cell)
	var min_c: Vector3i = bounds["min_cell"]
	var max_c: Vector3i = bounds["max_cell"]

	var size := Vector3(
		float(max_c.x - min_c.x + 1),
		float(max_c.y - min_c.y + 1),
		float(max_c.z - min_c.z + 1)
	)
	var center := Vector3(min_c) + size / 2.0
	var is_destructive := (active_tool == "erase_area" or active_tool == "cancel_orders")
	_ghost.show_box_at(center, size, not is_destructive)
