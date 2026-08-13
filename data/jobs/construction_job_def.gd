extends JobDef
class_name ConstructionJobDef
## Construction labor (GDD §6.10): build a placed blueprint over its
## BuildableDef.build_time, then materialize it via Blueprint.complete. The
## colonist walks to a stand-adjacent cell (ColonistAI MOVE/PATH), then WORK
## ticks this def's begin/complete. Mirrors the player's BuildAction
## (data/actions/build_action.gd) but headless — no ActionProgress gauge, no
## mouse unlock, no set_busy: ColonistAI's WORK state is itself the busy guard.
##
## Sprint scope: builds unconditionally — there is no has_complete_materials()
## gate here, so a colonist can finish a costly blueprint without the materials
## having been deposited. Costless test blueprints don't expose this; the
## NoMaterials failure path + hauling dependency is deferred (GDD §6.10 late-MVP).
## The work tick runs at 1× (skill × stamina multiplier deferred — begin's
## returned duration is the seam for build_time × multiplier later).


## build_time read from the target's BuildableDef; 0.0 (instant) if the target
## is not a Blueprint or its def is unknown. Matches BuildAction's duration
## resolution so player and colonist builds take the same time for a given def.
func begin(_actor: Node, target: Node) -> float:
	var bp := target as Blueprint
	if bp == null:
		return 0.0
	var def := BuildLibrary.get_def(bp.target_def_id)
	return def.build_time if def != null else 0.0


## Materialize the blueprint. Resets work_done on success so a later rebuild of
## the same target starts fresh (matches player BuildAction), and forwards the
## colonist as the builder so skill/stamina can be attributed later.
func complete(actor: Node, target: Node) -> void:
	var bp := target as Blueprint
	if is_instance_valid(bp):
		bp.work_done = 0.0
		bp.complete(actor)
