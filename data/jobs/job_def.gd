extends Resource
class_name JobDef
## Reusable template for one kind of colonist work (ARCH "Subsystem: Colonists",
## GDD §6.10). In the LimboAI + fractional job architecture, JobDef is the
## declarative data + behavior resource behind the universal work tree
## (ClaimJob -> HasTool -> NavigateTo -> PerformWork, see docs/architecture/ai.md):
## the data fields configure duration/animation/units, the virtuals below are
## the lifecycle the tree + JobBoard drive.
##
## Virtual contract (base implementations are sane defaults; override per def):
##   is_available(job)      claimability beyond the board's slot gate
##   should_close(job)      board lifetime: true = leave the registry
##   job_complete(job)      did a finished cycle actually satisfy the work
##   begin(actor, job)      cycle duration in UNSKILLED seconds (the tree divides
##                          by the actor's skill multiplier); only consulted
##                          when work_duration <= 0.0 — author dynamic-duration
##                          defs (recipe/plot/building-driven) with 0.0
##   complete(actor, job)   terminal effect of one PerformWork cycle (carve the
##                          voxel, materialize the blueprint, ...). The base
##                          default records skill XP and drops the job from the
##                          board — override WITHOUT calling _finish to loop
##                          (hauling), or call _finish after the effect
##   on_abort(actor, job, elapsed)  the cycle was preempted mid-work (needs
##                          preemption under BTDynamicSelector): persist partial
##                          progress, release claims
##   work_site(actor, job)  walk target for this cycle; null = the board default
##                          (anchor cell / target node). Multi-site labors
##                          (hauling crate-vs-sink) override per carry state
##
## Skill XP has a single entry point: _finish records the labor use (skills.md)
## — player actions record their own; defs never record twice.

@export var id: String             # "construction" / "hauling" — identifies this template.
@export var display_name: String   # "Construction" — Job Log / UI label.
@export var labor_id: String       # a LaborDef.id; gates get_best_job_for's filter.

## Required tool tag for this job (e.g. &"pickaxe", &"axe", &"pruning_kit").
@export var required_tool_tag: StringName = &""

## Animation to play during work execution (e.g. &"interact", &"digging").
@export var work_animation: StringName = &"Interact"

## Default work cycle duration in seconds if not dynamically scaled.
@export var work_duration: float = 1.2

## Default units of work accomplished per swing / work cycle.
@export var default_units_per_cycle: int = 20

## Base priority score for Utility AI evaluation.
@export var base_priority: float = 0.5

## Optional custom LimboAI behavior tree override (null uses generic worker BT).
@export var custom_subtree: BehaviorTree = null

## Max colonists that may be assigned to one Job of this def at once. 1 for
## single-colonist labors (construction); >1 lets a job be divvied (hauling).
@export var max_assignees: int = 1

## Actor requirements for jobs of this def — e.g. MinSkillCondition (the L1
## gate) or HasItemCondition. Reuses the Condition resource family that
## ActionOptions use (data/conditions/, subsystems/actions/), NOT ActionOption
## itself.
@export var conditions: Array[Condition] = []

## Whether the colonist must navigate to an adjacent cell (e.g. mining/building)
## or directly stand on the target location itself (e.g. deploy/stationing).
@export var requires_adjacent: bool = true


## True if `actor` satisfies every `conditions` entry, evaluated fresh against
## the job's target node. Empty conditions (the default) mean any colonist.
func meets_requirements(actor: Node, job: Variant) -> bool:
	return meets_requirements_any(actor, job)


## Supports both legacy Job and modern JobInstance.
func meets_requirements_any(actor: Node, job: Variant) -> bool:
	for condition in conditions:
		var t_node: Node = job.target_node if job != null and "target_node" in job else null
		if not condition.is_met(actor, t_node):
			return false
	return true


## Claimable right now? The labor-specific half of the gate (the board's slot
## half lives on Job.is_available). Override to drought-wait (hauling keeps an
## unsatisfied job registered but unclaimable until a crate restocks) or to
## hide work whose target stopped needing it.
func is_available(_job: Variant) -> bool:
	return true


## Board lifetime: true when the job should leave the registry. Called by the
## board's prune only when no assignees remain. Default mirrors availability —
## an unavailable job with nobody on it is dead. Drought-persistent defs
## override to decouple the two (unclaimable but alive).
func should_close(job: Variant) -> bool:
	return not is_available(job)


## Did a worked cycle actually satisfy the work? Distinguishes a clean finish
## from a stall (a hauler that ran out of sources short of the need).
func job_complete(_job: Variant) -> bool:
	return true


## Cycle duration in seconds BEFORE the skill multiplier — PerformWork applies
## `def.work_duration` first and only consults this when that is <= 0.0, so
## dynamic durations (blueprint build_time, recipe base_time, crop-driven
## harvest time) author the .tres with work_duration = 0.0 and override this.
## Return 0.0 to keep the authored/default duration.
func begin(_actor: Node, _job: Variant) -> float:
	return 0.0


## Terminal effect of one PerformWork cycle. The base default ends the job:
## skill XP + removal from the board. Subclasses apply the world effect first,
## then call _finish (or skip it to keep the job alive for another cycle —
## hauling's fetch/deliver loop).
func complete(actor: Node, job: Variant) -> void:
	_finish(actor, job)


## The cycle was preempted mid-work (a need won the dynamic selector, the
## agent was freed, ...). Default no-op; override to persist partial progress
## (blueprint/harvest work_done) or release held claims (crafting).
func on_abort(_actor: Node, _job: Variant, _elapsed: float) -> void:
	pass


## Walk target for THIS cycle, or null to use the board default (anchor cell /
## target node position). Multi-site labors override: hauling walks to a source
## crate while empty-handed and to the sink while carrying.
func work_site(_actor: Node, _job: Variant) -> Variant:
	return null


## End-of-job bookkeeping shared by every terminal path: record the labor's
## skill use and drop the job from the Colony board. Removal is idempotent —
## defs whose effect already closed the job (dig's EventBus round trip,
## blueprint_removed) may still call this.
func _finish(actor: Node, job: Variant) -> void:
	if actor != null and "skill_set" in actor and actor.skill_set != null \
			and labor_id != "" and "record_use_for_labor" in actor.skill_set:
		actor.skill_set.record_use_for_labor(labor_id)
	if job != null and "id" in job and str(job.id) != "" and actor is Node:
		var colony := (actor as Node).get_node_or_null("/root/Colony")
		if colony != null and "job_board" in colony and colony.job_board != null:
			colony.job_board.remove_job(str(job.id))
