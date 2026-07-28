class_name InstantPlacementStrategy
extends RefCounted
## MVP placement strategy (ARCH "Build", line 454): instantiates the block at
## the committed transform. Delegates the actual set_block_at to a VoxelGrid.
##
## STUB: commit() does not place anything yet — no block placement this pass.
## Exists so BuildController.strategy is real and the place-block flow is fill-in
## (wire a VoxelGrid reference here and call set_block_at on commit).

var _grid: Variant = null   # VoxelGrid, set via set_grid(); typed loosely to avoid a hard voxel/ dependency here.


func set_grid(grid) -> void:
	_grid = grid


## Place item_id at transform. STUB — warns and does nothing.
func commit(_transform: Transform3D, _rotation, _item_id: String) -> bool:
	push_warning("InstantPlacementStrategy.commit: not implemented (stub)")
	return false
