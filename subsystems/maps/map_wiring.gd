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


## Ensure the map's ItemsLayer exists and is registered in WorldItem's layer group,
## which is how WorldItem.spawn_at finds where loose items belong. Idempotent, so a
## re-wired map reuses its layer. Must run before anything on the map can spawn an
## item (flora, colonists, mining). Returns the layer.
static func wire_items(map: Map) -> Node3D:
	var layer := map.get_items_container()
	if not layer.is_in_group(WorldItem.ITEMS_LAYER_GROUP):
		layer.add_to_group(WorldItem.ITEMS_LAYER_GROUP)
	return layer


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


## Wire player area designation tool (AreaDesignationController).
## Injects the VoxelGridAdapter into the controller.
static func wire_areas(map: Map) -> void:
	var grid: BlockyGrid = map.get_blocky_grid()
	var adapter := VoxelGridAdapter.new()
	adapter.set_grid(grid)
	adapter.set_smooth_grid(_live_smooth_grid(map))

	var area_ctrl := map.find_child("AreaDesignationController", true, false) as AreaDesignationController
	if area_ctrl == null:
		area_ctrl = preload("res://subsystems/areas/area_designation_controller.tscn").instantiate()
		area_ctrl.name = "AreaDesignationController"
		map.add_child(area_ctrl)
	area_ctrl.grid_adapter = adapter
	var build_ctrl := map.find_child("BuildController", true, false) as BuildController
	if build_ctrl != null:
		area_ctrl.furniture_layer = build_ctrl.furniture_layer


## Wire HarvestBoxController: player area-designation tool for wild flora
## (ARCH "Wild Flora"). Needs only the FurnitureLayer (get_wild_flora_in_box) —
## no VoxelGridAdapter, unlike DigBoxController's voxel-terrain designation.
static func wire_harvest_box(map: Map, furniture_layer: FurnitureLayer) -> void:
	var ctrl := map.find_child("HarvestBoxController", true, false) as HarvestBoxController
	if ctrl == null:
		ctrl = HarvestBoxController.new()
		ctrl.name = "HarvestBoxController"
		map.add_child(ctrl)
	ctrl.furniture_layer = furniture_layer


## Wire dynamic day/night celestial lighting into the map.
## Replaces legacy static DirectionalLight3D with an instanced DayNightCycle.
static func wire_day_night(map: Map) -> void:
	if map.find_child("DayNightCycle", true, false) != null:
		return
	var static_light := map.find_child("DirectionalLight3D", true, false)
	if static_light != null:
		static_light.queue_free()
	var cycle_scene: PackedScene = load("res://subsystems/environment/day_night_cycle.tscn")
	if cycle_scene != null:
		var cycle: Node3D = cycle_scene.instantiate() as Node3D
		var env_container := map.find_child("EnvironmentContainer", true, false)
		if env_container != null:
			env_container.add_child(cycle)
		else:
			map.add_child(cycle)


## Wire dynamic flora regeneration (PlantSpawner) into the map.
static func wire_flora(map: Map, map_def: MapDef, furniture_layer: FurnitureLayer) -> PlantSpawner:
	if map == null or map_def == null:
		return null
	var spawner := map.find_child("PlantSpawner", true, false) as PlantSpawner
	if spawner == null:
		spawner = PlantSpawner.new()
		spawner.name = "PlantSpawner"
		var env_container := map.find_child("EnvironmentContainer", true, false)
		if env_container != null:
			env_container.add_child(spawner)
		else:
			map.add_child(spawner)
	spawner.setup(map, map_def, furniture_layer)
	return spawner


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
	var area_ctrl := map.find_child("AreaDesignationController", true, false) as AreaDesignationController
	if area_ctrl != null:
		area_ctrl.set_camera(player.get_camera())
		area_ctrl.add_exclude_body(player)
	var harvest_box_ctrl := map.find_child("HarvestBoxController", true, false) as HarvestBoxController
	if harvest_box_ctrl != null:
		harvest_box_ctrl.set_camera(player.get_camera())
		harvest_box_ctrl.add_exclude_body(player)


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

	# 1. Cost Wiring: Injects traversal cost multiplier (e.g. water wading penalty) into colonists.
	var cell_cost := _compose_cell_cost(map)
	Colony.set_cell_cost_fn(cell_cost)

	# 2. Bounds Wiring: Injects discrete playable volume bounds into Colony for world item validation.
	Colony.set_world_bounds(map.get_world_bounds())

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
	var base_walkable := compose_walkability(probe, fl, bl)
	var bounds: AABB = map.get_world_bounds()
	return func(cell: Vector3i) -> bool:
		if not bounds.has_point(Vector3(float(cell.x) + 0.5, float(cell.y) + 0.5, float(cell.z) + 0.5)):
			return false
		return bool(base_walkable.call(cell))


## Composes the traversal cost multiplier callback for cells (e.g. water wading penalty).
static func _compose_cell_cost(map: Map) -> Callable:
	var grid: BlockyGrid = map.get_blocky_grid()
	return func(cell: Vector3i) -> float:
		if grid != null and grid.get_block_at(cell) == "water":
			return 2.0
		return 0.0


