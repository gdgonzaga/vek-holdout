class_name JobSequence
extends RefCounted
## Runtime container for an ordered sequence of Jobs (ARCH "Subsystem: Jobs").
##
## Coordinates multi-stage pipelines (e.g. Haul -> Build, Haul -> Craft, Till -> Sow).
## The sequence is registered with JobBoard, which tracks active step progression,
## gates future steps from worker claims, and cascades cancellation.

enum Status {
	PENDING = 0,
	ACTIVE = 1,
	COMPLETED = 2,
	CANCELLED = 3,
}

## Unique identifier for this sequence.
var id: String = ""

## Human-readable title for inspection / UI.
var title: String = ""

## Anchor cell in the voxel world, matching target placement.
var anchor_cell: Vector3i = Vector3i.ZERO

## Associated world node (e.g. Blueprint, CraftingStation, FarmPlot).
var target_node: Node = null

## Ordered list of job IDs belonging to this sequence.
var step_job_ids: Array[String] = []

## Index of the currently active step.
var current_step_index: int = 0

## Current lifecycle status.
var status: Status = Status.ACTIVE

## Optional restriction: if true, all steps must be performed by the same colonist.
var require_same_worker: bool = false

## Colonist ID assigned if require_same_worker is true.
var bound_colonist_id: String = ""


# =================
# Primary Functions
# =================

## Adds a job ID to the sequence pipeline.
func add_step(job_id: String) -> void:
	# 1. Pipeline Validation: Ensure unique and non-empty job registration.
	_append_step_job(job_id)


## Returns true if job_id is the currently active step in this sequence.
func is_step_active(job_id: String) -> bool:
	if status != Status.ACTIVE:
		return false
	if current_step_index < 0 or current_step_index >= step_job_ids.size():
		return false
	return step_job_ids[current_step_index] == job_id


## Advances the sequence to the next step, or completes if all steps are done.
func advance_step() -> void:
	# 1. State Progression: Increment index and evaluate completion boundary.
	_progress_step_index()


## Cancels the sequence and all child jobs.
func cancel() -> void:
	status = Status.CANCELLED


## Serializes sequence state for SaveSystem / Colony persistence.
func serialize() -> Dictionary:
	return {
		"id": id,
		"title": title,
		"anchor_cell": [anchor_cell.x, anchor_cell.y, anchor_cell.z],
		"step_job_ids": step_job_ids.duplicate(),
		"current_step_index": current_step_index,
		"status": int(status),
		"require_same_worker": require_same_worker,
		"bound_colonist_id": bound_colonist_id,
	}


## Deserializes sequence state from saved dictionary.
func deserialize(data: Dictionary) -> void:
	id = str(data.get("id", ""))
	title = str(data.get("title", ""))
	var a: Array = data.get("anchor_cell", [0, 0, 0])
	if a.size() >= 3:
		anchor_cell = Vector3i(int(a[0]), int(a[1]), int(a[2]))
	step_job_ids.assign(data.get("step_job_ids", []))
	current_step_index = int(data.get("current_step_index", 0))
	status = int(data.get("status", Status.ACTIVE)) as Status
	require_same_worker = bool(data.get("require_same_worker", false))
	bound_colonist_id = str(data.get("bound_colonist_id", ""))


# ===================
# Auxiliary Functions
# ===================

func _append_step_job(job_id: String) -> void:
	## Auxiliary: Appends job_id to steps if non-empty and not duplicated.
	if job_id != "" and not step_job_ids.has(job_id):
		step_job_ids.append(job_id)


func _progress_step_index() -> void:
	## Auxiliary: Advances the current active step index or marks completed.
	current_step_index += 1
	if current_step_index >= step_job_ids.size():
		status = Status.COMPLETED
