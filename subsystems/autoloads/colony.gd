extends Node
## Colony autoload (ARCH "Subsystem: Colonists"). Cross-scene singleton —
## colonists persist base↔POI.
##
## Owns the colonist roster + the Job Board. Construction jobs are produced from
## blueprint placement (EventBus.blueprint_placed/removed → Job). Colonist NODES
## live in the current map's ColonistContainer; this autoload owns the roster data
## and spawns/reparents into that container on each map wire
## (MapWiring.wire_colonists → on_map_wired), mirroring how SceneManager reparents
## the persistent Player between maps.
##
## Known gaps:
##   - Save-load restore suppresses per-blueprint blueprint_placed emits
##     (BlueprintLayer._is_restoring), so jobs aren't recreated for restored
##     blueprints here. Reconciliation belongs to the map-load save wiring.
##   - The roster isn't cleared on New Game (no reset hook yet), and colonist
##     save/restore via SaveSystem._parked is deferred. The first-session New Game
##     path — the manual-verification path — is correct.

## The colony's job registry + lifecycle. A child Node so it shows in the Remote
## tree and can own _process later if needed.
var job_board: JobBoard

## Live index of storage crates, so hauling jobs can find a source for a
## blueprint's still-needed materials. A child Node; wired to the current map's
## FurnitureContainer by MapWiring on each map load.
var storage_registry: StorageRegistry

const MVP_CAP := 5  # Roster capacity (ARCH "max 5 in MVP").

# JobDefs: every placed blueprint becomes a Job from one of these. A blueprint
# with an unsatisfied material_cost → HAULING_DEF (the job loops FETCH/DELIVER
# until satisfied and persists through source droughts — zero-stock blueprints
# simply wait for stock); costless / pre-satisfied → CONSTRUCTION_DEF directly.
# A crafting order's materials crossing → CRAFTING_DEF (the station plays the
# blueprint's role: hauling feeds it, crafting consumes it).
const CONSTRUCTION_DEF := preload("res://data/jobs/construction.tres")
const HAULING_DEF := preload("res://data/jobs/hauling.tres")
const CRAFTING_DEF := preload("res://data/jobs/crafting.tres")
const HARVEST_DEF := preload("res://data/jobs/harvest.tres")
const SOW_DEF := preload("res://data/jobs/sow.tres")
const WATER_DEF := preload("res://data/jobs/water.tres")
const TEND_DEF := preload("res://data/jobs/tend.tres")
const DIG_DEF := preload("res://data/jobs/dig.tres")

## Active colonists. Node instances live in the current map's ColonistContainer;
## this Array is the cross-scene authority (colonist nodes persist base↔POI via
## reparent, like the Player).
var colonists: Array[Colonist] = []

## The ColonistContainer of the currently wired map (null until on_map_wired).
var _container: Node3D = null

## Cached walkability predicate from the active map (used for runtime-spawned colonists).
var _walkability_predicate: Callable = Callable()

## Cached column stand-cell hint from the active map (smooth heightfield; see
## VoxelPathfinder.set_stand_cell_hint). Invalid on smooth-less maps.
var _stand_cell_hint: Callable = Callable()

## Cached combined ground query from the active map, `(x, z) -> float` (NAN
## when no terrain reaches the column). Marker spawns snap onto the highest
## surface (hill or plate) instead of trusting authored Y.
var _ground_query: Callable = Callable()

## Cached terrain presence predicate from the active map (VoxelGridAdapter.is_terrain_at).
var _is_terrain_at: Callable = Callable()


func _ready() -> void:
	job_board = JobBoard.new()
	job_board.name = "JobBoard"
	add_child(job_board)
	storage_registry = StorageRegistry.new()
	storage_registry.name = "StorageRegistry"
	add_child(storage_registry)
	EventBus.blueprint_placed.connect(_on_blueprint_placed)
	EventBus.blueprint_removed.connect(_on_blueprint_removed)
	EventBus.blueprint_materials_ready.connect(_on_blueprint_materials_ready)
	EventBus.crafting_order_queued.connect(_on_crafting_order_queued)
	EventBus.crafting_materials_ready.connect(_on_crafting_materials_ready)
	EventBus.harvest_mark_toggled.connect(_on_harvest_mark_toggled)
	EventBus.plot_needs_sowing.connect(_on_plot_needs_sowing)
	EventBus.plot_needs_water.connect(_on_plot_needs_water)
	EventBus.plot_needs_tending.connect(_on_plot_needs_tending)
	EventBus.furniture_removed.connect(_on_furniture_removed)
	EventBus.dig_box_designated.connect(_on_dig_box_designated)


