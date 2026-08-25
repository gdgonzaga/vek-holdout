extends Resource
class_name JobDef
## Reusable template for one kind of colonist work (ARCH "Subsystem: Colonists",
## GDD §6.10). In the LimboAI + Fractional Job architecture, JobDef serves as a
## declarative data resource configuring required tool tags, animations, duration,
## work units, priority, and optional custom behavior trees.

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
func meets_requirements(actor: Node, job: Variant) -> bool:
	return meets_requirements_any(actor, job)


## Supports both legacy Job and modern JobInstance.
func meets_requirements_any(actor: Node, job: Variant) -> bool:
	for condition in conditions:
		var t_node: Node = job.target_node if job != null and "target_node" in job else null
		if not condition.is_met(actor, t_node):
			return false
	return true