## Blocky-only ground probe: a cell is standable iff it is air, has a solid
## floor below, and has head clearance above (the 1.6 m capsule spans two 1 m
## cells — without this check colonists path into 1-high gaps and grind against
## the ceiling forever). Takes get_block_at as a Callable so the probe composes
## over any blocky-grid-shaped source (and so tests stub it freely).
static func blocky_ground_probe(get_block_at: Callable) -> Callable:
	const DOWN := Vector3i(0, -1, 0)
	const UP := Vector3i(0, 1, 0)
	return func(cell: Vector3i) -> bool:
		var curr: String = get_block_at.call(cell)
		if curr != "" and curr != "water":             # solid obstacle (blocks, furniture)
			return false
		var floor_val: String = get_block_at.call(cell + DOWN)
		if floor_val == "" or floor_val == "water":     # no solid floor below (cannot stand on air or deep water)
			return false
		var head_val: String = get_block_at.call(cell + UP)
		if head_val != "" and head_val != "water":      # no head clearance
			return false
		if curr == "water" and head_val == "water":     # submerged in deep water (> 1 cell depth)
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
				var cave_curr: String = get_block_at.call(cell)
				if cave_curr != "" and cave_curr != "water":
					return false
				var cave_head: String = get_block_at.call(cell + UP)
				if cave_head != "" and cave_head != "water":
					return false
				if cave_curr == "water" and cave_head == "water":
					return false
				var cave_floor: String = get_block_at.call(cell + DOWN)
				if (cave_floor != "" and cave_floor != "water") or floor_in_terrain:
					return true
				return false
				
			if h >= float(cell.y):
				# Smooth surface within this cell: stand on it. Blocky must not
				# occupy the stand cell (air or water) nor the head cell above (the 1.6 m
				# capsule spans two cells — same clearance as the blocky probe).
				var surf_curr: String = get_block_at.call(cell)
				if surf_curr != "" and surf_curr != "water":
					return false
				var surf_head: String = get_block_at.call(cell + UP)
				if (surf_head != "" and surf_head != "water") or head_in_terrain:
					return false
				if surf_curr == "water" and surf_head == "water":
					return false
				var n: Vector3 = normals[0] if normals.size() > 0 else Vector3.UP
				return n.y >= min_normal_y

		# No smooth surface in or above this cell (or no smooth terrain here at
		# all): plain blocky rules, identical to a smooth-less map.
		var block_curr: String = get_block_at.call(cell)
		if block_curr != "" and block_curr != "water":             # solid (terrain/block)
			return false
		var block_floor: String = get_block_at.call(cell + DOWN)
		if (block_floor == "" or block_floor == "water") and not floor_in_terrain:      # no floor below
			return false
		var block_head: String = get_block_at.call(cell + UP)
		if (block_head != "" and block_head != "water") or head_in_terrain:        # no head clearance
			return false
		if block_curr == "water" and block_head == "water":
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

	var predicate := _compose_walkability(map)
	var smooth := _live_smooth_grid(map)
	var stand_hint := smooth_stand_hint(smooth) if smooth != null else Callable()

	var enemy_scene := preload("res://subsystems/combat/enemies/enemy_swarmer/enemy_swarmer.tscn")
	for spawn_pos in enemy_positions:
		var pos: Vector3 = spawn_pos
		var ground_y := map.ground_height_at(pos.x, pos.z)
		if not is_nan(ground_y):
			pos.y = ground_y + 1.0
		else:
			pos.y += 1.0
		var enemy := enemy_scene.instantiate() as EnemyBase
		enemy.position = pos
		container.add_child(enemy)

		# 1. Pathfinder Wiring: Injects map walkability and smooth stand hint into enemy pathfinder.
		wire_enemy_pathfinder(enemy, map)
	return container


## Configures an enemy's VoxelPathfinder with the map's walkability predicate and smooth surface stand hints.
static func wire_enemy_pathfinder(enemy: EnemyBase, map: Map) -> void:
	if enemy == null or enemy.pathfinder == null or map == null:
		return
	var predicate := _compose_walkability(map)
	enemy.pathfinder.set_walkability(predicate)
	# 1. Cost Wiring: Injects traversal cost multiplier into enemy pathfinder.
	var cell_cost := _compose_cell_cost(map)
	enemy.pathfinder.set_cell_cost(cell_cost)
	var smooth := _live_smooth_grid(map)
	if smooth != null:
		var stand_hint := smooth_stand_hint(smooth)
		if stand_hint.is_valid():
			enemy.pathfinder.set_stand_cell_hint(stand_hint)


## Instantiates or mounts the NightRaidController on the active map scene.
static func wire_raids(map: Map) -> NightRaidController:
	if map == null:
		return null
	var existing := map.find_child("NightRaidController", true, false) as NightRaidController
	if existing != null:
		existing.map = map
		return existing
	var controller := NightRaidController.new()
	controller.name = "NightRaidController"
	controller.map = map
	map.add_child(controller)
	return controller