## MapWiring.wire_colonists → here, on every map load. Empty roster + authored
## ColonistSpawn positions → fresh New-Game spawn (one colonist per marker, up to
## MVP_CAP). Non-empty → reparent the existing nodes into the new map so colonists
## survive base↔POI swaps (the same reparent idiom SceneManager uses for the Player).
func on_map_wired(container: Node3D, spawn_positions: Array) -> void:
	_container = container
	if colonists.is_empty():
		for pos in spawn_positions:
			spawn_colonist(null, pos)
	else:
		for c in colonists:
			if is_instance_valid(c) and c.get_parent() != container:
				if c.get_parent() != null:
					c.get_parent().remove_child(c)
				container.add_child(c)


## Store the active map's walkability predicate and inject it into all current colonists.
func set_walkability_predicate(predicate: Callable) -> void:
	_walkability_predicate = predicate
	for c in colonists:
		if is_instance_valid(c) and c.pathfinder != null:
			c.pathfinder.set_walkability(predicate)


## Store the active map's stand-cell hint and inject it into all current colonists.
func set_stand_cell_hint(hint: Callable) -> void:
	_stand_cell_hint = hint
	for c in colonists:
		if is_instance_valid(c) and c.pathfinder != null:
			c.pathfinder.set_stand_cell_hint(hint)


## Store the active map's combined ground query (Map.ground_height_at).
func set_ground_query(query: Callable) -> void:
	_ground_query = query


## Store the active map's terrain presence predicate (VoxelGridAdapter.is_terrain_at).
func set_terrain_predicate(predicate: Callable) -> void:
	_is_terrain_at = predicate


## True if cell contains natural terrain according to the active map's terrain predicate (defaults to true if unbound).
func is_terrain_at(cell: Vector3i) -> bool:
	if _is_terrain_at.is_valid():
		return _is_terrain_at.call(cell)
	return true


## Offsets for candidate standing cells from which a colonist can work on / dig a voxel.
## Includes horizontal neighbours, directly above, and step-up/step-down (+/-1 Y) positions.
const _WORK_STAND_OFFSETS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(0, 1, 0),
	Vector3i(1, 1, 0), Vector3i(-1, 1, 0), Vector3i(0, 1, 1), Vector3i(0, 1, -1),
	Vector3i(1, -1, 0), Vector3i(-1, -1, 0), Vector3i(0, -1, 1), Vector3i(0, -1, -1),
]


## True if cell is walkable according to the active map's walkability predicate.
func is_walkable(cell: Vector3i) -> bool:
	if _walkability_predicate.is_valid():
		return _walkability_predicate.call(cell)
	return true


## True if at least one candidate stand position adjacent to `cell` is walkable.
## Used to gate dig/work jobs so buried underground voxels cannot be claimed before
## they are exposed.
func has_walkable_neighbor(cell: Vector3i) -> bool:
	if not _walkability_predicate.is_valid():
		return true
	for off in _WORK_STAND_OFFSETS:
		if _walkability_predicate.call(cell + off):
			return true
	if _stand_cell_hint.is_valid():
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var col_cell: Vector3i = _stand_cell_hint.call(float(cell.x + dx), float(cell.z + dz))
				if col_cell != Vector3i.MAX and absi(col_cell.y - cell.y) <= 2:
					if _walkability_predicate.call(col_cell):
						return true
	return false


