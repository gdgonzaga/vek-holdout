class_name InstantPlacementStrategy
extends RefCounted
## MVP placement strategy (ARCH "Build", line 454): instantiates the block at
## the committed transform. Goes through the VoxelGridAdapter (never the raw
## VoxelGrid) so voxel coupling stays behind the IBlockGrid contract.
##
## commit() resolves the integer cell from the transform origin and calls
## adapter.set_block_at, which emits block_placed downstream.

var _grid: VoxelGridAdapter = null   # set via set_grid(); same-subsystem, so no voxel/ import here.


func set_grid(grid: VoxelGridAdapter) -> void:
	_grid = grid


## Place item_id at transform. Returns true on success, false if unwired or no
## item selected. Cost deduction is deferred (see TODO below).
func commit(transform: Transform3D, _rotation, item_id: String) -> bool:
	if _grid == null or item_id == "":
		return false
	var o := transform.origin
	var cell := Vector3i(int(floor(o.x)), int(floor(o.y)), int(floor(o.z)))
	# TODO(cost): once a materials store exists, check+deduct
	# BuildLibrary.get_def(item_id).get_cost() here before placing.
	_grid.set_block_at(cell, item_id)
	return true
