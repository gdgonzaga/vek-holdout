extends JobDef
class_name ConstructionJobDef
## Construction labor (GDD §6.10, ARCH "Build"): build a placed blueprint over
## its BuildableDef.build_time, then materialize it via Blueprint.complete —
## the colonist-side twin of the player's BuildAction
## (data/actions/build_action.gd). The job only exists once the blueprint's
## materials are satisfied (Colony spawns it on blueprint_materials_ready), so
## complete() may materialize unconditionally. Single-colonist.
##
## An occupied blueprint (another colonist or the player standing in its
## volume) hides the job (is_available false) and blocks complete() — the job
## waits on the board until the volume clears instead of entombing someone.

## Cycle duration: the target's authored build_time (dig.tres-style skill
## scaling is applied by PerformWork). 0.0 when the target is not a Blueprint
## or its def is unknown — falls back to the authored work_duration.
func begin(_actor: Node, job: Variant) -> float:
	var bp := _blueprint_of(job)
	if bp == null:
		return 0.0
	var def := BuildLibrary.get_def(bp.target_def_id)
	if def == null:
		return 0.0
	return def.build_time


## Materialize the blueprint. Resets work_done on success so a later rebuild
## of the same target starts fresh (matches player BuildAction). Guarded so it
## will not materialize while someone stands in the volume — the job stays on
## the board and a later claim retries.
func complete(actor: Node, job: Variant) -> void:
	var bp := _blueprint_of(job)
	if bp == null:
		_finish(actor, job)
		return
	if _is_blueprint_occupied(bp, actor):
		return
	bp.work_done = 0.0
	bp.complete(actor)
	_finish(actor, job)


## A construction job is claimable while its blueprint exists and its volume
## is clear. The slot gate (max_assignees=1) keeps it to one builder.
func is_available(job: Variant) -> bool:
	var bp := _blueprint_of(job)
	if bp == null:
		return false
	return not _is_blueprint_occupied(bp)


## Leaves the board only when the blueprint is actually freed (built or
## cancelled). An occupied blueprint keeps the job registered to resume once
## clear; blueprint_removed also drops it via Colony's listener.
func should_close(job: Variant) -> bool:
	var t: Variant = job.target_node if "target_node" in job else null
	return t == null or not is_instance_valid(t)


## Preempted mid-build: persist the partial work so a later attempt — colonist
## or player — resumes from here instead of restarting (the ActionProgress
## resume seam). No-op on a clean finish (complete already reset work_done) or
## when the blueprint is already gone.
func on_abort(_actor: Node, job: Variant, elapsed: float) -> void:
	var bp := _blueprint_of(job)
	if bp != null:
		bp.work_done = elapsed


func _blueprint_of(job: Variant) -> Blueprint:
	if job == null or not "target_node" in job:
		return null
	var t: Variant = job.target_node
	if t == null or not is_instance_valid(t):
		return null
	return t as Blueprint


const _CHARACTER_RADIUS: float = 0.35
const _CHARACTER_HEIGHT: float = 1.6

## True if any active colonist or player (excluding `exclude_actor`) stands
## inside any cell of the blueprint's 3D volume (character box vs cells).
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
	if is_instance_valid(player) and not player.is_queued_for_deletion() and not candidates.has(player):
		candidates.append(player)

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
		return [bp.anchor_cell]

	var footprint := bp.get_footprint_cells()
	if footprint.is_empty():
		var out: Array[Vector3i] = []
		if bp.anchor_cell != Vector3i.MAX:
			out.append(bp.anchor_cell)
		return out
	var fdef := bp.def as FurnitureDef
	var h := fdef.dimensions.y if fdef != null else 1
	if h <= 1:
		var flat: Array[Vector3i] = []
		flat.assign(footprint)
		return flat
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
