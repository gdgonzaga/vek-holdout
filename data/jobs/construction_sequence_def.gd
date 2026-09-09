class_name ConstructionSequenceDef
extends JobSequenceDef
## JobSequence generator for placed Blueprints (ARCH "Subsystem: Build / Jobs").
##
## Produces a 2-step pipeline:
##   Step 0: HaulingJobDef (loops fetch/deliver until blueprint materials satisfied)
##   Step 1: ConstructionJobDef (works build_time to materialize structure)
## If the blueprint is costless or already pre-satisfied, Step 0 is omitted.

const HAULING_DEF := preload("res://data/jobs/hauling.tres")
const CONSTRUCTION_DEF := preload("res://data/jobs/construction.tres")


# =================
# Primary Functions
# =================

func _build_steps(sequence: JobSequence, target: Node, anchor: Vector3i) -> void:
	var bp := target as Blueprint
	if bp == null:
		return

	# 1. Blueprint Inspection: Check if materials are still needed.
	var needed: Array[String] = bp.needed_item_ids()

	if not needed.is_empty():
		# 2. Step 0 (Hauling): Create hauling job bound to blueprint sink.
		var haul_job: Job = _create_haul_step(bp, anchor)
		haul_job.sequence_id = sequence.id
		Colony.job_board.add_job(haul_job)
		sequence.add_step(haul_job.id)

	# 3. Step 1 (Construction): Create build job that materializes the blueprint.
	var build_job: Job = _create_build_step(bp, anchor)
	build_job.sequence_id = sequence.id
	Colony.job_board.add_job(build_job)
	sequence.add_step(build_job.id)


# ===================
# Auxiliary Functions
# ===================

func _create_haul_step(bp: Blueprint, anchor: Vector3i) -> Job:
	## Auxiliary: Builds the hauling Job instance targeting the Blueprint.
	var job := Job.from_def(HAULING_DEF)
	job.title = "Haul materials for %s" % bp.target_def_id
	job.anchor_cell = anchor
	job.target_node = bp
	job.location = bp.global_position if bp.is_inside_tree() else Vector3(anchor)
	return job


func _create_build_step(bp: Blueprint, anchor: Vector3i) -> Job:
	## Auxiliary: Builds the construction Job instance targeting the Blueprint.
	var job := Job.from_def(CONSTRUCTION_DEF)
	job.title = "Build %s" % bp.target_def_id
	job.anchor_cell = anchor
	job.target_node = bp
	job.location = bp.global_position if bp.is_inside_tree() else Vector3(anchor)
	return job
