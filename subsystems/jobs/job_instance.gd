class_name JobInstance
extends RefCounted
## A unified fractional unit of work, supporting multi-colonist concurrent mining/building
## and atomic batch hauling.

## Emitted whenever unclaimed units change or the job's availability state flips.
signal availability_changed()

## Emitted whenever work progress is recorded against this job.
signal units_progressed(completed_units: int, total_units: int)

## Emitted when all required work units are completed.
signal job_completed()

## Emitted when the job is cancelled.
signal job_cancelled()

## Unique identifier for this job instance
var id: String = ""

## The template JobDef resource
var job_def: JobDef = null

## The labor category (e.g. &"mining", &"hauling", &"construction")
var labor_id: StringName = &""

## Human-readable title
var title: String = ""

## World-space position for work / destination
var world_position: Vector3 = Vector3.ZERO

## Source world-space position (used for hauling / item pickup)
var source_position: Vector3 = Vector3.ZERO

## Target world-space position (used for hauling / deposit or placement)
var target_position: Vector3 = Vector3.ZERO

## Voxel anchor coordinate if tied to a specific block or blueprint
var anchor_cell: Vector3i = Vector3i.ZERO

## Associated world node (e.g. Blueprint, Tree, Crop, Storage)
var target_node: Node = null

## Item ID for hauling tasks
var item_id: StringName = &""

## Total work units or item count required to finish the job
var total_units: int = 100

## Remaining unreserved work units available for workers to claim
var unclaimed_units: int = 100

## Work units completed so far
var completed_units: int = 0

## Active worker claims: colonist_id (String) -> WorkerClaim
var active_claims: Dictionary = {}

## True if all required units are finished
var is_completed: bool = false

## True if the job was cancelled
var is_cancelled: bool = false


## Factory for standard spatial work jobs (mining, farming, building, crafting).
static func create(
	p_def: JobDef,
	p_total_units: int = 100,
	p_pos: Vector3 = Vector3.ZERO,
	p_target: Node = null
) -> JobInstance:
	var job := JobInstance.new()
	job.id = Tools.generate_uuid() if ClassDB.class_exists(&"Tools") and Tools.has_method("generate_uuid") else str(ResourceUID.create_id())
	job.job_def = p_def
	if p_def:
		job.labor_id = StringName(p_def.labor_id)
		job.title = p_def.display_name
	job.world_position = p_pos
	job.target_position = p_pos
	job.target_node = p_target
	job.total_units = maxi(1, p_total_units)
	job.unclaimed_units = job.total_units
	job.completed_units = 0
	return job


## Factory for hauling and batch transport jobs.
static func create_haul(
	p_def: JobDef,
	p_item_id: StringName,
	p_amount: int,
	p_source: Vector3,
	p_target: Vector3,
	p_target_node: Node = null
) -> JobInstance:
	var job := JobInstance.new()
	job.id = Tools.generate_uuid() if ClassDB.class_exists(&"Tools") and Tools.has_method("generate_uuid") else str(ResourceUID.create_id())
	job.job_def = p_def
	if p_def:
		job.labor_id = StringName(p_def.labor_id)
		job.title = p_def.display_name
	else:
		job.labor_id = &"hauling"
		job.title = "Haul Items"
	job.item_id = p_item_id
	job.source_position = p_source
	job.target_position = p_target
	job.world_position = p_target
	job.target_node = p_target_node
	job.total_units = maxi(1, p_amount)
	job.unclaimed_units = job.total_units
	job.completed_units = 0
	return job


## Attempts to reserve a batch of work units for a colonist.
func try_claim_units(colonist: Variant, requested_units: int = -1) -> WorkerClaim:
	if is_completed or is_cancelled or unclaimed_units <= 0:
		return null
		
	var cid := _resolve_colonist_id(colonist)
	if cid == "":
		return null
		
	# If this worker already holds an active claim on this job, return it
	if active_claims.has(cid):
		return active_claims[cid] as WorkerClaim
		
	var capacity: int = unclaimed_units
	if requested_units > 0:
		capacity = requested_units
	elif colonist is Object and colonist != null:
		if colonist.has_method("get_work_capacity"):
			capacity = int(colonist.get_work_capacity(job_def))
		elif item_id != &"" and "inventory" in colonist and colonist.inventory != null and colonist.inventory.has_method("remaining_capacity"):
			capacity = int(colonist.inventory.remaining_capacity())
		elif job_def != null and job_def.default_units_per_cycle > 0:
			capacity = job_def.default_units_per_cycle
			
	var claim_amount: int = mini(unclaimed_units, maxi(1, capacity))
	if claim_amount <= 0:
		return null
		
	unclaimed_units -= claim_amount
	var target_pos: Vector3 = target_position if target_position != Vector3.ZERO else world_position
	var claim := WorkerClaim.new(self, cid, claim_amount, target_pos, source_position)
	active_claims[cid] = claim
	
	availability_changed.emit()
	return claim


