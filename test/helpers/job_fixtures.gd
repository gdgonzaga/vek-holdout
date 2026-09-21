extends RefCounted
## In-memory JobDefs for suites that exercise job plumbing (board claiming, sequences,
## hauling legs). The shipped data/jobs/*.tres are retuned as the game is balanced, so a
## test that loads them breaks on a content edit. Every value here is explicit and owned by
## the tests, not by game content; change one only together with the tests that read it.
##
## Each function returns a fresh def (Resources are ref-counted, nothing to free), so a test
## may mutate its copy freely. Ids are synthetic ("test_*"); labor ids and equipment tags are
## the code-level vocabulary the board and Colony route on, chosen to match what the plumbing
## expects (Colonist.labor_priorities keys, JobDef.required_equipped_tags).
##
## Usage:
##   const JobFixtures = preload("res://test/helpers/job_fixtures.gd")
##   var def: HaulingJobDef = JobFixtures.hauling()


# =================
# Primary Functions
# =================

## Sink/ground hauling: up to 3 haulers share one job, one short cycle per leg, no conditions.
## Sets: id, display_name, labor_id = "hauling", max_assignees = 3, work_duration = 0.1.
static func hauling() -> HaulingJobDef:
	# 1. Common Fields: id, label and labor so the board can route and label the job.
	var def := HaulingJobDef.new()
	_set_identity(def, "test_hauling", "Test Hauling", "hauling")
	def.max_assignees = 3
	def.work_duration = 0.1
	return def


## Blueprint construction: single builder, dynamic duration (begin() reads the target's build_time).
## Sets: id, display_name, labor_id = "construction", required_equipped_tags = [&"construction_tool"],
## work_duration = 0.0 (dynamic; max_assignees stays at the JobDef default of 1).
static func construction() -> ConstructionJobDef:
	# 1. Common Fields: id, label and labor so the board can route and label the job.
	var def := ConstructionJobDef.new()
	_set_identity(def, "test_construction", "Test Construction", "construction")
	# 2. Equipment Gate: builders must hold a tool carrying this tag.
	_set_required_tags(def, [&"construction_tool"])
	def.work_duration = 0.0
	return def


## Crafting at a station: single crafter, dynamic duration (begin() reads the recipe's base_time).
## Sets: id, display_name, labor_id = "crafting", work_duration = 0.0.
static func crafting() -> CraftingJobDef:
	# 1. Common Fields: id, label and labor so the board can route and label the job.
	var def := CraftingJobDef.new()
	_set_identity(def, "test_crafting", "Test Crafting", "crafting")
	def.work_duration = 0.0
	return def


## Persistent stationing: never leaves the board, stands on the target cell itself.
## Sets: id, display_name, labor_id = "deploy", work_animation = &"Idle", work_duration = 1.0,
## default_units_per_cycle = 0, base_priority = 2.0, requires_adjacent = false.
static func deploy() -> DeployJobDef:
	# 1. Common Fields: id, label and labor so the board can route and label the job.
	var def := DeployJobDef.new()
	_set_identity(def, "test_deploy", "Test Deploy", "deploy")
	def.work_animation = &"Idle"
	def.work_duration = 1.0
	def.default_units_per_cycle = 0
	def.base_priority = 2.0
	def.requires_adjacent = false
	return def


## Terrain digging: single digger, 2 s cycle.
## Sets: id, display_name, labor_id = "mining", required_equipped_tags = [&"mining_tool"],
## work_animation = &"Digging", work_duration = 2.0.
static func dig() -> DigJobDef:
	# 1. Common Fields: id, label and labor so the board can route and label the job.
	var def := DigJobDef.new()
	_set_identity(def, "test_dig", "Test Dig", "mining")
	# 2. Equipment Gate: diggers must hold a tool carrying this tag.
	_set_required_tags(def, [&"mining_tool"])
	def.work_animation = &"Digging"
	def.work_duration = 2.0
	return def


# ===================
# Auxiliary Functions
# ===================

static func _set_identity(def: JobDef, id: String, display_name: String, labor_id: String) -> void:
	## Auxiliary: the three fields every fixture must carry (JobDef.id / display_name / labor_id).
	def.id = id
	def.display_name = display_name
	def.labor_id = labor_id


static func _set_required_tags(def: JobDef, tags: Array[StringName]) -> void:
	## Auxiliary: typed assignment of JobDef.required_equipped_tags (an Array[StringName] export).
	def.required_equipped_tags = tags
