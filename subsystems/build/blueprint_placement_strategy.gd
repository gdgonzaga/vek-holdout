class_name BlueprintPlacementStrategy
extends RefCounted
## Placement strategy that spawns a blueprint — the non-physical plan form (GDD
## §7.4) — instead of materializing the buildable directly. The player (and
## later a colonist via the JobBoard) completes the blueprint by interacting
## with it: see Blueprint.complete / BlueprintLayer.complete_blueprint.
##
## The second IPlacementStrategy impl alongside InstantPlacementStrategy. The
## controller is oblivious to the difference: it still calls
## commit(transform, rotation, item_id). This strategy handles BOTH BlockDef and
## non-block defs — it looks the def up in BuildLibrary and lets BlueprintLayer
## size the blueprint to the target's footprint (1x1x1 for blocks).

var _blueprint_layer: BlueprintLayer = null


func set_blueprint_layer(layer: BlueprintLayer) -> void:
	_blueprint_layer = layer


## Spawn a blueprint for item_id at the committed transform. Returns true on
## success, false if unwired / unknown id.
func commit(transform: Transform3D, _rotation, item_id: String) -> bool:
	if _blueprint_layer == null or item_id == "":
		return false
	var def := BuildLibrary.get_def(item_id)
	if def == null:
		return false
	var o := transform.origin
	var cell := Vector3i(int(floor(o.x)), int(floor(o.y)), int(floor(o.z)))
	# `rotation` is the RotationState the controller passes; .step is the 0..3
	# yaw used for furniture footprints. Guard for a serialized int form too.
	var step := 0
	if _rotation is RotationState:
		step = _rotation.step
	elif _rotation is int:
		step = _rotation
	_blueprint_layer.spawn_blueprint(def, cell, step)
	return true
