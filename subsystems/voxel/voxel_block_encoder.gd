class_name VoxelBlockEncoder
extends RefCounted
## Static utility class for encoding and decoding 16-bit packed voxel integers.
##
## Raw 16-bit voxel values pack both an 11-bit Block Type ID (0..2047) and a
## 5-bit 3D Orthogonal Rotation Index (0..23, matching Godot's Basis orthogonal index).

const ROTATION_BITS: int = 5
const ROTATION_MASK: int = 0x1F
const MAX_ORTHO_ROTATIONS: int = 24

static var _ORTHO_BASES: Array[Basis] = _build_ortho_bases()


static func encode(type_id: int, rot_index: int = 0) -> int:
	return (type_id << ROTATION_BITS) | (rot_index & ROTATION_MASK)


static func decode_type(raw_val: int) -> int:
	return raw_val >> ROTATION_BITS


static func decode_rotation(raw_val: int) -> int:
	return raw_val & ROTATION_MASK


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


static func _build_ortho_bases() -> Array[Basis]:
	var out: Array[Basis] = []
	var x_dirs: Array[Vector3] = [
		Vector3.RIGHT, Vector3.LEFT,
		Vector3.UP, Vector3.DOWN,
		Vector3.BACK, Vector3.FORWARD
	]
	for x_axis in x_dirs:
		var ref: Vector3 = Vector3.UP if abs(x_axis.y) < 0.9 else Vector3.RIGHT
		var y_base: Vector3 = x_axis.cross(ref).normalized()
		var z_base: Vector3 = x_axis.cross(y_base).normalized()
		
		for rot_step in range(4):
			var angle: float = float(rot_step) * (PI / 2.0)
			var rot_q := Quaternion(x_axis, angle)
			var y_axis: Vector3 = (rot_q * y_base).round()
			var z_axis: Vector3 = (rot_q * z_base).round()
			out.append(Basis(x_axis, y_axis, z_axis))
	return out
