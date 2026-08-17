class_name BuildController
extends Node3D
## Build-mode controller (ARCH "Class: BuildController", lines 478-491).
## Active only when Player.mode == BUILD_PLACEMENT. Owns the cursor raycast, ghost
## preview, rotation state, and commit. Commit is delegated to an
## IPlacementStrategy — the controller is oblivious to whether that strategy
## materializes the buildable instantly (InstantPlacementStrategy) or spawns a
## blueprint for the player/colonists to complete later (BlueprintPlacementStrategy).
## It does per-kind VALIDITY only (block = air; furniture = free footprint),
## neither overlapping an existing blueprint, then hands off the same way for both.
## Grid queries go through the VoxelGridAdapter (IBlockGrid) — voxel_tool is
## never touched directly.
##
## This pass: ghost-follows-cursor works for both kinds (single cell for blocks,
## footprint center for furniture). LMB places via the strategy. RMB removes
## (blocks at the struck voxel, furniture/blueprint at the occupied cell).
## Rotation is wired: mouse wheel cycles the 90° step (visible on furniture),
## R cycles the rotation axis (no visible effect on cube blocks yet).

const _RAY_DISTANCE := 30.0
const DEBUG_RAYCAST := false

# Runtime-wired (not @export: VoxelGridAdapter/FurnitureLayer/BlueprintLayer
# and the placement strategies extend RefCounted, which Godot can't export). Set
# by the map/test after instantiation.
var grid_adapter: VoxelGridAdapter
# Duck-typed against IPlacementStrategy (documentation-only contract — see
# i_placement_strategy.gd). Held untyped so either InstantPlacementStrategy or
# BlueprintPlacementStrategy can be wired without a parse-time base-class dance.
var strategy
var furniture_layer: FurnitureLayer
var blueprint_layer: BlueprintLayer
@export var camera_path: NodePath = ^"" # set in scene or via set_camera()

var rotation_state := RotationState.new()

var _ghost: GhostPreview
var _camera: Camera3D
var _active := false
# The currently selected buildable id. Set via EventBus.buildable_selected (the
# build menu -> Player -> here). Used by the placement strategy on commit.
# TODO: also drive the ghost mesh from this.
var selected_id: String = ""
# Physics bodies to exclude from the cursor raycast (the player capsule, etc.).
# The third-person camera ray would otherwise hit the player before the terrain.
var exclude_bodies: Array[PhysicsBody3D] = []


func _ready() -> void:
	_ghost = $GhostPreview
	if camera_path != ^"" and has_node(camera_path):
		_camera = get_node(camera_path)
	# Blueprint mode is global; listen for the toggle (ARCH Player flow, line 388).
	EventBus.build_placement_toggled.connect(_on_build_placement_toggled)
	# Selected buildable arrives the same way — Player relays it from the build menu.
	EventBus.buildable_selected.connect(_on_buildable_selected)
	# Start inactive (NORMAL mode). Ghost is hidden in its own _ready.
	_update_activation()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	# Placement stays armed across screen opens (e.g. the world map over
	# placement), but its keys must not — this reads actions directly, outside
	# InputComponent, so the UiGate check is on us (see docs ui.md).
	if UiGate.is_input_blocked():
		return
	# LMB = place (routed to the strategy), RMB = remove.
	# Wheel = rotate 90° step, R = cycle rotation axis (GDD §4 controls table).
	# In Deconstruct, LMB also removes — the mode is removal-only.
	if event.is_action_pressed("build_place"):
		if BuildLibrary.is_deconstruct(selected_id):
			_try_remove()
		else:
			_try_commit()
	elif event.is_action_pressed("build_remove"):
		_try_remove()
	elif event.is_action_pressed("build_rotate_cw"):
		rotation_state.cycle_step()
	elif event.is_action_pressed("build_rotate_ccw"):
		rotation_state.cycle_step_back()
	elif event.is_action_pressed("build_rotate_axis"):
		rotation_state.cycle_axis()


