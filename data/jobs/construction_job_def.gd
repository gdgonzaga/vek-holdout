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


## Pauses work progress if any colonist or player other than the builder is occupying the blueprint.
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
## it will not materialize if another colonist or player is standing on it.
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
## occupied by a colonist or player. The Job's own slot gate (max_assignees=1) keeps it
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


const _CHARACTER_RADIUS: float = 0.35
const _CHARACTER_HEIGHT: float = 1.6

## Returns true if any active colonist or player (excluding exclude_actor) is currently standing
## inside any cell of the blueprint's 3D volume (accounting for the character's 3D bounding box).
func _is_blueprint_occupied(bp: Blueprint, exclude_actor: Node = null) -> bool:
	if not is_instance_valid(bp):
		return false
	var bp_cells := _get_blueprint_cells(bp)
	if bp_cells.is_empty():
		return false

	var candidates: Array[Node3D] = []
	for colonist in Colony.colonists:
		if is_instance_valid(colonist) and not colonist.is_queued_for_deletion():
			candidates.append(colonist)

	if bp.get_tree() != null:
		for node in bp.get_tree().get_nodes_in_group("colonists"):
			var c := node as Node3D
			if is_instance_valid(c) and not c.is_queued_for_deletion() and not candidates.has(c):
				candidates.append(c)

	var player := SceneManager.get_player()
	if is_instance_valid(player) and not player.is_queued_for_deletion():
		if not candidates.has(player):
			candidates.append(player)

	if bp.get_tree() != null:
		var tree_player := bp.get_tree().get_first_node_in_group("player") as Node3D
		if tree_player == null and bp.get_tree().root != null:
			tree_player = bp.get_tree().root.find_child("Player", true, false) as Node3D
		if is_instance_valid(tree_player) and not tree_player.is_queued_for_deletion() and not candidates.has(tree_player):
			candidates.append(tree_player)

	for actor in candidates:
		if actor == exclude_actor:
			continue
		if _character_overlaps_cells(actor.global_position, bp_cells):
			return true

	return false


func _get_blueprint_cells(bp: Blueprint) -> Array[Vector3i]:
	if not is_instance_valid(bp):
		return []
	if bp.def == null and bp.target_def_id != "":
		bp.def = BuildLibrary.get_def(bp.target_def_id)
	if bp.def != null and not bp.def is FurnitureDef:
		var out: Array[Vector3i] = [bp.anchor_cell]
		return out

	var footprint := bp.get_footprint_cells()
	if footprint.is_empty():
		var out: Array[Vector3i] = []
		if bp.anchor_cell != Vector3i.MAX:
			out.append(bp.anchor_cell)
		return out
	var fdef := bp.def as FurnitureDef
	var h := fdef.dimensions.y if fdef != null else 1
	if h <= 1:
		var out: Array[Vector3i] = []
		out.assign(footprint)
		return out
	var cells: Array[Vector3i] = []
	for cell in footprint:
		for dy in range(h):
			cells.append(cell + Vector3i(0, dy, 0))
	return cells


func _character_overlaps_cells(pos: Vector3, bp_cells: Array[Vector3i]) -> bool:
	var min_x := int(floor(pos.x - _CHARACTER_RADIUS))
	var max_x := int(floor(pos.x + _CHARACTER_RADIUS))
	var min_y := int(floor(pos.y))
	var max_y := int(floor(pos.y + _CHARACTER_HEIGHT))
	var min_z := int(floor(pos.z - _CHARACTER_RADIUS))
	var max_z := int(floor(pos.z + _CHARACTER_RADIUS))

	for x in range(min_x, max_x + 1):
		for y in range(min_y, max_y + 1):
			for z in range(min_z, max_z + 1):
				if bp_cells.has(Vector3i(x, y, z)):
					return true
	return false
