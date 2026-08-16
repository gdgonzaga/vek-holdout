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

## Active colonists. Node instances live in the current map's ColonistContainer;
## this Array is the cross-scene authority (colonist nodes persist base↔POI via
## reparent, like the Player).
var colonists: Array[Colonist] = []

## The ColonistContainer of the currently wired map (null until on_map_wired).
var _container: Node3D = null

## Cached walkability predicate from the active map (used for runtime-spawned colonists).
var _walkability_predicate: Callable = Callable()


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
	EventBus.furniture_removed.connect(_on_furniture_removed)


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
	c.global_position = pos
	if _walkability_predicate.is_valid() and c.pathfinder != null:
		c.pathfinder.set_walkability(_walkability_predicate)

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
			var job := Job.from_def(HAULING_DEF)
			job.title = "Haul materials for %s" % target_def_id
			job.anchor_cell = anchor
			job.location = _world_location_for(target_def_id, anchor)
			job.target_node = blueprint
			job_board.add_job(job)
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
	for j in job_board.get_jobs():
		if j.anchor_cell == anchor and j.labor_id == "construction":
			return
	var job := Job.from_def(CONSTRUCTION_DEF)
	job.title = "Build %s" % target_def_id
	job.anchor_cell = anchor
	job.location = _world_location_for(target_def_id, anchor)
	job.target_node = blueprint
	job_board.add_job(job)


## BlueprintLayer -> EventBus -> here. Fires on BOTH cancel and completion
## (complete_blueprint frees the blueprint too). Drop any job targeting that
## anchor so a colonist is never sent to a blueprint that no longer exists.
## Erasing an already-removed id (colonist completed it first) is a harmless no-op.
func _on_blueprint_removed(_target_def_id: String, anchor: Vector3i) -> void:
	for job in job_board.get_jobs():
		if job.anchor_cell == anchor:
			job_board.remove_job(job.id)


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
## labor so a re-queue can't double the haul run.
func _on_crafting_order_queued(station: Node, anchor: Vector3i) -> void:
	if not MaterialSink.is_material_sink(station):
		return
	if station.has_complete_materials():
		return
	for j in job_board.get_jobs():
		if j.anchor_cell == anchor and j.labor_id == "hauling":
			return
	var job := Job.from_def(HAULING_DEF)
	job.title = "Haul materials for crafting"
	job.anchor_cell = anchor
	job.location = _station_location(station)
	job.target_node = station
	job_board.add_job(job)


## CraftingStation.deposit_from -> EventBus.crafting_materials_ready -> here.
## Fires exactly once per order (the crossing that completes its inputs).
## Spawns the craft job the haul run was feeding, deduped like construction.
func _on_crafting_materials_ready(station: Node, anchor: Vector3i) -> void:
	_spawn_craft_job(station, anchor)


## Build + register a crafting Job at `anchor` bound to `station`, unless one
## already exists there. Single-assignee (crafting.tres default).
func _spawn_craft_job(station: Node, anchor: Vector3i) -> void:
	for j in job_board.get_jobs():
		if j.anchor_cell == anchor and j.labor_id == "crafting":
			return
	var job := Job.from_def(CRAFTING_DEF)
	var recipe: RecipeDef = station.active_recipe()
	job.title = "Craft %s" % recipe.label() if recipe != null else "Craft order"
	job.anchor_cell = anchor
	job.location = _station_location(station)
	job.target_node = station
	job_board.add_job(job)


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
		_remove_harvest_job(anchor)


func _on_furniture_removed(_def_id: String, anchor: Vector3i) -> void:
	_remove_harvest_job(anchor)


func _spawn_harvest_job(furniture: Node, anchor: Vector3i) -> void:
	for j in job_board.get_jobs():
		if j.anchor_cell == anchor and j.labor_id == "harvesting":
			return
	var job := Job.from_def(HARVEST_DEF)
	var f := furniture as Furniture
	job.title = "Harvest %s" % (f.label if f != null else "resource")
	job.anchor_cell = anchor
	job.location = f.global_position if f != null else Vector3(anchor)
	job.target_node = furniture
	job_board.add_job(job)


func _remove_harvest_job(anchor: Vector3i) -> void:
	for job in job_board.get_jobs():
		if job.anchor_cell == anchor and job.labor_id == "harvesting":
			job_board.remove_job(job.id)
