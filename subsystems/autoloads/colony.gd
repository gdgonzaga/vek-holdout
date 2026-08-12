extends Node
## Colony autoload (ARCH "Subsystem: Colonists"). Cross-scene singleton —
## colonists persist base↔POI.
##
## Phase 1 scope: owns the Job Board and produces construction jobs from blueprint
## placement (EventBus.blueprint_placed/removed → Job). The colonist roster
## (add/remove_colonist, MVP cap 5) is added with colonist spawning (Phase 2).
##
## Known gap (deferred to map-wiring / Phase 2): a save-load restore suppresses
## per-blueprint blueprint_placed emits (BlueprintLayer._is_restoring), so jobs
## are not recreated for restored blueprints here. Reconciliation belongs to the
## map-load wiring that doesn't exist yet; the live place/remove path is correct.

## The colony's job registry + lifecycle. A child Node so it shows in the Remote
## tree and can own _process later if needed.
var job_board: JobBoard


func _ready() -> void:
	job_board = JobBoard.new()
	job_board.name = "JobBoard"
	add_child(job_board)
	EventBus.blueprint_placed.connect(_on_blueprint_placed)
	EventBus.blueprint_removed.connect(_on_blueprint_removed)


## BlueprintLayer -> EventBus -> here. Create a construction job at the blueprint's
## anchor so a colonist can later walk to it. The job's location is a best-effort
## footprint-center approach point (no yaw in the signal); ColonistAI refines it
## into a real adjacent standing cell at navigation time.
func _on_blueprint_placed(target_def_id: String, anchor: Vector3i) -> void:
	var job := Job.new()
	job.id = Tools.generate_uuid()
	job.labor_id = "construction"
	job.title = "Build %s" % target_def_id
	job.anchor_cell = anchor
	job.location = _world_location_for(target_def_id, anchor)
	job_board.add_job(job)


## BlueprintLayer -> EventBus -> here. Fires on BOTH cancel and completion
## (complete_blueprint frees the blueprint too). Drop any job targeting that
## anchor so a colonist is never sent to a blueprint that no longer exists.
## Erasing an already-removed id (colonist completed it first) is a harmless no-op.
func _on_blueprint_removed(_target_def_id: String, anchor: Vector3i) -> void:
	for job in job_board.get_jobs():
		if job.anchor_cell == anchor:
			job_board.remove_job(job.id)


## Footprint-center world position for a job's walk target. Reuses FurnitureLayer's
## static geometry helpers so footprint math has one home. Returns the anchor
## corner as a safe fallback for unknown defs.
func _world_location_for(target_def_id: String, anchor: Vector3i) -> Vector3:
	var def := BuildLibrary.get_def(target_def_id)
	if def == null:
		return Vector3(anchor)
	var dims := FurnitureLayer.dimensions_of(def)
	return FurnitureLayer.world_origin(anchor, dims, 0)
