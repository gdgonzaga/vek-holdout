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
	var grid: BlockyGrid = map.get_blocky_grid()
	var adapter := VoxelGridAdapter.new()
	adapter.set_grid(grid)
	# Smooth half for ground-support queries on smooth placements (D3); null
	# adapter-side on terrain-less maps, so build validity is unchanged there.
	adapter.set_smooth_grid(_live_smooth_grid(map))
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
	# Smooth-material strategy (Phase 5): add-sphere placement of terrain
	# materials. Null grid on terrain-less maps — commit fails safe (false).
	var smooth_strategy := SmoothPlacementStrategy.new()
	smooth_strategy.set_smooth_grid(_live_smooth_grid(map))
	ctrl.smooth_strategy = smooth_strategy


	return fl


## Wire mining execution (MiningSystem) and player designation tool (DigBoxController).
## Injects the VoxelGridAdapter into both.
static func wire_mining(map: Map) -> void:
	var grid: BlockyGrid = map.get_blocky_grid()
	var adapter := VoxelGridAdapter.new()
	adapter.set_grid(grid)
	adapter.set_smooth_grid(_live_smooth_grid(map))

	# MiningSystem: map-level simulation node for marker management and terrain carving
	var mining_sys := map.find_child("MiningSystem", true, false) as MiningSystem
	if mining_sys == null:
		mining_sys = MiningSystem.new()
		mining_sys.name = "MiningSystem"
		map.add_child(mining_sys)
	mining_sys.set_grid_adapter(adapter)
	Colony.set_terrain_predicate(Callable(adapter, "is_terrain_at"))

	# DigBoxController: player UI tool for dig box designation
	var dig_ctrl := map.find_child("DigBoxController", true, false) as DigBoxController
	if dig_ctrl == null:
		dig_ctrl = preload("res://subsystems/mining/dig_box.tscn").instantiate()
		dig_ctrl.name = "DigBoxController"
		map.add_child(dig_ctrl)
	dig_ctrl.grid_adapter = adapter


## Attach the player to the map and wire its camera into BuildController.
## Reuses an existing VoxelViewer on the player so repeated map swaps don't
## stack viewers (one per swap) — the first swap adds it, subsequent swaps find
## it already parented.
static func wire_player(map: Map, player: Player) -> void:
	# VoxelViewer streams terrain + collision around the player. BuildController's
	# physics raycast (BlockyGrid.raycast_to_voxel) only hits something once chunks
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
		# The dig tool's timed action acts on the player (busy/yields/skill).
		ctrl.set_player(player)
	var dig_ctrl := map.find_child("DigBoxController", true, false) as DigBoxController
	if dig_ctrl != null:
		dig_ctrl.set_camera(player.get_camera())
		dig_ctrl.add_exclude_body(player)


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
	# Point the storage registry at this map's furniture container so hauling
	# jobs can live-scan its crates. Same wiring moment as colonists — per map
	# load, so base<->POI swaps rebind to the new map's crates.
	Colony.storage_registry.on_map_wired(map.get_furniture_container())
	# Inject the walkability predicate (voxel air-above-solid-floor, minus
	# furniture/blueprint occupancy) into every colonist's pathfinder. Re-run
	# per map load so base<->POI swaps pick up the new map's layers.
	var predicate := _compose_walkability(map)
	Colony.set_walkability_predicate(predicate)
	# Stand-cell hint + combined ground query follow the same per-map lifecycle.
	# Explicit reset on smooth-less maps: a stale hint would keep calling the
	# previous map's (freed) SmoothGrid after a base<->POI swap.
	var smooth := _live_smooth_grid(map)
	Colony.set_stand_cell_hint(smooth_stand_hint(smooth) if smooth != null else Callable())
	Colony.set_ground_query(Callable(map, "ground_height_at"))

	# Spawn/reparent colonists AFTER ground query and predicates are wired so
	# initial spawn height queries resolve correctly.
	Colony.on_map_wired(container, spawns.get("colonists", []))
	return container


## The map's smooth grid when it is actually live (exists, not freeing itself,
## and carries a generator); null on terrain-less maps — the default.
static func _live_smooth_grid(map: Map) -> SmoothGrid:
	var smooth := map.get_smooth_grid()
	if smooth != null and is_instance_valid(smooth) and smooth.terrain_gen != null:
		return smooth
	return null


