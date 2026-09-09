class_name CraftingSequenceDef
extends JobSequenceDef
## JobSequence generator for CraftingStation orders (ARCH "Subsystem: Crafting / Jobs").
##
## Produces a 2-step pipeline:
##   Step 0: HaulingJobDef (loops fetch/deliver until station materials satisfied)
##   Step 1: CraftingJobDef (works recipe.base_time to produce item outputs)

const HAULING_DEF := preload("res://data/jobs/hauling.tres")
const CRAFTING_DEF := preload("res://data/jobs/crafting.tres")


# =================
# Primary Functions
# =================

func _build_steps(sequence: JobSequence, target: Node, anchor: Vector3i) -> void:
	var station := target as CraftingStation
	if station == null:
		return

	# 1. Step 0 (Hauling): Create hauling job bound to station if materials are needed.
	if not station.has_complete_materials():
		var haul_job: Job = _create_haul_step(station, anchor)
		haul_job.sequence_id = sequence.id
		Colony.job_board.add_job(haul_job)
		sequence.add_step(haul_job.id)

	# 2. Step 1 (Crafting): Create craft job to produce the active recipe.
	var craft_job: Job = _create_craft_step(station, anchor)
	craft_job.sequence_id = sequence.id
	Colony.job_board.add_job(craft_job)
	sequence.add_step(craft_job.id)


# ===================
# Auxiliary Functions
# ===================

func _create_haul_step(station: CraftingStation, anchor: Vector3i) -> Job:
	## Auxiliary: Builds the hauling Job instance targeting the CraftingStation.
	var job := Job.from_def(HAULING_DEF)
	job.title = "Haul materials for crafting"
	job.anchor_cell = anchor
	job.target_node = station
	job.location = _station_location(station)
	return job


func _create_craft_step(station: CraftingStation, anchor: Vector3i) -> Job:
	## Auxiliary: Builds the crafting Job instance targeting the CraftingStation.
	var recipe: RecipeDef = station.active_recipe()
	var label: String = recipe.label() if recipe != null else "order"
	var job := Job.from_def(CRAFTING_DEF)
	job.title = "Craft %s" % label
	job.anchor_cell = anchor
	job.target_node = station
	job.location = _station_location(station)
	return job


func _station_location(station: CraftingStation) -> Vector3:
	## Auxiliary: Resolves world position of workstation furniture.
	var furniture := station.get_parent() as Node3D
	if furniture != null:
		return furniture.global_position if furniture.is_inside_tree() else furniture.position
	return Vector3.ZERO
