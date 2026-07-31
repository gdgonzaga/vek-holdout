class_name WorldWiring
extends RefCounted
## Static utilities for wiring a World's subsystems at runtime.
##
## Extracts the canonical wiring pattern proven in testing/build/build_test.gd
## (lines 40-55) so SceneManager reuses one source of truth instead of
## duplicating adapter/strategy/FurnitureLayer/camera plumbing per swap.
##
## Requires a one-frame deferral (await get_tree().process_frame) AFTER world
## instantiation so child _ready calls (esp. CameraRig camera build) have run
## before wire_build/wire_player read them. NOTE: that deferral is for camera
## wiring ONLY — not for voxel writes (those need the region streamed, ~40 frames
## for a fresh process targeting an unloaded coordinate; see IMPLEMENTATION.md F3).


## Wire BuildController deps (adapter -> grid, strategy -> adapter,
## FurnitureLayer -> container). Returns the FurnitureLayer (or null if the world
## has no BuildController or the wiring is incomplete).
static func wire_build(world: World) -> FurnitureLayer:
	var ctrl := world.find_child("BuildController") as BuildController
	if ctrl == null:
		return null
	var grid: VoxelGrid = world.get_grid()
	var adapter := VoxelGridAdapter.new()
	adapter.set_grid(grid)
	ctrl.grid_adapter = adapter
	var strategy := InstantPlacementStrategy.new()
	strategy.set_grid(adapter)
	ctrl.strategy = strategy
	var fl := FurnitureLayer.new()
	fl.set_container(world.get_furniture_container())
	ctrl.furniture_layer = fl
	return fl


## Attach the player to the world and wire its camera into BuildController.
## Reuses an existing VoxelViewer on the player so repeated world swaps don't
## stack viewers (one per swap) — the first swap adds it, subsequent swaps find
## it already parented.
static func wire_player(world: World, player: Player) -> void:
	# VoxelViewer streams terrain + collision around the player. BuildController's
	# physics raycast (VoxelGrid.raycast_to_voxel) only hits something once chunks
	# exist there, so the viewer must precede any build interaction.
	var viewer := player.get_node_or_null("VoxelViewer")
	if viewer == null:
		viewer = VoxelViewer.new()
		viewer.name = "VoxelViewer"
		viewer.requires_visuals = true
		# requires_collision is version-uncertain in this GDExtension build — the
		# codebase only ever sets it defensively via `in` + set() (see the 5
		# testing/ call sites), never as a typed property. requires_visuals IS a
		# real property. Keep the guard.
		if "requires_collision" in viewer:
			viewer.set("requires_collision", true)
		player.add_child(viewer)
	var ctrl := world.find_child("BuildController") as BuildController
	if ctrl != null:
		ctrl.set_camera(player.get_camera())
		ctrl.add_exclude_body(player)