## Instantiate, position, register, and wire a new colonist.
## Returns the new Colonist instance, or null if the roster is full or no map is wired.
func spawn_colonist(colonist_def: ColonistDef = null, pos: Vector3 = Vector3.ZERO) -> Colonist:
	if colonists.size() >= MVP_CAP:
		push_warning("Colony: roster full (MVP cap %d)" % MVP_CAP)
		return null
	if _container == null:
		push_warning("Colony: no active map container to spawn colonist into")
		return null

	var c: Colonist = preload("res://subsystems/colonists/colonist.tscn").instantiate()
	if colonist_def != null:
		c.colonist_def = colonist_def

	# Add to tree BEFORE setting global_position — it only resolves in-tree.
	_container.add_child(c)
	# Marker/def Y is a hint, not truth: where hills overlap the blocky plate,
	# the highest surface can sit metres above (or below) the authored Y. Snap
	# XZ-preserving onto the combined ground query's surface + epsilon.
	if _ground_query.is_valid():
		var ground_y: float = _ground_query.call(pos.x, pos.z)
		if not is_nan(ground_y):
			pos.y = ground_y + 1.0
		else:
			pos.y += 1.0
	else:
		pos.y += 1.0
	c.global_position = pos
	if _walkability_predicate.is_valid() and c.pathfinder != null:
		c.pathfinder.set_walkability(_walkability_predicate)
	if _stand_cell_hint.is_valid() and c.pathfinder != null:
		c.pathfinder.set_stand_cell_hint(_stand_cell_hint)

	colonists.append(c)
	return c


## Recruit a colonist (random world event / radio, post-MVP). Respects the cap.
func add_colonist(c: Colonist) -> void:
	if colonists.size() >= MVP_CAP:
		push_warning("Colony: roster full (MVP cap %d)" % MVP_CAP)
		return
	colonists.append(c)
	if _container != null and c.get_parent() == null:
		_container.add_child(c)
		if _walkability_predicate.is_valid() and c.pathfinder != null:
			c.pathfinder.set_walkability(_walkability_predicate)
		if _stand_cell_hint.is_valid() and c.pathfinder != null:
			c.pathfinder.set_stand_cell_hint(_stand_cell_hint)


## Drop a colonist by id (death or departure). Frees the node.
func remove_colonist(colonist_id: String) -> void:
	for i in range(colonists.size()):
		if colonists[i].colonist_id == colonist_id:
			var c: Colonist = colonists[i]
			colonists.remove_at(i)
			if is_instance_valid(c) and c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
			return


# --- Job production plumbing ---------------------------------------------------
# Every producer path is the same shape: dedupe by anchor + def, build from the
# def, bind the placement, register. Def identity works as the dedupe key
# because the DEF consts above are preloaded singletons — and it's the only
# workable key for the farming defs, which all share labor_id "farming".


## Build + register a Job at `anchor` bound to `target`, unless one from the
## same def already exists there.
func _spawn_job(def: JobDef, title: String, anchor: Vector3i, location: Vector3, target: Node) -> void:
	for j in job_board.get_jobs():
		if j.anchor_cell == anchor and j.def == def:
			return
	var job := Job.from_def(def)
	job.title = title
	job.anchor_cell = anchor
	job.location = location
	job.target_node = target
	job_board.add_job(job)


## Drop jobs at `anchor` — every def's when `def` is null, else only that def's.
func _remove_jobs_at(anchor: Vector3i, def: JobDef = null) -> void:
	for job in job_board.get_jobs():
		if job.anchor_cell == anchor and (def == null or job.def == def):
			job_board.remove_job(job.id)


## BlueprintLayer -> EventBus -> here. Decide haul-vs-construct:
##   - blueprint has an unsatisfied material_cost (needed_item_ids non-empty) →
##     spawn a HAUL job, regardless of current stock: haulers loop FETCH/DELIVER
##     until the blueprint's deposit_from crosses has_complete_materials, which
##     emits blueprint_materials_ready → _spawn_construction_job. While no crate
##     stocks a needed material the job waits on the board (unclaimable but not
##     dead — HaulingJobDef.should_close), so a later restock resumes hauling
##     without any new producer event.
##   - otherwise (costless or already satisfied) → spawn a construction job
##     directly.
func _on_blueprint_placed(target_def_id: String, anchor: Vector3i, blueprint: Node) -> void:
	var bp := blueprint as Blueprint
	if bp != null:
		var needed := bp.needed_item_ids()
		# Any unsatisfied material_cost → haul (the job drought-waits on the
		# board until storage can satisfy it). Else build now (costless /
		# pre-satisfied).
		if not needed.is_empty():
			_spawn_job(HAULING_DEF, "Haul materials for %s" % target_def_id, anchor,
					_world_location_for(target_def_id, anchor), blueprint)
			return
	_spawn_construction_job(target_def_id, anchor, blueprint)


