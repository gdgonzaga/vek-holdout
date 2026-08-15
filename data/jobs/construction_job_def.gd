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


## Single WORK leg targeting the blueprint, available exactly while the blueprint
## exists. complete() frees it, so the post-complete get_next_leg call returns
## null — the clean end-signal for this colonist (the one leg's begin/complete did
## all the work, and a null next leg ends the job). Without the guard we'd hand
## back a leg to a freed bp and only abort next tick via ColonistAI's freed-target
## guard: a spurious re-path, and the job would end on the abort path instead of
## the success path. (Matches is_available, which gates on the same validity.)
func get_next_leg(_actor: Node, job: Job) -> JobLeg:
	if not is_instance_valid(job.target_node):
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
	if leg.target_node == null:
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


## Materialize the blueprint. Resets work_done on success so a later rebuild of
## the same target starts fresh (matches player BuildAction), and forwards the
## colonist as the builder so skill/stamina can be attributed later.
func complete(actor: Node, leg: JobLeg, _job: Job) -> void:
	if leg.target_node == null:
		return
	var bp := leg.target_node as Blueprint
	if is_instance_valid(bp):
		bp.work_done = 0.0
		bp.complete(actor)


## On an abort (blueprint cancelled/freed mid-build), persist the partial WORK
## time so a later attempt — colonist or player — resumes from here instead of
## restarting. No-op on a clean finish (complete already reset work_done) or when
## the blueprint is already gone (nothing to persist).
func on_end(success: bool, _actor: Node, leg: JobLeg, _job: Job, elapsed: float) -> void:
	if success:
		return
	var bp := leg.target_node as Blueprint
	if is_instance_valid(bp):
		bp.work_done = elapsed


## A construction job is available while its blueprint still exists. The Job's
## own slot gate (max_assignees=1) keeps it to one builder; once the bp is freed
## (built or cancelled) this flips false so should_close() can remove it.
func is_available(job: Job) -> bool:
	return is_instance_valid(job.target_node)
