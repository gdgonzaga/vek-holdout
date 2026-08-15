extends RefCounted
class_name Job
## A unit of colonist work, owned by the JobBoard (ARCH "Subsystem: Colonists").
##
## A Job is created when something needs doing (a blueprint is placed → a
## construction or hauling job) and resolved through the lifecycle in
## job_board.gd. This class is pure data + the multi-assign claim bookkeeping
## (try_assign/unassign/is_available/should_close); the JobBoard owns the
## registry, ColonistAI drives the leg loop, and the JobDef owns the behaviour.
##
## Multi-assign: up to `max_assignees` colonists may work one Job at once. A
## colonist leaving (leg exhaustion or abort) calls unassign; the Job leaves the
## board only when should_close() — no assignees left AND not accepting more
## (e.g. a haul job whose blueprint is now satisfied, or one that lost its source
## crate). So one colonist finishing ≠ job done.
##
## Sprint scope: def/labor_id/anchor_cell/location/title/target_node are
## exercised by construction + hauling. base_rate remains forward-compat for the
## skill × stamina work-speed phase (GDD §6) and is unused.

## The JobDef template this job was built from (back-ref, like Furniture.def).
## Owns the leg behaviour (get_next_leg/begin/complete/on_end/is_available). Set
## by Job.from_def / the producer; null on ad-hoc jobs (treated as instant).
var def: JobDef = null

## Unique id (Tools.generate_uuid()). Set by the creator; the JobBoard keys on it.
var id: String = ""

## Which Labor this is (a LaborDef.id, e.g. "construction" or "hauling"). Drives
## priority selection against a colonist's `labor_priorities` in get_best_job_for.
var labor_id: String = ""

## Human-readable label, e.g. "Build workshop". For the Job Log UI.
var title: String = ""

## Voxel cell the job targets (a blueprint's anchor). Authoritative placement ref.
var anchor_cell: Vector3i = Vector3i.ZERO

## World-space point a colonist walks toward to reach this job. A best-effort
## footprint-center approximation set at creation; ColonistAI refines it into a
## real adjacent standing cell at navigation time.
var location: Vector3 = Vector3.ZERO

## The in-world node being worked (e.g. the Blueprint), if any. Held as a weak
## Node ref so a freed/removed target can be detected.
var target_node: Node = null

## Base work rate multiplier (GDD §6: effective rate = base_rate × skill × stamina).
## Unused this sprint.
var base_rate: float = 1.0

## Max colonists that may be assigned at once (copied from def.max_assignees).
var max_assignees: int = 1

## colonist_ids currently assigned to this job. Mutated only via try_assign/
## unassign/clear_assigned. Drives the slot half of is_available + the drain
## check in should_close.
var _assigned_colonists: Array[String] = []

## Times this job has failed (JobBoard.fail increments). At >= 3 the board
## auto-removes it (early-MVP policy, ARCH "Job failure handling").
var failure_count: int = 0


## Build a Job from a JobDef: fresh uuid, the def back-ref, the labor_id +
## title denormalized from the def so get_best_job_for / the Job Log don't need a
## def lookup, and max_assignees copied for the slot gate. The caller still sets
## the per-placement binding (anchor_cell, location, target_node).
static func from_def(d: JobDef) -> Job:
	var job := Job.new()
	job.id = Tools.generate_uuid()
	job.def = d
	job.labor_id = d.labor_id
	job.title = d.display_name
	job.max_assignees = d.max_assignees
	return job


## True if `colonist_id` is currently assigned to this job.
func is_assigned(colonist_id: String) -> bool:
	return _assigned_colonists.has(colonist_id)


## Try to assign `colonist` to this job. Returns true on success, false if the
## job can't accept it (full, no longer available, already assigned, or the
## colonist fails the def's actor requirements — the authoritative condition
## gate; get_best_job_for pre-filters with the same check so a failure here
## means the condition flipped mid-poll). Pull, not push: this only registers
## the colonist — it then asks get_next_leg when ready (at claim, and after
## each leg).
func try_assign(colonist: Colonist) -> bool:
	var cid := colonist.colonist_id
	if not is_available() or is_assigned(cid):
		return false
	if def != null and not def.meets_requirements(colonist, self):
		return false
	_assigned_colonists.append(cid)
	return true


## Release `colonist` from this job (leg exhaustion or abort). No-op if it wasn't
## assigned. The caller checks should_close() afterward to decide removal.
func unassign(colonist: Colonist) -> void:
	_assigned_colonists.erase(colonist.colonist_id)


## Release every assignee (used by the failure path). Unlike unassign(colonist),
## this does not go through a Colonist ref, so on_end cleanup is the caller's job.
func clear_assigned() -> void:
	_assigned_colonists.clear()


## Can this job accept more work right now? The slot gate (assignees < max) AND
## the def's labour-specific gate (e.g. blueprint still unsatisfied + source in
## stock for hauling). Drives get_best_job_for's filter and the dead-job prune.
func is_available() -> bool:
	return _assigned_colonists.size() < max_assignees and (def == null or def.is_available(self))


## True when the job should leave the board: no colonists left AND it can't
## accept more (satisfied, cancelled, or unsatisfiable). Called by ColonistAI
## after unassign; if true, the AI removes the job from the JobBoard.
func should_close() -> bool:
	return _assigned_colonists.is_empty() and not is_available()


func _to_string() -> String:
	return "Job(%s labor=%s @ %s)" % [id, labor_id, anchor_cell]