## Blueprint.deposit_from -> EventBus.blueprint_materials_ready -> here. Fires
## exactly once when a blueprint's materials cross has_complete_materials (player
## AddMaterials or a hauler's DELIVER leg — both go through deposit_from). Spawns
## the construction job that the haul run was feeding. Guarded against a
## duplicate (defensive — the signal is single-fire per blueprint, and the
## producer no longer spawns construction for material'd blueprints).
func _on_blueprint_materials_ready(target_def_id: String, anchor: Vector3i, blueprint: Node) -> void:
	_spawn_construction_job(target_def_id, anchor, blueprint)


## Build + register a construction Job at `anchor` bound to `blueprint`, unless
## one already exists there (the no-source producer path + a later deposit can
## both target the same blueprint). The job's location is a best-effort
## footprint-center approach point; ColonistAI refines it into a real adjacent
## standing cell at navigation time.
func _spawn_construction_job(target_def_id: String, anchor: Vector3i, blueprint: Node) -> void:
	_spawn_job(CONSTRUCTION_DEF, "Build %s" % target_def_id, anchor,
			_world_location_for(target_def_id, anchor), blueprint)


## BlueprintLayer -> EventBus -> here. Fires on BOTH cancel and completion
## (complete_blueprint frees the blueprint too). Drop any job targeting that
## anchor so a colonist is never sent to a blueprint that no longer exists.
## Erasing an already-removed id (colonist completed it first) is a harmless no-op.
func _on_blueprint_removed(_target_def_id: String, anchor: Vector3i) -> void:
	_remove_jobs_at(anchor)


# --- Crafting (GDD §7.9) -------------------------------------------------------
# The station plays the blueprint's role in the same produce chain:
# queue → haul (below) → materials-ready → craft. Stations aren't freed on
# completion, so their jobs close through "order gone"/"sink satisfied" rather
# than blueprint removal — no furniture_removed listener needed; a freed
# station is caught by ColonistAI's freed-target guard + should_close.


## CraftingStation.queue_recipe -> EventBus.crafting_order_queued -> here.
## Spawn a haul job bound to the station (the existing def — hauling is
## sink-generic) so haulers FETCH the order's inputs from crates and DELIVER
## them via the station's deposit_from. Spawned regardless of current stock:
## through a drought the job waits on the board (HaulingJobDef.should_close)
## and restock resumes it with no new producer event. Deduped by anchor +
## def so a re-queue can't double the haul run.
func _on_crafting_order_queued(station: Node, anchor: Vector3i) -> void:
	if not MaterialSink.is_material_sink(station):
		return
	if station.has_complete_materials():
		return
	_spawn_job(HAULING_DEF, "Haul materials for crafting", anchor, _station_location(station), station)


## CraftingStation.deposit_from -> EventBus.crafting_materials_ready -> here.
## Fires exactly once per order (the crossing that completes its inputs).
## Spawns the craft job the haul run was feeding, deduped like construction.
func _on_crafting_materials_ready(station: Node, anchor: Vector3i) -> void:
	_spawn_craft_job(station, anchor)


## Build + register a crafting Job at `anchor` bound to `station`, unless one
## already exists there. Single-assignee (crafting.tres default).
func _spawn_craft_job(station: Node, anchor: Vector3i) -> void:
	var recipe: RecipeDef = station.active_recipe()
	var title := "Craft %s" % recipe.label() if recipe != null else "Craft order"
	_spawn_job(CRAFTING_DEF, title, anchor, _station_location(station), station)


## Walk target for station-bound jobs: the furniture's position, which
## FurnitureLayer sets to the footprint center (world_origin). ColonistAI
## refines it into an adjacent standing cell at navigation time.
func _station_location(station: Node) -> Vector3:
	var furniture := station.get_parent() as Node3D
	if furniture == null:
		return Vector3.ZERO
	return furniture.global_position