## Build the per-cell is_walkable Callable for a map: an injectable ground
## probe ANDed with furniture/blueprint occupancy. The probe is the dual-voxel
## seam — blocky-only on terrain-less maps, the hybrid probe (docs/TODO.md D4)
## wherever the smooth grid is live.
static func _compose_walkability(map: Map) -> Callable:
	var grid: BlockyGrid = map.get_blocky_grid()
	var ctrl := map.find_child("BuildController") as BuildController
	var fl: FurnitureLayer = ctrl.furniture_layer if ctrl != null else null
	var bl: BlueprintLayer = ctrl.blueprint_layer if ctrl != null else null
	var smooth := _live_smooth_grid(map)
	var probe := blocky_ground_probe(Callable(grid, "get_block_at"))
	if smooth != null:
		var is_solid := Callable(smooth, "is_solid_at")
		probe = hybrid_ground_probe(Callable(grid, "get_block_at"),
				Callable(smooth, "height_at"), smooth.terrain_gen.max_walk_slope_deg, is_solid)
	return compose_walkability(probe, fl, bl)


## Blocky-only ground probe: a cell is standable iff it is air, has a solid
## floor below, and has head clearance above (the 1.6 m capsule spans two 1 m
## cells — without this check colonists path into 1-high gaps and grind against
## the ceiling forever). Takes get_block_at as a Callable so the probe composes
## over any blocky-grid-shaped source (and so tests stub it freely).
static func blocky_ground_probe(get_block_at: Callable) -> Callable:
	const DOWN := Vector3i(0, -1, 0)
	const UP := Vector3i(0, 1, 0)
	return func(cell: Vector3i) -> bool:
		if get_block_at.call(cell) != "":             # solid (terrain/block)
			return false
		if get_block_at.call(cell + DOWN) == "":      # no floor below
			return false
		if get_block_at.call(cell + UP) != "":        # no head clearance
			return false
		return true


## Dual-voxel ground probe (docs/TODO.md D4): a cell is standable when the
## smooth surface passes through it on a walkable slope (stand ON the hill),
## or — anywhere the smooth terrain doesn't reach the cell — when the plain
## blocky rules hold. `smooth_height_at` is SmoothGrid.height_at (cached
## column heights, NAN where the terrain doesn't reach); `max_slope_deg` comes
## from TerrainGenDef so per-map tuning is data-driven.
##
## Besides adding hill-top cells, the smooth source CANCELS blocky cells
## buried inside terrain: on maps where hills overlap the blocky plate, the
## plate-top column still reads as air-above-solid to the blocky rules, but a
## colonist routed there would grind into the hillside. This is the one place
## the hybrid probe may answer differently from a smooth-less map — D4
## Invariant 1 ("smooth only adds standable cells") holds verbatim for every
## structure standing clear of the surface; buried cells are terrain, not
## structures.
##
## D4 slope bound <= 45deg keeps derived stand cells within +/-1 per horizontal
## step, so the pathfinder's step model (climb +1, drop <= 3) needs no change.
static func hybrid_ground_probe(get_block_at: Callable, smooth_height_at: Callable, max_slope_deg: float, is_terrain_at: Callable = Callable()) -> Callable:
	const DOWN := Vector3i(0, -1, 0)
	const UP := Vector3i(0, 1, 0)
	var min_normal_y := cos(deg_to_rad(clampf(max_slope_deg, 0.0, 89.0))) - 0.01 # Float tolerance for exact 45-deg slopes
	return func(cell: Vector3i) -> bool:
		var normals: Array = []
		# Probe at the column center so the cached height answers for this
		# exact column, never the boundary between two.
		var h: float = smooth_height_at.call(float(cell.x) + 0.5, float(cell.z) + 0.5, normals)
		
		var has_terrain_query := is_terrain_at.is_valid()
		var cell_in_terrain: bool = is_terrain_at.call(cell) if has_terrain_query else false
		var head_in_terrain: bool = is_terrain_at.call(cell + UP) if has_terrain_query else false
		var floor_in_terrain: bool = is_terrain_at.call(cell + DOWN) if has_terrain_query else false

		if not is_nan(h):
			if h >= float(cell.y + 1):
				# Cell is below the mountain surface height.
				# If we have no terrain query or if the cell/head is solid terrain, it is buried.
				if not has_terrain_query or cell_in_terrain or head_in_terrain:
					return false
				# Otherwise, this is a hollowed out cave/tunnel below the surface.
				if get_block_at.call(cell) != "":
					return false
				if get_block_at.call(cell + UP) != "":
					return false
				if get_block_at.call(cell + DOWN) != "" or floor_in_terrain:
					return true
				return false
				
			if h >= float(cell.y):
				# Smooth surface within this cell: stand on it. Blocky must not
				# occupy the stand cell (air) nor the head cell above (the 1.6 m
				# capsule spans two cells — same clearance as the blocky probe).
				if get_block_at.call(cell) != "":
					return false
				if get_block_at.call(cell + UP) != "":
					return false
				if head_in_terrain:
					return false
				var n: Vector3 = normals[0] if normals.size() > 0 else Vector3.UP
				return n.y >= min_normal_y

		# No smooth surface in or above this cell (or no smooth terrain here at
		# all): plain blocky rules, identical to a smooth-less map.
		if get_block_at.call(cell) != "":             # solid (terrain/block)
			return false
		if get_block_at.call(cell + DOWN) == "" and not floor_in_terrain:      # no floor below
			return false
		if get_block_at.call(cell + UP) != "" or head_in_terrain:        # no head clearance
			return false
		return true


