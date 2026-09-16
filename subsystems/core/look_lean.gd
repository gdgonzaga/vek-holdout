class_name LookLean
extends Node

## Torso/head look lean shared by Player and Colonist (ARCH "Subsystem: Player"
## flow "Look: Facing and Lean", "Subsystem: Colonists" flow "Look at Work and
## Combat Targets").
##
## Bends the humanoid Chest and Head bones by a look pitch so looking up or down
## reads on the avatar without tipping the whole body over. The owner (an
## animation controller) decides where the pitch comes from and calls apply()
## every frame AFTER its AnimationTree has written that frame's pose: the lean is
## composed onto that pose, and because the tree re-poses both bones every frame
## it never accumulates. Holds no _process of its own so that ordering stays with
## the owner.

## Humanoid-profile bones that carry the lean (names from the model's BoneMap
## retarget, the same set the ActionOneshot upper-body filter uses).
const CHEST_BONE := &"Chest"
const HEAD_BONE := &"Head"

## Bend the torso/head with the look pitch
@export var enabled: bool = true

## Furthest the upper body leans back when looking up (Chest + Head combined)
@export_range(0.0, 90.0, 0.5, "suffix:°") var max_up_deg: float = 40.0

## Furthest the upper body leans forward when looking down (Chest + Head combined)
@export_range(0.0, 90.0, 0.5, "suffix:°") var max_down_deg: float = 40.0

## Share of the lean bent into the Chest bone; the Head takes the rest
@export_range(0.0, 1.0, 0.05) var chest_share: float = 0.6

## How quickly the lean catches up to its target pitch (higher is snappier)
@export_range(0.0, 60.0, 0.5) var smoothing: float = 12.0

var _skeleton: Skeleton3D
var _chest_bone_idx: int = -1
var _head_bone_idx: int = -1

## Pitch eased toward its clamped target, carried frame to frame
var _smoothed_pitch: float = 0.0


# =================
# Primary Functions
# =================

## Resolves the lean bones on the given skeleton, warning if the rig lacks them.
func bind(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_chest_bone_idx = skeleton.find_bone(CHEST_BONE) if skeleton != null else -1
	_head_bone_idx = skeleton.find_bone(HEAD_BONE) if skeleton != null else -1
	if not is_bound():
		push_warning("LookLean: skeleton lacks '%s'/'%s' bones; look lean disabled." % [CHEST_BONE, HEAD_BONE])


## Whether both lean bones were resolved by bind().
func is_bound() -> bool:
	return _chest_bone_idx >= 0 and _head_bone_idx >= 0


## Eases toward target_pitch (radians, look-up positive) and bends Chest/Head by
## it. Call once per frame, after the AnimationTree has posed the skeleton.
func apply(target_pitch: float, delta: float) -> void:
	if not enabled or not is_bound():
		return

	# 1. Target Resolution: Clamp the pitch to the separate look-up / look-down limits.
	var clamped := clamp_pitch(target_pitch)
	_smoothed_pitch = lerpf(_smoothed_pitch, clamped, 1.0 - exp(-smoothing * delta))
	# This rig bends forward (chin down) on positive local-X rotation, the
	# opposite of the look-up-positive pitch, so the lean is negated.
	var lean := -_smoothed_pitch

	# 2. Torso Lean: Bend the Chest by its share of the lean.
	_lean_bone(_chest_bone_idx, lean * chest_share)

	# 3. Head Tilt: Bend the Head by the remaining share.
	_lean_bone(_head_bone_idx, lean * (1.0 - chest_share))


## Clamps a pitch (radians, look-up positive) to the lean limits.
func clamp_pitch(pitch: float) -> float:
	return clampf(pitch, -deg_to_rad(max_down_deg), deg_to_rad(max_up_deg))


# ===================
# Auxiliary Functions
# ===================

## Auxiliary: Composes an extra local-X rotation onto a bone's current pose
func _lean_bone(bone_idx: int, angle: float) -> void:
	var pose := _skeleton.get_bone_pose_rotation(bone_idx)
	_skeleton.set_bone_pose_rotation(bone_idx, pose * Quaternion(Vector3.RIGHT, angle))
