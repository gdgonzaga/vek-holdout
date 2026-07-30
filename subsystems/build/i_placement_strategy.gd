class_name IPlacementStrategy
## Voxel-agnostic placement contract (ARCH "Build", line 453).
## BuildController delegates commit() to an IPlacementStrategy; it does not know
## whether placement is instant (MVP) or blueprint-then-build (post-MVP).
##
## Godot has no formal interfaces; this is a documentation-only contract (same
## pattern as build/i_block_grid.gd). Implementations provide commit() with the
## matching signature and duck-type against this spec.


## Place item_id at the given transform with the given rotation. Return true on
## success. `rotation` is the RotationState (or its serialized form).
func commit(_transform: Transform3D, _rotation, _item_id: String) -> bool:
	return false
