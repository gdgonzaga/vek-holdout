class_name HarvestBoxController
extends Node3D
## Player area-designation tool for marking wild flora (trees, bushes, wild
## plants) for the colonist harvest labor in bulk (ARCH "Wild Flora"). Mirrors
## DigBoxController's raycast-and-commit UX, simplified to a flat ground
## footprint — flora sit on the ground, so there's no orientation/stairway
## mode to cycle.
##
## Resizing: Scroll Wheel adjusts Width (clamped 1..15); Shift + Scroll
## adjusts Depth (clamped 1..15). A generous fixed vertical span covers any
## flora height in the footprint regardless of hit point.
##
## Designation: LMB marks every WildFlora in the footprint for harvest via
## its Harvestable component (the same EventBus.harvest_mark_toggled path
## the E-menu single-tree toggle already uses, so Colony's job routing is
## unaffected). RMB un-marks instead.

const _RAY_DISTANCE := 30.0
## World | TerrainBlocky | TerrainSmooth (layers 1-3; project.godot [layer_names]).
const _RAY_COLLISION_MASK := 0b111
## Cells below/above the hit cell the footprint spans, covering any authored
## flora height (tallest current content is 4 cells).
const _BELOW_HIT := 1
const _ABOVE_HIT := 6

var furniture_layer: FurnitureLayer
var exclude_bodies: Array[PhysicsBody3D] = []

var width: int = 5
var depth: int = 5

var _camera: Camera3D
var _active: bool = false
var _preview: MeshInstance3D
var _has_valid_target: bool = false
var _last_cell: Vector3i = Vector3i.ZERO
var _last_rendered_cell := Vector3i.MAX
var _last_rendered_width := -1
var _last_rendered_depth := -1


func _ready() -> void:
	# 1. Preview Mesh Setup: A translucent footprint quad, hidden until active.
	_create_preview_mesh()
	EventBus.harvest_box_toggled.connect(_on_toggled)
	_update_activation()


## Enable or disable the controller.
func set_active(active: bool) -> void:
	_active = active
	_update_activation()


## Runtime camera wiring from the Player (MapWiring.wire_player).
func set_camera(camera: Camera3D) -> void:
	_camera = camera


## Add a physics body (the player capsule) to the raycast exclusion list.
func add_exclude_body(body: PhysicsBody3D) -> void:
	if body != null and not exclude_bodies.has(body):
		exclude_bodies.append(body)


func _unhandled_input(event: InputEvent) -> void:
	if not _active or UiGate.is_input_blocked():
		return
	if not (event is InputEventMouseButton) or not event.pressed:
		return

	var mouse_event := event as InputEventMouseButton
	var btn: int = mouse_event.button_index

	if btn == MOUSE_BUTTON_LEFT:
		# 1. Mark Commit: Designate every flora in the current footprint for harvest.
		_try_commit(true)
		get_viewport().set_input_as_handled()
	elif btn == MOUSE_BUTTON_RIGHT:
		# 2. Unmark Commit: Clear harvest designation from the current footprint.
		_try_commit(false)
		get_viewport().set_input_as_handled()
	elif btn == MOUSE_BUTTON_WHEEL_UP:
		if _resize(1 if mouse_event.shift_pressed else 0, 0 if mouse_event.shift_pressed else 1):
			get_viewport().set_input_as_handled()
	elif btn == MOUSE_BUTTON_WHEEL_DOWN:
		if _resize(-1 if mouse_event.shift_pressed else 0, 0 if mouse_event.shift_pressed else -1):
			get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if not _active:
		return
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
	if furniture_layer == null or _camera == null or get_world_3d() == null:
		_has_valid_target = false
		_preview.hide()
		return

	# 1. Player Exclusion Fallback: Ensure the raycast ignores the player capsule.
	_ensure_player_excluded()

	# 2. Ground Raycast: Find the cell the player is looking at.
	var hit := _raycast_ground()
	if hit.is_empty():
		_has_valid_target = false
		_preview.hide()
		return

	var hit_pos: Vector3 = hit.get("position", Vector3.ZERO)
	var cell := Vector3i(int(floor(hit_pos.x)), int(floor(hit_pos.y)), int(floor(hit_pos.z)))
	_has_valid_target = true
	_last_cell = cell
	_update_preview(cell)


func _on_toggled(active: bool) -> void:
	set_active(active)
	if active:
		width = 5
		depth = 5


func _update_activation() -> void:
	if not is_node_ready():
		return
	if not _active:
		_preview.hide()
		_has_valid_target = false


