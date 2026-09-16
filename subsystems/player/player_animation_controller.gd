## Subsystem: Player
## Modular animation controller component attached as a child node to Player (CharacterBody3D).
## Automatically binds skeleton, drives AnimationTree parameters, and handles facing orientation and the look lean.
class_name PlayerAnimationController
extends Node

## Upper-body bones that carry the look lean. Humanoid-profile names from the
## model's BoneMap retarget, the same set the ActionOneshot filter in player.tscn uses.
const LEAN_CHEST_BONE := &"Chest"
const LEAN_HEAD_BONE := &"Head"

## Reference to AnimationTree (auto-resolves if empty)
@export var anim_tree: AnimationTree

## Reference to AnimationPlayer (auto-resolves if empty)
@export var anim_player: AnimationPlayer

## Reference to Visuals container node (auto-resolves if empty)
@export var visuals: Node3D

## Rotation lerp speed for facing direction
@export var rotation_speed: float = 15.0

@export_group("Look Lean", "look_lean_")

## Bend the torso/head with camera pitch so looking up/down reads on the avatar
@export var look_lean_enabled: bool = true

## Furthest the upper body leans back when looking up (Chest + Head combined)
@export_range(0.0, 90.0, 0.5, "suffix:°") var look_lean_max_up_deg: float = 40.0

## Furthest the upper body leans forward when looking down (Chest + Head combined)
@export_range(0.0, 90.0, 0.5, "suffix:°") var look_lean_max_down_deg: float = 40.0

## Share of the lean bent into the Chest bone; the Head takes the rest
@export_range(0.0, 1.0, 0.05) var look_lean_chest_share: float = 0.6

## How quickly the lean catches up to the camera (higher is snappier)
@export_range(0.0, 60.0, 0.5) var look_lean_smoothing: float = 12.0

## Cached parent Player reference
var _player: Player

## Cached StateMachinePlayback parameter interface
var _playback: AnimationNodeStateMachinePlayback

## Skeleton and bone indices the look lean writes to (-1 until resolved)
var _skeleton: Skeleton3D
var _chest_bone_idx: int = -1
var _head_bone_idx: int = -1

## Camera pitch eased toward its clamped lean target, carried frame to frame
var _smoothed_pitch: float = 0.0

## State tracking across frames for airborne jump transitions
var _was_on_floor: bool = true


func _ready() -> void:
	_player = get_parent() as Player
	
	if _player:
		# Hide old prototype capsule mesh if present
		var capsule_3d := _player.get_node_or_null("MeshInstance3D") as Node3D
		if capsule_3d:
			capsule_3d.visible = false
			
		if not anim_player:
			anim_player = _player.get_node_or_null("AnimationPlayer") as AnimationPlayer
			
		if not anim_tree:
			anim_tree = _player.get_node_or_null("AnimationTree") as AnimationTree
	
		if not visuals:
			visuals = _player.get_node_or_null("Visuals") as Node3D
			
		if visuals:
			visuals.visible = true
			
		# Enable AnimationTree and cache the locomotion StateMachine playback interface
		if anim_tree:
			anim_tree.active = true
			_playback = anim_tree.get("parameters/Locomotion/playback") as AnimationNodeStateMachinePlayback
			# The look lean composes onto this tree's output, so this node must
			# process after the tree whatever order the scene lists them in.
			process_priority = anim_tree.process_priority + 1
			
		# 1. Skeleton Re-homing: Ensure the imported skeleton has the unique name 'GeneralSkeleton'.
		_setup_skeleton()


func _process(delta: float) -> void:
	if not _player or not anim_tree:
		return
	
	# 1. Mesh Facing Direction: Lerp visual container towards the camera's look direction.
	_update_mesh_rotation(delta)
	
	# 2. Animation Parameter Evaluation: Update blend position, jump states, and floor status.
	_update_animation_state()

	# 3. Look Lean: Bend the torso/head with camera pitch, on top of the pose the AnimationTree just produced.
	_apply_look_lean(delta)


