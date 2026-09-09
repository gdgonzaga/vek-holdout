## Subsystem: Player
## Modular animation controller component attached as a child node to Player (CharacterBody3D).
## Automatically binds skeleton, drives AnimationTree parameters, and handles facing orientation.
class_name PlayerAnimationController
extends Node

## Reference to AnimationTree (auto-resolves if empty)
@export var anim_tree: AnimationTree

## Reference to AnimationPlayer (auto-resolves if empty)
@export var anim_player: AnimationPlayer

## Reference to Visuals container node (auto-resolves if empty)
@export var visuals: Node3D

## Rotation lerp speed for facing direction
@export var rotation_speed: float = 15.0

## Cached parent CharacterBody3D reference
var _player: CharacterBody3D

## Cached StateMachinePlayback parameter interface
var _playback: AnimationNodeStateMachinePlayback

## State tracking across frames for airborne jump transitions
var _was_on_floor: bool = true


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	
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
			
		# 1. Skeleton Re-homing: Ensure the imported skeleton has the unique name 'GeneralSkeleton'.
		_setup_skeleton()


func _process(delta: float) -> void:
	if not _player or not anim_tree:
		return
	
	# 1. Mesh Facing Direction: Lerp visual container towards horizontal movement vector.
	_update_mesh_rotation(delta)
	
	# 2. Animation Parameter Evaluation: Update blend position, jump states, and floor status.
	_update_animation_state()


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

## Auxiliary: Rotates the visual mesh towards the movement direction of the parent CharacterBody3D
func _update_mesh_rotation(delta: float) -> void:
	if not visuals:
		return
	
	var horiz_vel := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	if horiz_vel.length() > 0.1:
		var dir := horiz_vel.normalized()
		# For models (+Z forward), atan2(dir.x, dir.z) faces the travel direction
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


## Auxiliary: Re-homes the imported model skeleton's unique name into this scene's scope
func _setup_skeleton() -> void:
	if not _player:
		return

	var skeleton := _player.find_child("*Skeleton*", true, false) as Skeleton3D
	if skeleton:
		skeleton.owner = _player
		if anim_player:
			anim_player.clear_caches()