func _resize(depth_delta: int, width_delta: int) -> bool:
	## Auxiliary: Applies a clamped +/-1 change to width or depth, returns whether it changed.
	var changed := false
	if width_delta != 0:
		var new_w := clampi(width + width_delta, 1, 15)
		changed = new_w != width
		width = new_w
	if depth_delta != 0:
		var new_d := clampi(depth + depth_delta, 1, 15)
		changed = changed or new_d != depth
		depth = new_d
	return changed


func _ensure_player_excluded() -> void:
	## Auxiliary: Lazily adds the local player capsule to the raycast exclusion list.
	if not exclude_bodies.is_empty():
		return
	var player_body := GameState.get_local_player() as PhysicsBody3D
	if player_body != null:
		add_exclude_body(player_body)


func _raycast_ground() -> Dictionary:
	## Auxiliary: Raycasts screen-center against ground/terrain layers. Empty Dictionary if no hit.
	var space := get_world_3d().direct_space_state
	var center := get_viewport().get_visible_rect().size / 2.0
	var origin := _camera.project_ray_origin(center)
	var dir := _camera.project_ray_normal(center)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * _RAY_DISTANCE)
	query.collision_mask = _RAY_COLLISION_MASK
	var rids: Array = []
	for body in exclude_bodies:
		if is_instance_valid(body):
			rids.append(body.get_rid())
	query.exclude = rids
	return space.intersect_ray(query)


func _box_min(cell: Vector3i) -> Vector3i:
	return Vector3i(cell.x - int(width / 2.0), cell.y - _BELOW_HIT, cell.z - int(depth / 2.0))


func _box_max(cell: Vector3i) -> Vector3i:
	var left_w := int(width / 2.0)
	var left_d := int(depth / 2.0)
	return Vector3i(cell.x + (width - left_w - 1), cell.y + _ABOVE_HIT, cell.z + (depth - left_d - 1))


func _create_preview_mesh() -> void:
	## Auxiliary: Builds the translucent footprint MeshInstance3D child.
	_preview = MeshInstance3D.new()
	_preview.name = "Preview"
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.3, 0.9, 0.3, 0.35)
	_preview.material_override = mat
	_preview.hide()
	add_child(_preview)


func _update_preview(cell: Vector3i) -> void:
	## Auxiliary: Rebuilds/repositions the footprint mesh only when the shape changed.
	if cell == _last_rendered_cell and width == _last_rendered_width and depth == _last_rendered_depth:
		_preview.show()
		return
	_last_rendered_cell = cell
	_last_rendered_width = width
	_last_rendered_depth = depth

	var min_c := _box_min(cell)
	var max_c := _box_max(cell)
	var box := BoxMesh.new()
	box.size = Vector3(float(max_c.x - min_c.x + 1), 0.1, float(max_c.z - min_c.z + 1))
	_preview.mesh = box
	var center_x := (float(min_c.x) + float(max_c.x) + 1.0) * 0.5
	var center_z := (float(min_c.z) + float(max_c.z) + 1.0) * 0.5
	_preview.global_position = Vector3(center_x, float(cell.y) + 0.05, center_z)
	_preview.show()


func _try_commit(mark: bool) -> void:
	## Auxiliary: Marks/unmarks every WildFlora in the current footprint via Harvestable.
	if not _has_valid_target or furniture_layer == null:
		return

	var flora_list := furniture_layer.get_wild_flora_in_box(_box_min(_last_cell), _box_max(_last_cell))
	var toggled := _apply_mark_to_flora(flora_list, mark)
	_report_designation(toggled, flora_list.size(), mark)


func _apply_mark_to_flora(flora_list: Array[WildFlora], mark: bool) -> int:
	## Auxiliary: Toggles Harvestable.set_marked on each flora that isn't already in that state.
	var toggled := 0
	for flora in flora_list:
		var h := flora.get_node_or_null("Harvestable") as Harvestable
		if h == null or h.is_marked_for_harvest() == mark:
			continue
		h.set_marked(mark)
		toggled += 1
	return toggled


func _report_designation(toggled: int, considered: int, mark: bool) -> void:
	## Auxiliary: Logs the designation result to stdout and the GameLog HUD.
	print("[Harvest Designation] %s %d wild flora (out of %d in area)" % [
		"Marked" if mark else "Unmarked", toggled, considered
	])
	if toggled == 0:
		GameLog.info("No wild flora to %s in designated area" % ("mark" if mark else "unmark"))
	else:
		GameLog.info("%s %d plants for harvest" % ["Marked" if mark else "Unmarked", toggled])