## Triggers a one-shot tool or interaction animation (e.g. "Digging", "Interact", "AttackOverhead").
## Overlays the specified action over upper-body bones without interrupting lower-body movement.
func trigger_action(action_name: StringName) -> void:
	if not anim_tree:
		return

	# 1. Action Resolution: Resolve generic action or weapon animation names to valid transition keys.
	var resolved_action: StringName = _resolve_action_animation_name(action_name)

	# Set transition target for the action selector
	anim_tree.set("parameters/ActionSelect/transition_request", String(resolved_action))

	# Fire the one-shot action overlay node
	anim_tree.set("parameters/ActionOneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Cancels any active one-shot action animation immediately.
func cancel_action() -> void:
	if anim_tree:
		anim_tree.set("parameters/ActionOneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


## Auxiliary: Maps incoming generic action or weapon animation names to valid ActionSelect transition names
func _resolve_action_animation_name(action_name: StringName) -> StringName:
	var name_str := String(action_name).to_lower()
	if name_str in ["attackoverhead", "swing", "attack", "strike", "melee"]:
		return &"AttackOverhead"
	if name_str in ["interact", "fire", "shoot", "use"]:
		return &"Interact"
	if name_str in ["digging", "dig"]:
		return &"Digging"
	return action_name


# =============================================================================
# Auxiliary Functions (Step-down narrative order)
# =============================================================================

## Auxiliary: Rotates the visual mesh towards the camera's look direction, so the
## avatar always faces where the player is looking rather than where it's walking
## (holding back/strafe moves the body without spinning it to face travel direction).
func _update_mesh_rotation(delta: float) -> void:
	if not visuals:
		return
	
	var dir: Vector3 = _player.get_look_direction()
	if dir.length_squared() > 0.0001:
		# For models (+Z forward), atan2(dir.x, dir.z) faces the look direction
		var target_angle := atan2(dir.x, dir.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, rotation_speed * delta)


## Auxiliary: Updates locomotion blend position and drives StateMachine jump transitions
func _update_animation_state() -> void:
	var is_on_floor := _player.is_on_floor()
	var horiz_vel := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	var speed := horiz_vel.length()
	
	# 1. Blend Calculation: Calculate normalized blend position for Idle (0.0), Walk (0.5), Sprint (1.0).
	var blend_pos := _calculate_locomotion_blend(speed)
	anim_tree.set("parameters/Locomotion/Grounded/blend_position", blend_pos)
	
	if not _playback:
		return
		
	# Handle touchdown impact
	if is_on_floor and not _was_on_floor:
		_playback.travel("animations_JumpDown")
	elif not is_on_floor:
		# Trigger JumpUp ONCE on jump takeoff; allow StateMachine to auto-advance to JumpLoop when finished
		if _was_on_floor and _player.velocity.y > 0.0:
			_playback.travel("animations_JumpUp")
		elif _playback.get_current_node() not in [&"animations_JumpUp", &"animations_JumpLoop"]:
			_playback.travel("animations_JumpLoop")
	elif is_on_floor and _playback.get_current_node() not in [&"animations_JumpDown", &"animations_JumpUp"]:
		_playback.travel("Grounded")
		
	_was_on_floor = is_on_floor


## Auxiliary: Maps m/s horizontal movement speed to normalized 0.0 to 1.0 blend position
func _calculate_locomotion_blend(speed_ms: float) -> float:
	# Map 0.0 to 8.0 m/s speed into 0.0 (Idle) -> 0.5 (Walk) -> 1.0 (Sprint)
	if speed_ms <= 0.1:
		return 0.0
	elif speed_ms <= 3.0:
		return remap(speed_ms, 0.1, 3.0, 0.0, 0.5)
	else:
		return remap(clampf(speed_ms, 3.0, 8.0), 3.0, 8.0, 0.5, 1.0)


## Auxiliary: Bends the Chest/Head with camera pitch, composed onto the pose the
## AnimationTree wrote this frame. The tree re-poses both bones every frame, so
## the lean never accumulates; bending bones rather than the whole body keeps the feet planted.
func _apply_look_lean(delta: float) -> void:
	if not look_lean_enabled or _chest_bone_idx < 0 or _head_bone_idx < 0:
		return

	# 1. Target Resolution: Clamp camera pitch to the separate look-up / look-down lean limits.
	var target_pitch := _clamp_look_pitch(_player.get_look_pitch())
	_smoothed_pitch = lerpf(_smoothed_pitch, target_pitch, 1.0 - exp(-look_lean_smoothing * delta))
	# This rig bends forward (chin down) on positive local-X rotation, the
	# opposite of CameraRig's look-up-positive pitch, so the lean is negated.
	var lean := -_smoothed_pitch

	# 2. Torso Lean: Bend the Chest by its share of the lean.
	_lean_bone(_chest_bone_idx, lean * look_lean_chest_share)

	# 3. Head Tilt: Bend the Head by the remaining share.
	_lean_bone(_head_bone_idx, lean * (1.0 - look_lean_chest_share))


## Auxiliary: Clamps a camera pitch (radians, look-up positive) to the lean limits
func _clamp_look_pitch(pitch: float) -> float:
	return clampf(pitch, -deg_to_rad(look_lean_max_down_deg), deg_to_rad(look_lean_max_up_deg))


## Auxiliary: Composes an extra local-X rotation onto a bone's current pose
func _lean_bone(bone_idx: int, angle: float) -> void:
	var pose := _skeleton.get_bone_pose_rotation(bone_idx)
	_skeleton.set_bone_pose_rotation(bone_idx, pose * Quaternion(Vector3.RIGHT, angle))


## Auxiliary: Re-homes the imported model skeleton's unique name into this scene's scope
func _setup_skeleton() -> void:
	if not _player:
		return

	var skeleton := _player.find_child("*Skeleton*", true, false) as Skeleton3D
	if skeleton:
		skeleton.owner = _player
		if anim_player:
			anim_player.clear_caches()

		# 1. Lean Bone Resolution: Cache the bones the look lean writes to every frame.
		_cache_lean_bones(skeleton)


## Auxiliary: Resolves the look-lean bone indices, warning if the rig lacks them
func _cache_lean_bones(skeleton: Skeleton3D) -> void:
	_skeleton = skeleton
	_chest_bone_idx = skeleton.find_bone(LEAN_CHEST_BONE)
	_head_bone_idx = skeleton.find_bone(LEAN_HEAD_BONE)
	if _chest_bone_idx < 0 or _head_bone_idx < 0:
		push_warning("PlayerAnimationController: skeleton lacks '%s'/'%s' bones; look lean disabled." % [LEAN_CHEST_BONE, LEAN_HEAD_BONE])
