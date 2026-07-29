class_name BuildController
extends Node3D
## Build-mode controller (ARCH "Class: BuildController", lines 478-491).
## Active only when Player.mode == BLUEPRINT. Owns the cursor raycast, ghost
## preview, rotation state, and commit. Delegates commit resolution to an
## IPlacementStrategy and grid queries to an IBlockGrid (VoxelGridAdapter) — it
## never touches voxel_tool directly.
##
## This pass: ghost-follows-cursor works (raycast from camera, snap to the
## adjacent empty voxel of the face under the cursor, tint by validity). Placement
## is a stub (InstantPlacementStrategy.commit warns). Rotation is a stub.

const _RAY_DISTANCE := 30.0

# Runtime-wired (not @export: VoxelGridAdapter/InstantPlacementStrategy extend
# RefCounted, which Godot can't export). Set by the world/test after instantiation.
var grid_adapter: VoxelGridAdapter
var strategy: InstantPlacementStrategy
@export var camera_path: NodePath = ^""   # set in scene or via set_camera()

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
	EventBus.blueprint_mode_toggled.connect(_on_blueprint_mode_toggled)
	# Selected buildable arrives the same way — Player relays it from the build menu.
	EventBus.buildable_selected.connect(_on_buildable_selected)
	# Start inactive (NORMAL mode). Ghost is hidden in its own _ready.
	_update_activation()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	# LMB = place (routed to the stub strategy), RMB = remove (stub).
	# Rotation keys (R / mouse wheel) would route to rotation_state here.
	if event.is_action_pressed("build_place"):
		_try_commit()
	elif event.is_action_pressed("build_remove"):
		_try_remove()


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
	# Placement cell = the struck voxel + the face normal (the adjacent empty cell
	# where a new block would go).
	var cell: Vector3i = hit["position"] + hit["normal"]
	var valid := grid_adapter.is_valid_placement(cell)
	_ghost.show_at(cell, valid)


## Enable/disable the controller (called on blueprint_mode_toggled).
func set_active(active: bool) -> void:
	_active = active
	_update_activation()


## Runtime camera wiring (controller is a sibling of the player, so it can't use
## a relative path). Called by the world/test after the player exists.
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


func _on_blueprint_mode_toggled(active: bool) -> void:
	set_active(active)


func _on_buildable_selected(id: String) -> void:
	selected_id = id
	_set_ghost_mesh()


func _set_ghost_mesh():
	var def := BuildLibrary.get_def(selected_id)
	if def == null:
		return
	_ghost.mesh = def.mesh

func _try_commit() -> void:
	if strategy == null or grid_adapter == null or _camera == null:
		return
	# Recompute the target cell (mirrors _physics_process) and hand the transform
	# to the strategy. Strategy is a stub — warns and places nothing this pass.
	var center := get_viewport().get_visible_rect().size / 2.0
	var origin := _camera.project_ray_origin(center)
	var dir := _camera.project_ray_normal(center)
	var hit := grid_adapter.raycast_to_voxel(origin, dir, _RAY_DISTANCE, _exclude_rids())
	if not hit.get("hit", false):
		return
	var cell: Vector3i = hit["position"] + hit["normal"]
	if not grid_adapter.is_valid_placement(cell):
		return
	var t := Transform3D.IDENTITY
	t.origin = Vector3(cell)
	strategy.commit(t, rotation_state, selected_id)


func _try_remove() -> void:
	# TODO: route removal through a strategy or grid_adapter.get_grid().remove_block_at.
	push_warning("BuildController: remove not implemented (stub)")
