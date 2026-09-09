class_name JobSequenceDef
extends Resource
## Data-driven template and factory for multi-step JobSequences (ARCH "Subsystem: Jobs").
##
## Subclasses define specific sequence generators (e.g. ConstructionSequenceDef,
## CraftingSequenceDef) that inspect the target and construct the ordered Job pipeline.

@export var id: String = ""
@export var display_name: String = ""


# =================
# Primary Functions
# =================

## Factory method to create a JobSequence instance bound to target and anchor.
func create_sequence(target: Node, anchor: Vector3i) -> JobSequence:
	# 1. Container Initialization: Instantiate and configure the base JobSequence.
	var seq: JobSequence = _instantiate_sequence(target, anchor)
	
	# 2. Step Population: Subclass virtual hook to build and append ordered jobs.
	_build_steps(seq, target, anchor)
	return seq


# ===================
# Auxiliary Functions
# ===================

func _instantiate_sequence(target: Node, anchor: Vector3i) -> JobSequence:
	## Auxiliary: Creates the JobSequence container with default metadata.
	var seq := JobSequence.new()
	seq.id = Tools.generate_uuid() if ClassDB.class_exists(&"Tools") and Tools.has_method("generate_uuid") else str(ResourceUID.create_id())
	seq.title = display_name
	seq.target_node = target
	seq.anchor_cell = anchor
	return seq


func _build_steps(_sequence: JobSequence, _target: Node, _anchor: Vector3i) -> void:
	## Auxiliary / Virtual: Subclasses override to populate jobs into sequence.
	pass
