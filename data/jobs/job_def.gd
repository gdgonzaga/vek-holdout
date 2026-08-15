extends Resource
class_name JobDef
## Reusable template for one kind of colonist work (ARCH "Subsystem: Colonists",
## GDD §6.10). One subclass per Labor; a Job instance carries a `def` back-ref
## (like Furniture.def) plus the per-placement binding (which blueprint, where).
##
## A JobDef owns two things:
##   1. Data: id / display_name / labor_id / max_assignees — authored as a .tres
##      via script_class, designers tune these.
##   2. Leg behaviour: a job is a sequence of JobLegs (walk→act). get_next_leg
##      produces the next leg for a colonist (null when that colonist is done);
##      begin reports the leg's work duration (0 = instant), complete applies the
##      leg's effect, on_end cleans up when a colonist leaves the job, and
##      is_available / should_close / job_complete gate its board lifetime and
##      completion semantics. This mirrors the behaviour-bearing Resource
##      precedent (GameAction, Condition) — the behaviour lives here rather
##      than on the Furniture because it depends on Job parameters the Furniture
##      doesn't know (e.g. a craft job's duration = recipe.base_time × quantity).
##
## Multi-assign: a Job may accept up to `max_assignees` colonists at once
## (Job.is_available = the slot gate && def.is_available(self)). Construction is
## single-colonist (1); hauling allows several haulers to divvy a material run
## through the blueprint's shared deposit counter — "one colonist finishing ≠
## job done" until the blueprint's has_complete_materials() flips.
##
## ColonistAI drives the per-frame tick and the leg loop; it knows nothing about
## what a leg does — only walk→begin→complete→advance.

@export var id: String             # "construction" / "hauling" — identifies this template.
@export var display_name: String   # "Construction" — Job Log / UI label.
@export var labor_id: String       # a LaborDef.id; gates get_best_job_for's filter.

## Max colonists that may be assigned to one Job of this def at once. 1 for
## single-colonist labors (construction); >1 lets a job be divvied (hauling).
@export var max_assignees: int = 1

## Actor requirements for jobs of this def — e.g. MinSkillCondition (the L1
## gate) or HasItemCondition. Reuses the Condition resource family that
## ActionOptions use (data/conditions/, subsystems/actions/), NOT ActionOption
## itself (its label + GameAction are interaction-menu coupling a job lacks).
##
## Contract: these are HOT — JobBoard.get_best_job_for and Job.try_assign
## evaluate them fresh on every poll/claim, so a condition may flip mid-job
## run and the next evaluation sees it (unlike ActionOptions, which are checked
## once when the interaction menu opens). Never cache the result. Keep them
## actor-inherent facts (skill, carried items); world facts a def can check
## procedurally (does a crate stock the tool?) belong in get_next_leg /
## is_available instead — a def-level tool condition would lock out the very
## colonists the job's FETCH_TOOL leg exists for.
@export var conditions: Array[Condition] = []


## True if `actor` satisfies every `conditions` entry, evaluated fresh against
## the job's target node. Empty conditions (the default) mean any colonist.
## Enforced by JobBoard.get_best_job_for (skip — no claim/release churn) and
## Job.try_assign (the authoritative gate). Conditions must tolerate a null
## target (patrol-style jobs have no target node).
func meets_requirements(actor: Node, job: Job) -> bool:
	for condition in conditions:
		if not condition.is_met(actor, job.target_node):
			return false
	return true


## The next leg for `actor` on `job`, or null when this colonist has no further
## work (it should leave the job). Called at claim (leg 0) and after each leg's
## begin/complete. Per-run state lives on the colonist (e.g. carry inventory) or
## is derived from the job target (e.g. a blueprint's material progress) — NOT on
## this shared def. Base default: no legs (the colonist finishes immediately).
func get_next_leg(_actor: Node, _job: Job) -> JobLeg:
	return null


## Setup + report this leg's work duration in seconds. Called when the colonist
## arrives at the leg's target. Return 0.0 for an instant leg (the AI calls
## complete() the same tick and advances); >0.0 enters WORK and ticks. Override
## per Labor. The base default is instant.
func begin(_actor: Node, _leg: JobLeg, _job: Job) -> float:
	return 0.0


## Apply this leg's effect. Called when begin's duration elapses (or immediately
## when begin returned <= 0). Override per Labor. Base default: no-op.
func complete(_actor: Node, _leg: JobLeg, _job: Job) -> void:
	pass


## Cleanup when a colonist leaves the job. `success` is true on a clean finish
## (get_next_leg returned null and job_complete says the job is done), false on
## an abort (target freed / next leg unreachable) or a stall. Use to return
## carried items, persist partial progress, etc. `elapsed` is the WORK time
## accumulated on the current leg (for timed legs). `leg` is null when the
## colonist was released before ever receiving leg 0 (claim-path miss) — defs
## must tolerate that. Base default: no-op.
func on_end(_success: bool, _actor: Node, _leg: JobLeg, _job: Job, _elapsed: float) -> void:
	pass


## Can this job currently accept more work / another colonist? Combined with the
## Job's own slot count in Job.is_available. Override to gate on labor-specific
## state — e.g. hauling returns false once the blueprint is satisfied or no
## source crate has the needed materials. Base default: always available.
func is_available(_job: Job) -> bool:
	return true


## True when the job should leave the board: its work is resolved or its target
## is gone. Split from is_available so a def can keep a job registered while it
## is temporarily unclaimable — a haul job survives a source drought (waiting
## for restock) and only closes once its sink is satisfied or gone. The board's
## prune and ColonistAI's removal consult this, never raw is_available, so
## waiting jobs aren't deleted at the first selection sweep. Base default:
## close exactly when not available.
func should_close(job: Job) -> bool:
	return not is_available(job)


## Whether a null get_next_leg means the job finished cleanly (true — success
## and skill XP) versus the colonist stalling without completing it (false —
## e.g. a hauler that drained every crate short of the sink's need). Base
## default: null leg = done.
func job_complete(_job: Job) -> bool:
	return true
