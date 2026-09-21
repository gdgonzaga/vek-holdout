extends BuildableDef
class_name BlockDef
## Voxel-grid buildable (GDD §7.2). A BuildableDef exposed to the blocky voxel
## world — what BlockLibrary feeds into VoxelBlockyLibrary and BlockyGrid places.
## Schema: docs/ARCHITECTURE.md "data/blocks/<type>.tres".
##
## Inherits id/display_name/hp/mesh/material_cost/unlocked_by_default from
## BuildableDef. Adds rotational symmetry options. Natural ground is NOT a
## block: it lives in the smooth terrain vocabulary (TerrainMaterialDef) —
## this schema is built structures only (the D1 def-level mirror).
##
## No library-index fields here on purpose: BlockLibrary owns the id<->index
## mapping, and stored voxel values are its plain indices (never def data).

enum RotationMode {
	NONE = 1,       # Standard cubic block (1 model ID)
	YAW_ONLY = 4,   # 4 horizontal orientations around Y axis (e.g. stairs, logs)
	FULL_3D = 24    # All 24 orthogonal orientations (e.g. wedges, corner slopes)
}

## Orthogonal rotation indices for the 4 horizontal yaw states, in quarter-turn
## order (0, 90, 180, 270 degrees around +Y). Values follow the mesher's
## mesh_ortho_rotation_index convention (see VoxelBlockEncoder's class doc);
## sanitize_rotation also accepts a quarter-turn count 0..3 by indexing here.
const YAW_INDICES: Array[int] = [0, 22, 10, 16]

## Rotational symmetry mode. Non-NONE modes make BlockLibrary bake one variant
## model per orientation at runtime (variants share this def's mesh) — authors
## never hand-make rotated meshes.
@export var rotation_mode: RotationMode = RotationMode.NONE

## Fluid flag: marks non-solid fluids like water or lava.
@export var is_fluid: bool = false

## Locomotion multiplier for a body whose lower torso is inside this block. Only read for fluids
## (solids and air never slow anyone); 1.0 = no drag. BlockLibrary.get_wading_speed_mult applies the
## fluid gate, so consumers ask the library instead of reading this directly.
@export_range(0.0, 1.0) var wading_speed_mult: float = 1.0

## Collision generation: set false for non-solid blocks (water, tall grass).
@export var collision_enabled: bool = true

## Transparency index for VoxelMesherBlocky (0 = opaque, > 0 = transparent).
## Opaque blocks adjacent to transparent blocks do not cull their faces.
@export var transparency_index: int = 0

## When true, touching blocks of the same model cull their shared internal faces.
@export var culls_neighbors_of_same_type: bool = false

## Optional custom Material (e.g. ShaderMaterial for water) overriding the default standard material.
@export var custom_material: Material = null

## Explicit fixed base library index. When > 0, BlockLibrary assigns this exact index
## rather than an auto-assigned sequential index, guaranteeing save compatibility across game updates.
@export var fixed_index: int = -1


func is_rotatable() -> bool:
	return rotation_mode != RotationMode.NONE


func sanitize_rotation(desired_rot_index: int) -> int:
	match rotation_mode:
		RotationMode.NONE:
			return 0
		RotationMode.FULL_3D:
			return clampi(desired_rot_index, 0, 23)
		RotationMode.YAW_ONLY:
			if desired_rot_index in YAW_INDICES:
				return desired_rot_index
			if desired_rot_index >= 0 and desired_rot_index < YAW_INDICES.size():
				return YAW_INDICES[desired_rot_index]
			var clamped_idx := clampi(desired_rot_index, 0, 23)
			var b := VoxelBlockEncoder.rot_index_to_basis(clamped_idx)
			var best_idx: int = YAW_INDICES[0]
			var max_dot: float = -999.0
			for idx in YAW_INDICES:
				var yb := VoxelBlockEncoder.rot_index_to_basis(idx)
				var dot: float = b.x.dot(yb.x) + b.y.dot(yb.y) + b.z.dot(yb.z)
				if dot > max_dot:
					max_dot = dot
					best_idx = idx
			return best_idx
		_:
			return 0
