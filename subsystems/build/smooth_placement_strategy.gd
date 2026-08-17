class_name SmoothPlacementStrategy
extends RefCounted
## Smooth-material placement strategy (docs/TODO.md Phase 5): materializes a
## terrain material as an add-sphere (SmoothGrid.add_material) at the committed
## transform origin. The InstantPlacementStrategy counterpart for natural
## materials — instant and HP-free by design: blueprint/labor flow is for built
## structures, not ground shaping. Duck-typed against i_placement_strategy.gd
## like the other strategies (rotation is ignored — spheres have no yaw).
##
## The build ray must have hit the natural surface first (BuildController's
## smooth-hit filter derives the center at hit + normal * radius/2 and runs the
## overlap validity before committing) — smooth materials build ON natural
## ground (D2), never through furniture/blocks/blueprints or over a character.

var _smooth: SmoothGrid = null


func set_smooth_grid(smooth: SmoothGrid) -> void:
	_smooth = smooth


## Place material_id as a sphere at transform.origin. Returns true on success,
## false if unwired/unknown. Radius comes from the material def (data-owned).
func commit(transform: Transform3D, _rotation, item_id: String) -> bool:
	if _smooth == null:
		return false
	var mat := BuildLibrary.get_terrain_material(item_id)
	if mat == null:
		return false
	_smooth.add_material(transform.origin, item_id, mat.place_radius)
	return true
