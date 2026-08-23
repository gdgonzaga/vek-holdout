extends JobDef
class_name ConstructionJobDef
## Construction labor (GDD §6.10): build a placed blueprint over its
## BuildableDef.build_time, then materialize it via Blueprint.complete. Expressed
## as a single-leg job: get_next_leg returns the blueprint leg once (the colonist
## walks to a stand-adjacent cell), begin reports build_time, complete
## materializes it. Mirrors the player's BuildAction (data/actions/build_action.gd)
## but headless — no ActionProgress gauge, no mouse unlock, no set_busy:
## ColonistAI's WORK state is itself the busy guard.
##
## Single-colonist (max_assignees=1, the JobDef default). Unlike hauling, one
## builder finishing IS the job done — should_close() true once the bp is freed.
##
## Sprint scope: builds once materials are satisfied — the hauling dependency is
## handled upstream (Colony only spawns a construction job once the blueprint's
## deposit_from crosses has_complete_materials, via the blueprint_materials_ready
## signal). The work tick runs at 1× (skill × stamina multiplier deferred —
## begin's returned duration is the seam for build_time × multiplier later).


## Single WORK leg targeting the blueprint, available while the blueprint
## exists and is not occupied. complete() frees it, so the post-complete get_next_leg
## call returns null — the clean end-signal for this colonist.
func get_next_leg(_actor: Node, job: Job) -> JobLeg:
	if not is_instance_valid(job.target_node):
		return null
	var bp := job.target_node as Blueprint
	if bp == null or _is_blueprint_occupied(bp):
		return null
	# `location` is the footprint-center approach set by Colony at spawn; the AI
	# refines it into an adjacent standing cell. target_node is the blueprint.
	var leg := JobLeg.new()
	leg.location = job.location
	leg.target_node = job.target_node
	return leg


## build_time read from the target's BuildableDef, divided by the builder's
## skill multiplier for this def's labor (SkillSet.get_multiplier; 1.0 for an
## unskilled actor — the effective-rate seam from GDD §6, stamina factor still
## deferred). 0.0 (instant) if the target is not a Blueprint or its def is
## unknown. Matches BuildAction's duration resolution so player and colonist
## builds take the same time for a given def at L1.
func begin(actor: Node, leg: JobLeg, _job: Job) -> float:
	if not is_instance_valid(leg.target_node):
		return 0.0
	var bp := leg.target_node as Blueprint
	if bp == null:
		return 0.0
	var def := BuildLibrary.get_def(bp.target_def_id)
	if def == null:
		return 0.0
	var colonist := actor as Colonist
	if colonist == null or colonist.skill_set == null:
		return def.build_time
	return def.build_time / colonist.skill_set.get_multiplier(labor_id)


## Pauses work progress if any colonist other than the builder is occupying the blueprint.
func can_progress_work(actor: Node, leg: JobLeg, _job: Job) -> bool:
	if not is_instance_valid(leg.target_node):
		return false
	var bp := leg.target_node as Blueprint
	if bp == null:
		return false
	return not _is_blueprint_occupied(bp, actor)


## Materialize the blueprint. Resets work_done on success so a later rebuild of
## the same target starts fresh (matches player BuildAction), and forwards the
## colonist as the builder so skill/stamina can be attributed later. Guarded so
## it will not materialize if another colonist is standing on it.
func complete(actor: Node, leg: JobLeg, _job: Job) -> void:
	if not is_instance_valid(leg.target_node):
		return
	var bp := leg.target_node as Blueprint
	if bp != null and not _is_blueprint_occupied(bp, actor):
		bp.work_done = 0.0
		bp.complete(actor)


## On an abort (blueprint cancelled/freed mid-build), persist the partial WORK
## time so a later attempt — colonist or player — resumes from here instead of
## restarting. No-op on a clean finish (complete already reset work_done), when
## the blueprint is already gone (nothing to persist), or when the colonist was
## released before receiving a leg (claim-path miss — leg is null, no progress
## to persist).
func on_end(success: bool, _actor: Node, leg: JobLeg, _job: Job, elapsed: float) -> void:
	if success or leg == null or not is_instance_valid(leg.target_node):
		return
	var bp := leg.target_node as Blueprint
	if bp != null:
		bp.work_done = elapsed


## A construction job is available while its blueprint still exists and is not
## occupied by a colonist. The Job's own slot gate (max_assignees=1) keeps it
## to one builder.
func is_available(job: Job) -> bool:
	if not is_instance_valid(job.target_node):
		return false
	var bp := job.target_node as Blueprint
	if bp == null:
		return false
	return not _is_blueprint_occupied(bp)


## The job leaves the board ONLY when the blueprint is actually freed (built or cancelled).
## An occupied blueprint keeps the job registered so it can resume once clear.
func should_close(job: Job) -> bool:
	return not is_instance_valid(job.target_node)


## The job is complete only when the blueprint has been materialized and freed.
func job_complete(job: Job) -> bool:
	return not is_instance_valid(job.target_node)


## Returns true if any active colonist or player (excluding exclude_actor) is currently standing
## inside any cell of the blueprint's 3D volume (accounting for the 2-cell character height).
func _is_blueprint_occupied(bp: Blueprint, exclude_actor: Node = null) -> bool:
	if not is_instance_valid(bp):
		return false
	if bp.def == null and bp.target_def_id != "":
		bp.def = BuildLibrary.get_def(bp.target_def_id)
	var footprint := bp.get_footprint_cells()
	if footprint.is_empty():
		return false
	var bp_cells := _get_blueprint_cells(bp, footprint)
	for colonist in Colony.colonists:
		if not is_instance_valid(colonist) or colonist.is_queued_for_deletion():
			continue
		if colonist == exclude_actor:
			continue
		if _character_overlaps_cells(colonist.global_position, bp_cells):
			return true
	var player := SceneManager.get_player()
	if is_instance_valid(player) and not player.is_queued_for_deletion() and player != exclude_actor:
		if _character_overlaps_cells(player.global_position, bp_cells):
			return true
	return false


func _get_blueprint_cells(bp: Blueprint, footprint: Array[Vector3i]) -> Array[Vector3i]:
	var fdef := bp.def as FurnitureDef
	var h := fdef.dimensions.y if fdef != null else 1
	if h <= 1:
		return footprint
	var cells: Array[Vector3i] = []
	for cell in footprint:
		for dy in range(h):
			cells.append(cell + Vector3i(0, dy, 0))
	return cells


func _character_overlaps_cells(pos: Vector3, cells: Array[Vector3i]) -> bool:
	var cx := int(floor(pos.x))
	var cy := int(floor(pos.y))
	var cz := int(floor(pos.z))
	var lower := Vector3i(cx, cy, cz)
	var upper := Vector3i(cx, cy + 1, cz)
	return cells.has(lower) or cells.has(upper)
