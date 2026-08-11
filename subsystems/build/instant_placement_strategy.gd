class_name InstantPlacementStrategy
extends RefCounted
## MVP/debug placement strategy (ARCH "Build", line 454): materializes the
## buildable directly at the committed transform — no blueprint, no labor.
## Handles BOTH kinds now that BuildController routes every commit through the
## strategy: BlockDef -> VoxelGridAdapter.set_block_at; everything else ->
## FurnitureLayer.spawn. Goes through these adapters (never the raw VoxelGrid)
## so voxel coupling stays behind the IBlockGrid contract.
##
## commit() resolves the integer cell from the transform origin and dispatches by
## def kind. Cost deduction is deferred (see TODO below).

var _grid: VoxelGridAdapter = null       # set via set_grid(); same-subsystem, so no voxel/ import here.
var _furniture_layer: FurnitureLayer = null # set via set_furniture_layer(); for non-block defs.


func set_grid(grid: VoxelGridAdapter) -> void:
	_grid = grid


func set_furniture_layer(fl: FurnitureLayer) -> void:
	_furniture_layer = fl


## Place item_id at transform. Returns true on success, false if unwired/unknown.
## Cost deduction is deferred (see TODO below).
func commit(transform: Transform3D, _rotation, item_id: String) -> bool:
	if item_id == "":
		return false
	var def := BuildLibrary.get_def(item_id)
	if def == null:
		return false
	var o := transform.origin
	var cell := Vector3i(int(floor(o.x)), int(floor(o.y)), int(floor(o.z)))
	# TODO(cost): once a materials store exists, check+deduct def.get_cost()
	# here before placing.
	if def is BlockDef:
		if _grid == null:
			return false
		_grid.set_block_at(cell, item_id)
	else:
		if _furniture_layer == null:
			return false
		var step := 0
		if _rotation is RotationState:
			step = _rotation.step
		_furniture_layer.spawn(def, cell, step)
	return true