func _physics_process(_delta: float) -> void:
	if not _active or _camera == null or grid_adapter == null:
		return
	# Screen-center ray from the camera (ARCH line 335).
	var center := get_viewport().get_visible_rect().size / 2.0
	var origin := _camera.project_ray_origin(center)
	var dir := _camera.project_ray_normal(center)
	var hit := grid_adapter.raycast_to_voxel(origin, dir, _RAY_DISTANCE, _exclude_rids())
	if not hit.get("hit", false):
		_ghost.hide_()
		return
	if BuildLibrary.is_deconstruct(selected_id):
		# The physics ray hits the target's collision directly (furniture and
		# blueprints have their own bodies), so the hit cell is itself the block
		# cell or an occupied cell. Try block, then furniture, then blueprint.
		var struck: Vector3i = hit["position"]
		if grid_adapter.get_block_at(struck) != "":
			# Block: red unit box on the struck cell.
			_ghost.show_remove_at(Vector3(struck))
		elif furniture_layer != null and furniture_layer.has_at(struck):
			# Furniture: red overlay of the targeted piece's own mesh, using its
			# placed transform so it sits exactly on the real furniture.
			var furn: Furniture = furniture_layer.get_furniture_at(struck)
			if furn != null and furn.def != null and furn.def.mesh != null:
				_ghost.show_remove_mesh_at(furn.global_position, furn.def.mesh, furn.rotation_degrees.y)
			else:
				_ghost.show_remove_at(Vector3(struck))
		elif blueprint_layer != null and blueprint_layer.has_at(struck):
			# Blueprint: red overlay of its target's mesh (or a unit box if the
			# target has no mesh, e.g. a voxel block).
			var bp: Blueprint = blueprint_layer.get_blueprint_at(struck)
			if bp != null and bp.def != null and bp.def.mesh != null:
				_ghost.show_remove_mesh_at(bp.global_position, bp.def.mesh, bp.rotation_degrees.y)
			else:
				_ghost.show_remove_at(Vector3(struck))
		else:
			_ghost.hide_()
		return
	# Placement cell = the struck voxel + the face normal (the adjacent empty cell
	# where a new block/furniture anchor would go). Smooth hits already carry the
	# derived cell — slope normals aren't axis-aligned offsets (D3).
	var cell: Vector3i = _placement_cell(hit)
	if DEBUG_RAYCAST:
		print("[DEBUG] hit pos=%s norm=%s cell=%s selected_id=%s" % [hit["position"], hit["normal"], cell, selected_id])
	var ghost_pos: Vector3
	var valid: bool
	if _is_furniture(selected_id):
		# Furniture: footprint center on XZ; valid only if every covered cell is free.
		ghost_pos = _furniture_ghost_pos(cell)
		valid = _is_footprint_free(cell, BuildLibrary.get_def(selected_id))
		if DEBUG_RAYCAST:
			print("[DEBUG] furniture ghost_pos=%s valid=%s" % [ghost_pos, valid])
	else:
		# Block (or nothing selected): single cell at the corner. Valid only if
		# the cell is air and not already covered by a blueprint.
		ghost_pos = Vector3(cell)
		valid = grid_adapter.is_valid_placement(cell) \
			and (blueprint_layer == null or not blueprint_layer.has_at(cell))
		if DEBUG_RAYCAST:
			print("[DEBUG] block ghost_pos=%s valid=%s" % [ghost_pos, valid])
	_ghost.show_at(ghost_pos, valid)
	# Rotate the ghost mesh to match the current step (visible for furniture;
	# harmless for rotation-symmetric cube blocks).
	_ghost.rotation_degrees.y = rotation_state.get_yaw_degrees()


## Enable/disable the controller (called on build_placement_toggled).
func set_active(active: bool) -> void:
	_active = active
	_update_activation()


## Runtime camera wiring (controller is a sibling of the player, so it can't use
## a relative path). Called by the map/test after the player exists.
func set_camera(camera: Camera3D) -> void:
	_camera = camera


## Add a physics body to the raycast exclusion list (e.g. the player capsule).
func add_exclude_body(body: PhysicsBody3D) -> void:
	if body != null and not exclude_bodies.has(body):
		exclude_bodies.append(body)


## RIDs to pass to PhysicsRayQueryParameters3D.exclude.
func _exclude_rids() -> Array:
	var rids: Array = []
	for body in exclude_bodies:
		rids.append(body.get_rid())
	return rids


func _update_activation() -> void:
	if not is_node_ready():
		return
	if _active:
		_ghost.show()
	else:
		_ghost.hide_()


func _on_build_placement_toggled(active: bool) -> void:
	set_active(active)


