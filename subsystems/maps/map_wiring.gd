class_name MapWiring
extends RefCounted
## Static utilities for wiring a Map's subsystems at runtime.
##
## Extracts the canonical wiring pattern proven in testing/build/build_test.gd
## (lines 40-55) so SceneManager reuses one source of truth instead of
## duplicating adapter/strategy/FurnitureLayer/camera plumbing per swap.
##
## Requires a one-frame deferral (await get_tree().process_frame) AFTER map
## instantiation so child _ready calls (esp. CameraRig camera build) have run
## before wire_build/wire_player read them. NOTE: that deferral is for camera
## wiring ONLY — not for voxel writes (those need the region streamed, ~40 frames
## for a fresh process targeting an unloaded coordinate; see IMPLEMENTATION.md F3).


## Wire BuildController deps (adapter -> grid, FurnitureLayer -> container,
## BlueprintLayer -> container/grid/furniture, strategy -> layers). Returns the
## FurnitureLayer (or null if the map has no BuildController).
##
## Active strategy is BlueprintPlacementStrategy: LMB spawns a blueprint the
## player completes by interacting (Build action) — the incremental step toward
## blueprint-then-build (GDD §7.4). Flip to InstantPlacementStrategy (with
## set_grid + set_furniture_layer) for the instant MVP/debug behavior.
static func wire_build(map: Map) -> FurnitureLayer:
	var ctrl := map.find_child("BuildController") as BuildController
	if ctrl == null:
		return null
	var grid: VoxelGrid = map.get_grid()
	var adapter := VoxelGridAdapter.new()
	adapter.set_grid(grid)
	ctrl.grid_adapter = adapter
	var fl := FurnitureLayer.new()
	fl.set_container(map.get_furniture_container())
	ctrl.furniture_layer = fl
	# Blueprint layer: sibling of FurnitureLayer; shares the container and the
	# adapter/furniture deps so it can size to and materialize the target.
	var bl := BlueprintLayer.new()
	bl.set_container(map.get_furniture_container())
	bl.set_grid(adapter)
	bl.set_furniture_layer(fl)
	ctrl.blueprint_layer = bl
	# Strategy goes through the layers (ARCH flow trace: strategy -> layers).
	var strategy := BlueprintPlacementStrategy.new()
	strategy.set_blueprint_layer(bl)
	ctrl.strategy = strategy
	return fl


## Attach the player to the map and wire its camera into BuildController.
## Reuses an existing VoxelViewer on the player so repeated map swaps don't
## stack viewers (one per swap) — the first swap adds it, subsequent swaps find
## it already parented.
static func wire_player(map: Map, player: Player) -> void:
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
	var ctrl := map.find_child("BuildController") as BuildController
	if ctrl != null:
		ctrl.set_camera(player.get_camera())
		ctrl.add_exclude_body(player)


## Hand the map's ColonistContainer + authored ColonistSpawn* positions to Colony
## so it can spawn into (empty roster) or reparent into (existing roster) this map,
## then inject each colonist's pathfinder with the walkability predicate. Returns
## the container (or null if the map has none). Called from SceneManager._wire_map
## after the player is wired.
static func wire_colonists(map: Map) -> Node3D:
	var container := map.get_colonist_container()
	if container == null:
		return null
	var spawns := SpawnHelpers.read_spawns(map)
	# Spawn/reparent first — add_child runs each colonist's _ready, which caches
	# its pathfinder field, before we inject below.
	Colony.on_map_wired(container, spawns.get("colonists", []))
	# Point the storage registry at this map's furniture container so hauling
	# jobs can live-scan its crates. Same wiring moment as colonists — per map
	# load, so base<->POI swaps rebind to the new map's crates.
	Colony.storage_registry.on_map_wired(map.get_furniture_container())
	# Inject the walkability predicate (voxel air-above-solid-floor, minus
	# furniture/blueprint occupancy) into every colonist's pathfinder. Re-run
	# per map load so base<->POI swaps pick up the new map's layers.
	var predicate := _compose_walkability(map)
	for c in Colony.colonists:
		if is_instance_valid(c) and c.pathfinder != null:
			c.pathfinder.set_walkability(predicate)
	return container


## Build the per-cell is_walkable Callable from the map's voxel grid + build
## layers. A cell is standable iff it is air, has a solid floor below, and is
## not occupied by furniture or a blueprint (colonist stands ADJACENT to a
## build target, never on its footprint).
static func _compose_walkability(map: Map) -> Callable:
	var grid: VoxelGrid = map.get_grid()
	var ctrl := map.find_child("BuildController") as BuildController
	var fl: FurnitureLayer = ctrl.furniture_layer if ctrl != null else null
	var bl: BlueprintLayer = ctrl.blueprint_layer if ctrl != null else null
	const DOWN := Vector3i(0, -1, 0)
	return func(cell: Vector3i) -> bool:
		if grid.get_block_at(cell) != "":             # solid (terrain/block)
			return false
		if grid.get_block_at(cell + DOWN) == "":      # no floor below
			return false
		if fl != null and fl.has_at(cell):
			return false
		if bl != null and bl.has_at(cell):
			return false
		return true
