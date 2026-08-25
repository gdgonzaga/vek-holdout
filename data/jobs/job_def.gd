extends Resource
class_name JobDef
## Reusable template for one kind of colonist work (ARCH "Subsystem: Colonists",
## GDD §6.10). In the LimboAI + Fractional Job architecture, JobDef serves as a
## declarative data resource configuring required tool tags, animations, duration,
## work units, priority, and optional custom behavior trees.
##
## Legacy JobLeg methods are preserved for backward compatibility and marked @deprecated.

@export var id: String             # "construction" / "hauling" — identifies this template.
@export var display_name: String   # "Construction" — Job Log / UI label.
@export var labor_id: String       # a LaborDef.id; gates get_best_job_for's filter.

## Required tool tag for this job (e.g. &"pickaxe", &"axe", &"pruning_kit").
@export var required_tool_tag: StringName = &""

## Animation to play during work execution (e.g. &"interact", &"digging").
@export var work_animation: StringName = &"interact"

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


## True if `actor` satisfies every `conditions` entry, evaluated fresh against
## the job's target node. Empty conditions (the default) mean any colonist.
func meets_requirements(actor: Node, job: Job) -> bool:
	return meets_requirements_any(actor, job)


## Supports both legacy Job and modern JobInstance.
func meets_requirements_any(actor: Node, job: Variant) -> bool:
	for condition in conditions:
		var t_node: Node = job.target_node if job != null and "target_node" in job else null
		if not condition.is_met(actor, t_node):
			return false
	return true


# ==============================================================================
# LEGACY / DEPRECATED: JobLeg procedural state machine methods
# Kept for backward compatibility during LimboAI migration (see tech-debt.md).
# ==============================================================================

## @deprecated Use LimboAI behavior trees and JobInstance instead.
func get_next_leg(_actor: Node, _job: Job) -> JobLeg:
	return null


## @deprecated Use BTActionPerformWork and JobInstance instead.
func begin(_actor: Node, _leg: JobLeg, _job: Job) -> float:
	return 0.0


## @deprecated Use JobInstance.complete_claim / apply_work_units instead.
func complete(_actor: Node, _leg: JobLeg, _job: Job) -> void:
	pass


## @deprecated Use WorkerClaim.abandon / complete_claim instead.
func on_end(_success: bool, _actor: Node, _leg: JobLeg, _job: Job, _elapsed: float) -> void:
	pass


## @deprecated Use JobInstance.is_available instead.
func is_available(_job: Job) -> bool:
	return true


## @deprecated Use JobInstance.should_close / is_completed instead.
func should_close(job: Job) -> bool:
	return not is_available(job)


## @deprecated Use JobInstance.is_completed instead.
func job_complete(_job: Job) -> bool:
	return true
