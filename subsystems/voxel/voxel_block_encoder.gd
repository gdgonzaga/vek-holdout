class_name VoxelBlockEncoder
extends RefCounted
## Static rotation-state math for the 24 orthogonal orientations, in the SAME
## convention the blocky mesher uses for VoxelBlockyModelMesh.mesh_ortho_rotation_index:
## index 0 is identity and the four yaws are 0/22/10/16 (0/90/180/270 degrees
## about +Y). Rotatable blocks are rendered by baking per-orientation variant
## MODELS into the library (BlockLibrary + VoxelLibraryGenerator); this class
## is the orientation arithmetic that picks and previews them.
##
## The table was derived empirically from the installed addon — render an
## asymmetric probe mesh per index through VoxelMesherBlocky and recover the
## Basis (method preserved in tmp/convention_derivation.gd) — and is pinned by
## suite_voxel_block_encoder_test, so an addon update that changes the
## convention fails the suite instead of silently mis-rotating content.
##
## There is deliberately NO encode()/decode() here: packing type+rotation bits
## into stored voxel values produces voxels that persist but never render or
## collide (see BlockyGrid's storage convention and docs/VOXEL-TOOL-NOTES.md).

const MAX_ORTHO_ROTATIONS: int = 24

## The four yaw-only orientations in quarter-turn order (0, 90, 180, 270 deg).
const YAW_ORTHOS: Array[int] = [0, 22, 10, 16]

## Rotation about the cell center applied by the mesher for each index
## (columns are x/y/z axes of the resulting orientation).
static var _ORTHO_BASES: Array[Basis] = [
	Basis(Vector3.RIGHT, Vector3.UP, Vector3.BACK),      #  0 identity — yaw 0
	Basis(Vector3.DOWN, Vector3.RIGHT, Vector3.BACK),    #  1
	Basis(Vector3.LEFT, Vector3.DOWN, Vector3.BACK),     #  2
	Basis(Vector3.UP, Vector3.LEFT, Vector3.BACK),       #  3
	Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP),   #  4
	Basis(Vector3.BACK, Vector3.RIGHT, Vector3.UP),      #  5
	Basis(Vector3.LEFT, Vector3.BACK, Vector3.UP),       #  6
	Basis(Vector3.FORWARD, Vector3.LEFT, Vector3.UP),    #  7
	Basis(Vector3.RIGHT, Vector3.DOWN, Vector3.FORWARD), #  8
	Basis(Vector3.UP, Vector3.RIGHT, Vector3.FORWARD),   #  9
	Basis(Vector3.LEFT, Vector3.UP, Vector3.FORWARD),    # 10 yaw 180
	Basis(Vector3.DOWN, Vector3.LEFT, Vector3.FORWARD),  # 11
	Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN),    # 12
	Basis(Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN), # 13
	Basis(Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN),  # 14
	Basis(Vector3.BACK, Vector3.LEFT, Vector3.DOWN),     # 15
	Basis(Vector3.BACK, Vector3.UP, Vector3.LEFT),       # 16 yaw 270
	Basis(Vector3.DOWN, Vector3.BACK, Vector3.LEFT),     # 17
	Basis(Vector3.FORWARD, Vector3.DOWN, Vector3.LEFT),  # 18
	Basis(Vector3.UP, Vector3.FORWARD, Vector3.LEFT),    # 19
	Basis(Vector3.BACK, Vector3.DOWN, Vector3.RIGHT),    # 20
	Basis(Vector3.UP, Vector3.BACK, Vector3.RIGHT),      # 21
	Basis(Vector3.FORWARD, Vector3.UP, Vector3.RIGHT),   # 22 yaw 90
	Basis(Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT), # 23
]


static func basis_to_rot_index(basis: Basis) -> int:
	var b_norm: Basis = basis.orthonormalized()
	var max_dot: float = -999.0
	var best_idx: int = 0
	for i in range(_ORTHO_BASES.size()):
		var ob: Basis = _ORTHO_BASES[i]
		var dot: float = ob.x.dot(b_norm.x) + ob.y.dot(b_norm.y) + ob.z.dot(b_norm.z)
		if dot > max_dot:
			max_dot = dot
			best_idx = i
	return best_idx


static func rot_index_to_basis(rot_index: int) -> Basis:
	var idx := clampi(rot_index, 0, MAX_ORTHO_ROTATIONS - 1)
	return _ORTHO_BASES[idx]


static func rotate_around_axis(current_rot_index: int, axis: Vector3, step_angle_rad: float = PI / 2.0) -> int:
	var b := rot_index_to_basis(current_rot_index)
	var rot_q := Quaternion(axis.normalized(), step_angle_rad)
	var rot_b := Basis(rot_q)
	var rotated_b := (rot_b * b).orthonormalized()
	return basis_to_rot_index(rotated_b)