func _on_buildable_selected(id: String) -> void:
	selected_id = id
	# Deconstruct has no def mesh; _physics_process drives show_remove_at (which
	# resets the mesh itself) every frame.
	if not BuildLibrary.is_deconstruct(id):
		_set_ghost_mesh()


func _set_ghost_mesh():
	var def := BuildLibrary.get_def(selected_id)
	if def == null:
		return
	_ghost.mesh = def.mesh

func _try_commit() -> void:
	if grid_adapter == null or _camera == null or strategy == null or selected_id == "":
		return
	var def := BuildLibrary.get_def(selected_id)
	if def == null:
		return
	# Recompute the target cell (mirrors _physics_process).
	var center := get_viewport().get_visible_rect().size / 2.0
	var origin := _camera.project_ray_origin(center)
	var dir := _camera.project_ray_normal(center)
	var hit := grid_adapter.raycast_to_voxel(origin, dir, _RAY_DISTANCE, _exclude_rids())
	if not hit.get("hit", false):
		return
	var cell: Vector3i = _placement_cell(hit)
	# Per-kind VALIDITY only (block = air; furniture = free footprint), neither
	# overlapping an existing blueprint. Commit itself is the strategy's job —
	# instant or blueprint — so the controller hands off the same way for both.
	if def is BlockDef:
		if not grid_adapter.is_valid_placement(cell):
			return
		if blueprint_layer != null and blueprint_layer.has_at(cell):
			return
	else:
		if not _is_footprint_free(cell, def):
			return
	var t := Transform3D.IDENTITY
	t.origin = Vector3(cell)
	strategy.commit(t, rotation_state, selected_id)


func _try_remove() -> void:
	if grid_adapter == null or _camera == null:
		return
	var center := get_viewport().get_visible_rect().size / 2.0
	var origin := _camera.project_ray_origin(center)
	var dir := _camera.project_ray_normal(center)
	var hit := grid_adapter.raycast_to_voxel(origin, dir, _RAY_DISTANCE, _exclude_rids())
	if not hit.get("hit", false):
		return
	# The physics ray hits the target's collision directly (furniture/blueprints
	# have their own bodies), so the hit cell is itself the block cell or an
	# occupied furniture/blueprint cell. Try block, then furniture, then blueprint.
	var struck: Vector3i = hit["position"]
	if grid_adapter.get_block_at(struck) != "":
		grid_adapter.remove_block_at(struck)
		return
	if furniture_layer != null and furniture_layer.remove_at(struck):
		return
	if blueprint_layer != null and blueprint_layer.remove_blueprint_at(struck):
		return


# --- kind helpers -------------------------------------------------------------

## Placement cell from a raycast hit. Blocky/body hits resolve to the struck
## cell + face normal; smooth hits come pre-derived (floor(point + normal*0.5))
## with a zero normal, so they are taken as-is. Smooth-hit cells skip the
## "supported?" question until Phase 3's support check lands (D3).
func _placement_cell(hit: Dictionary) -> Vector3i:
	if hit.get("surface", "") == "smooth":
		return hit["position"]
	return hit["position"] + hit["normal"]

## True if the selected id is a non-block (free-standing) buildable. Reads the
## catalog so the def shape (BlockDef vs not) drives routing everywhere.
func _is_furniture(id: String) -> bool:
	if id == "":
		return false
	var def := BuildLibrary.get_def(id)
	return def != null and not (def is BlockDef)


## World-space origin for the furniture ghost: footprint center on XZ, anchor Y.
func _furniture_ghost_pos(cell: Vector3i) -> Vector3:
	var def := BuildLibrary.get_def(selected_id)
	var dims := FurnitureLayer.dimensions_of(def)
	return FurnitureLayer.world_origin(cell, dims, rotation_state.step)


## Every covered cell of the (yaw-rotated) footprint must be air, free of
## furniture, and free of an existing blueprint.
func _is_footprint_free(anchor: Vector3i, def: BuildableDef) -> bool:
	var dims := FurnitureLayer.dimensions_of(def)
	for off in FurnitureLayer.footprint_cells(dims, rotation_state.step):
		var c: Vector3i = anchor + off
		if not grid_adapter.is_valid_placement(c):
			return false
		if furniture_layer != null and furniture_layer.has_at(c):
			return false
		if blueprint_layer != null and blueprint_layer.has_at(c):
			return false
	return true