## Column stand-cell hint for the pathfinder (D4): resolves a column's stand Y
## from the smooth heightfield exactly as the hybrid probe derives it, so
## find_stand_cell / find_stand_near_cell agree with walkability instead of
## assuming flat ground. Vector3i.MAX where the smooth terrain doesn't reach —
## the finder then falls back to its flat assumption for that column.
static func smooth_stand_hint(smooth: SmoothGrid) -> Callable:
	return func(x: float, z: float) -> Vector3i:
		var h: float = smooth.height_at(x + 0.5, z + 0.5)
		if is_nan(h):
			return Vector3i.MAX
		return Vector3i(int(floor(x)), int(floor(h)), int(floor(z)))


## Compose the full is_walkable predicate: ground probe AND not occupied by
## non-steppable furniture or a blueprint (at the cell or overhead) — colonists
## stand ADJACENT to a build target, never on its footprint.
static func compose_walkability(ground_probe: Callable, fl: FurnitureLayer, bl: BlueprintLayer) -> Callable:
	const UP := Vector3i(0, 1, 0)
	## Furniture shorter than this is steppable — colonists walk over it
	## the same way the player does via StepClimber. Matches the colonist
	## scene's StepClimber.step_height (see colonist.tscn).
	const STEP_HEIGHT := 0.5
	return func(cell: Vector3i) -> bool:
		if not ground_probe.call(cell):
			return false
		if fl != null and fl.has_at(cell):
			if not fl.is_steppable_at(cell, STEP_HEIGHT):
				return false
		if bl != null and bl.has_at(cell):
			return false
		if fl != null and fl.has_at(cell + UP):       # furniture overhead
			if not fl.is_steppable_at(cell + UP, STEP_HEIGHT):
				return false
		if bl != null and bl.has_at(cell + UP):       # blueprint overhead
			return false
		return true


## Instantiate enemy prototypes into the map's EnemyContainer from authored EnemySpawn* markers or MapDef.enemy_spawns.
static func wire_enemies(map: Map, map_def: MapDef = null) -> Node3D:
	var container := map.get_enemy_container()
	if container == null:
		return null
	var spawns := SpawnHelpers.read_spawns(map)
	var enemy_positions: Array = spawns.get("enemies", [])
	if enemy_positions.is_empty() and map_def != null and not map_def.enemy_spawns.is_empty():
		for entry in map_def.enemy_spawns:
			if entry is Dictionary and entry.has("pos"):
				enemy_positions.append(entry["pos"])

	for child in container.get_children():
		child.queue_free()

	var enemy_scene := preload("res://subsystems/combat/enemies/enemy_swarmer/enemy_swarmer.tscn")
	for spawn_pos in enemy_positions:
		var pos: Vector3 = spawn_pos
		var ground_y := map.ground_height_at(pos.x, pos.z)
		if not is_nan(ground_y):
			pos.y = ground_y + 1.0
		else:
			pos.y += 1.0
		var enemy := enemy_scene.instantiate() as Node3D
		enemy.position = pos
		container.add_child(enemy)
	return container