## Convenience alias for batch hauling reservations.
func reserve_batch(batch_amount: int, colonist: Variant) -> WorkerClaim:
	return try_claim_units(colonist, batch_amount)


## Abandons an active claim and restores unworked units back to the unclaimed pool.
func abandon_claim(colonist_id: String) -> void:
	if not active_claims.has(colonist_id):
		return
		
	var claim: WorkerClaim = active_claims[colonist_id]
	var unworked: int = maxi(0, claim.claimed_units - claim.completed_units)
	unclaimed_units += unworked
	active_claims.erase(colonist_id)
	
	availability_changed.emit()


## Marks finished work units on an active claim.
func complete_claim(colonist_id: String, finished_units: int) -> int:
	if is_completed or is_cancelled or finished_units <= 0:
		return 0
		
	var actual_units: int = finished_units
	if active_claims.has(colonist_id):
		var claim: WorkerClaim = active_claims[colonist_id]
		var remaining_in_claim: int = maxi(0, claim.claimed_units - claim.completed_units)
		actual_units = mini(finished_units, remaining_in_claim)
		claim.completed_units += actual_units
		if claim.is_finished():
			active_claims.erase(colonist_id)
			
	completed_units = mini(total_units, completed_units + actual_units)
	units_progressed.emit(completed_units, total_units)
	
	if completed_units >= total_units:
		is_completed = true
		job_completed.emit()
		
	availability_changed.emit()
	return actual_units


## Directly applies work units (used by standalone tasks or test harnesses).
func apply_work_units(units: int, worker: Node = null) -> int:
	if is_completed or is_cancelled or units <= 0:
		return 0
		
	if worker != null:
		var cid := _resolve_colonist_id(worker)
		if cid != "":
			if active_claims.has(cid):
				return complete_claim(cid, units)
			else:
				var claim := try_claim_units(worker, units)
				if claim:
					return complete_claim(cid, units)
					
	# Fallback direct progression
	var to_apply: int = mini(units, get_remaining_uncompleted_units())
	completed_units += to_apply
	unclaimed_units = maxi(0, total_units - completed_units - _get_active_reserved_units())
	units_progressed.emit(completed_units, total_units)
	
	if completed_units >= total_units:
		is_completed = true
		job_completed.emit()
		
	availability_changed.emit()
	return to_apply


## Cancels the job and releases all active claims.
func cancel_job() -> void:
	if is_cancelled:
		return
	is_cancelled = true
	active_claims.clear()
	unclaimed_units = 0
	job_cancelled.emit()
	availability_changed.emit()


## True if the job can accept more worker claims.
func is_available() -> bool:
	return not is_completed and not is_cancelled and unclaimed_units > 0


## Total work units left until job completion.
func get_remaining_uncompleted_units() -> int:
	return maxi(0, total_units - completed_units)


## Total units actively reserved by workers.
func _get_active_reserved_units() -> int:
	var sum: int = 0
	for claim: WorkerClaim in active_claims.values():
		sum += (claim.claimed_units - claim.completed_units)
	return sum


func _resolve_colonist_id(colonist: Variant) -> String:
	if colonist is String:
		return colonist
	if colonist is StringName:
		return str(colonist)
	if colonist is Object and colonist != null:
		if "colonist_id" in colonist and str(colonist.colonist_id) != "":
			return str(colonist.colonist_id)
		if colonist is Node:
			return colonist.name
		return str(colonist.get_instance_id())
	return ""


func _to_string() -> String:
	return "JobInstance(%s, %s, units=%d/%d, claims=%d)" % [
		id,
		title,
		completed_units,
		total_units,
		active_claims.size()
	]