## Footprint-center world position for a job's walk target. Reuses FurnitureLayer's
## static geometry helpers so footprint math has one home. Returns the anchor
## corner as a safe fallback for unknown defs.
func _world_location_for(target_def_id: String, anchor: Vector3i) -> Vector3:
	var def := BuildLibrary.get_def(target_def_id)
	if def == null:
		return Vector3(anchor)
	var dims := FurnitureLayer.dimensions_of(def)
	return FurnitureLayer.world_origin(anchor, dims, 0)


# --- Harvesting (GDD §6.10, ARCH "Harvesting") --------------------------------

func _on_harvest_mark_toggled(furniture: Node, anchor: Vector3i, is_marked: bool) -> void:
	if is_marked:
		_spawn_harvest_job(furniture, anchor)
	else:
		_remove_jobs_at(anchor, HARVEST_DEF)


func _on_furniture_removed(_def_id: String, anchor: Vector3i) -> void:
	_remove_jobs_at(anchor, HARVEST_DEF)
	_remove_jobs_at(anchor, SOW_DEF)
	_remove_jobs_at(anchor, WATER_DEF)
	_remove_jobs_at(anchor, TEND_DEF)


# --- Farming (GDD §6 / Farming, ARCH "Farming") -----------------------------

func _on_plot_needs_sowing(growable: Node, anchor: Vector3i, crop_id: String, needed: bool) -> void:
	if needed:
		_spawn_sow_job(growable, anchor, crop_id)
	else:
		_remove_jobs_at(anchor, SOW_DEF)


func _on_plot_needs_water(growable: Node, anchor: Vector3i, needed: bool) -> void:
	if needed:
		_spawn_water_job(growable, anchor)
	else:
		_remove_jobs_at(anchor, WATER_DEF)


func _on_plot_needs_tending(growable: Node, anchor: Vector3i, needed: bool) -> void:
	if needed:
		_spawn_tend_job(growable, anchor)
	else:
		_remove_jobs_at(anchor, TEND_DEF)


func _spawn_sow_job(growable: Node, anchor: Vector3i, crop_id: String) -> void:
	var crop_def := CropLibrary.get_crop(crop_id)
	var title := "Sow %s" % (crop_def.display_name if crop_def != null else "crop")
	_spawn_job(SOW_DEF, title, anchor, _target_node_location(growable, anchor), _target_node_of(growable))


func _spawn_water_job(growable: Node, anchor: Vector3i) -> void:
	_spawn_job(WATER_DEF, "Water crop", anchor,
			_target_node_location(growable, anchor), _target_node_of(growable))


func _spawn_tend_job(growable: Node, anchor: Vector3i) -> void:
	_spawn_job(TEND_DEF, "Tend crop", anchor,
			_target_node_location(growable, anchor), _target_node_of(growable))


func _target_node_of(node: Node) -> Node:
	if node == null:
		return null
	if node is Furniture:
		return node
	var parent := node.get_parent()
	if parent != null:
		return parent
	return node


func _target_node_location(node: Node, anchor: Vector3i) -> Vector3:
	var target := _target_node_of(node)
	if target is Node3D:
		return (target as Node3D).global_position
	return Vector3(anchor)


func _spawn_harvest_job(furniture: Node, anchor: Vector3i) -> void:
	var f := furniture as Furniture
	var title := "Harvest %s" % (f.label if f != null else "resource")
	var location := f.global_position if f != null else Vector3(anchor)
	_spawn_job(HARVEST_DEF, title, anchor, location, furniture)


# --- Mining (GDD §6.10, ARCH "Mining") ----------------------------------------

func _on_dig_box_designated(cells: Array) -> void:
	for cell_val in cells:
		if cell_val is Vector3i:
			_spawn_dig_job(cell_val)


func _spawn_dig_job(anchor: Vector3i) -> void:
	var location := Vector3(anchor) + Vector3(0.5, 0.5, 0.5)
	_spawn_job(DIG_DEF, "Dig terrain", anchor, location, null)
