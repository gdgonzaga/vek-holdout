extends RefCounted
class_name Job
## A unit of colonist work, owned by the JobBoard (ARCH "Subsystem: Colonists").
##
## A Job is created when something needs doing (a blueprint is placed → a
## construction job) and resolved through the lifecycle in job_board.gd
## (claim → complete / fail). This class is pure data; the JobBoard owns the
## registry and transitions, and ColonistAI drives the claim/path/work loop.
##
## Sprint scope note: `def`, `labor_id`, `anchor_cell`, `location`, `title`, and
## `target_node` are all exercised by the "colonist walks to and builds a
## blueprint" goal (ColonistAI WORK ticks job.def). `base_rate` remains
## forward-compat for the skill × stamina work-speed phase (GDD §6) and is unused.

## The JobDef template this job was built from (back-ref, like Furniture.def).
## Owns the WORK behaviour ColonistAI ticks on arrival (begin/complete). Set by
## Job.from_def / the producer; null on ad-hoc jobs (treated as instant work).
var def: JobDef = null

## Unique id (Tools.generate_uuid()). Set by the creator; the JobBoard keys on it.
var id: String = ""

## Which Labor this is (a LaborDef.id, e.g. "construction"). Drives priority
## selection against a colonist's `labor_priorities` in get_best_job_for.
var labor_id: String = ""

## Human-readable label, e.g. "Build workshop". For the Job Log UI.
var title: String = ""

## Voxel cell the job targets (a blueprint's anchor). Authoritative placement ref.
var anchor_cell: Vector3i = Vector3i.ZERO

## World-space point a colonist walks toward to reach this job. A best-effort
## footprint-center approximation set at creation; ColonistAI refines it into a
## real adjacent standing cell at navigation time (the walkability predicate picks
## a free neighbour then).
var location: Vector3 = Vector3.ZERO

## The in-world node being worked (e.g. the Blueprint), if any. Held as a weak
## Node ref so a freed/removed target can be detected. Unused this sprint.
var target_node: Node = null

## Base work rate multiplier (GDD §6: effective rate = base_rate × skill × stamina).
## Unused this sprint.
var base_rate: float = 1.0

## colonist_id of the claimer, or "" when unclaimed. Mutated only via JobBoard.
var claimed_by: String = ""

## Times this job has failed (JobBoard.fail increments). At >= 3 the board
## auto-removes it (early-MVP policy, ARCH "Job failure handling").
var failure_count: int = 0


## Build a Job from a JobDef: fresh uuid, the def back-ref, and the labor_id +
## title denormalized from the def so get_best_job_for / the Job Log don't need a
## def lookup. The caller still sets the per-placement binding (anchor_cell,
## location, target_node).
static func from_def(d: JobDef) -> Job:
	var job := Job.new()
	job.id = Tools.generate_uuid()
	job.def = d
	job.labor_id = d.labor_id
	job.title = d.display_name
	return job


func _to_string() -> String:
	return "Job(%s labor=%s @ %s)" % [id, labor_id, anchor_cell]
