## Subsystem: Colonists
## Modular animation controller component attached as a child node to Colonist (CharacterBody3D).
## Automatically binds skeleton, drives AnimationTree parameters, and handles facing orientation.
class_name ColonistAnimationController
extends Node

## Reference to AnimationTree (auto-resolves if empty)
@export var anim_tree: AnimationTree

## Reference to AnimationPlayer (auto-resolves if empty)
@export var anim_player: AnimationPlayer

## Reference to Visuals container node (auto-resolves if empty)
@export var visuals: Node3D

## Rotation lerp speed for facing direction
@export var rotation_speed: float = 15.0

## Cached parent Colonist reference
var _colonist: CharacterBody3D

## Cached StateMachinePlayback parameter interface
var _playback: AnimationNodeStateMachinePlayback

## Optional forced animation override (driven by BT tasks during work/interaction)
var _forced_anim: StringName = &""

## State tracking across frames for airborne jump transitions
var _was_on_floor: bool = true

## Substitutions for library keys the asset pack has not provided yet
const _ANIM_FALLBACKS: Dictionary = {
	&"Sprint": &"Walk",
}

## Missing-animation names already warned about (avoid per-frame warning spam)
var _warned_missing: Array[StringName] = []


func _ready() -> void:
	_colonist = get_parent() as CharacterBody3D
	
	if _colonist:
		# Ensure old prototype capsule mesh is hidden
		var capsule_mesh := _colonist.get_node_or_null("Mesh") as Node3D
		if capsule_mesh:
			capsule_mesh.visible = false
			
		if not anim_player:
			anim_player = _colonist.get_node_or_null("AnimationPlayer") as AnimationPlayer
			
		if not anim_tree:
			anim_tree = _colonist.get_node_or_null("AnimationTree") as AnimationTree
	
		if not visuals:
			visuals = _colonist.get_node_or_null("Visuals") as Node3D
			
		if visuals:
			visuals.visible = true
			
		# Enable AnimationTree and cache the locomotion StateMachine playback interface
		if anim_tree:
			anim_tree.active = true
			_playback = anim_tree.get("parameters/Locomotion/playback") as AnimationNodeStateMachinePlayback
			
		# 1. Skeleton Re-homing: Ensure the imported skeleton has the unique name 'GeneralSkeleton'.
		_setup_skeleton()


func _process(delta: float) -> void:
	if not _colonist:
		return
	
	# 1. Mesh Facing Direction: Lerp visual container towards horizontal movement vector.
	_update_mesh_rotation(delta)
	
	# 2. Animation Parameter Evaluation: Update blend position, jump states, and floor status.
	_update_animation_state()


## Triggers an upper-body one-shot action animation (e.g. "Digging", "Interact").
func trigger_action(action_name: StringName) -> void:
	if not anim_tree:
		return
		
	# Set transition target for the action selector
	anim_tree.set("parameters/ActionSelect/transition_request", String(action_name))
	
	# Fire the one-shot action overlay node
	anim_tree.set("parameters/ActionOneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Cancels any active one-shot action animation immediately.
func cancel_action() -> void:
	if anim_tree:
		anim_tree.set("parameters/ActionOneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)


## Sets a forced animation override (e.g. from BT tasks during work/interaction)
func play_animation_override(anim_name: StringName) -> void:
	_forced_anim = anim_name
	if anim_tree:
		trigger_action(anim_name)
	elif anim_player:
		_play_anim(anim_name)


## Clears any active animation override, returning to standard locomotion states
func clear_override() -> void:
	_forced_anim = &""
	if anim_tree:
		cancel_action()


# =============================================================================
# Auxiliary Functions (Step-down narrative order)
# =============================================================================

## Auxiliary: Rotates the visual mesh towards the movement direction of the parent Colonist
func _update_mesh_rotation(delta: float) -> void:
	if not visuals:
		return
	
	var horiz_vel := Vector3(_colonist.velocity.x, 0.0, _colonist.velocity.z)
	if horiz_vel.length() > 0.1:
		var dir := horiz_vel.normalized()
		# For models (+Z forward), atan2(dir.x, dir.z) faces the travel direction
		var target_angle := atan2(dir.x, dir.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, rotation_speed * delta)


## Auxiliary: Updates locomotion blend position and drives StateMachine jump transitions
func _update_animation_state() -> void:
	if not anim_tree:
		if anim_player:
			# Fallback evaluation for legacy direct AnimationPlayer setup
			_fallback_update_animation_player_state()
		return
		
	var is_on_floor := _colonist.is_on_floor()
	var horiz_vel := Vector3(_colonist.velocity.x, 0.0, _colonist.velocity.z)
	var speed := horiz_vel.length()
	var is_following_path: bool = not _colonist.has_arrived() if (_colonist and _colonist.has_method("has_arrived")) else false
	
	# 1. Blend Calculation: Calculate normalized blend position for Idle (0.0), Walk (0.5), Sprint (1.0).
	var blend_pos := _calculate_locomotion_blend(speed, is_following_path)
	anim_tree.set("parameters/Locomotion/Grounded/blend_position", blend_pos)
	
	if not _playback:
		return
		
	# Handle touchdown impact
	if is_on_floor and not _was_on_floor:
		_playback.travel("animations_JumpDown")
	elif not is_on_floor:
		# Trigger JumpUp ONCE on jump takeoff; allow StateMachine to auto-advance to JumpLoop when finished
		if _was_on_floor and _colonist.velocity.y > 0.0:
			_playback.travel("animations_JumpUp")
		elif _playback.get_current_node() not in [&"animations_JumpUp", &"animations_JumpLoop"]:
			_playback.travel("animations_JumpLoop")
	elif is_on_floor and _playback.get_current_node() not in [&"animations_JumpDown", &"animations_JumpUp"]:
		_playback.travel("Grounded")
		
	_was_on_floor = is_on_floor


## Auxiliary: Maps m/s horizontal movement speed or path-following status to normalized 0.0 to 1.0 blend position
func _calculate_locomotion_blend(speed_ms: float, is_following_path: bool) -> float:
	if speed_ms <= 0.1 and not is_following_path:
		return 0.0
	elif speed_ms <= 3.0:
		return remap(maxf(speed_ms, 0.1), 0.1, 3.0, 0.0, 0.5)
	else:
		return remap(clampf(speed_ms, 3.0, 8.0), 3.0, 8.0, 0.5, 1.0)


## Auxiliary: Fallback direct AnimationPlayer state update when AnimationTree is not present
func _fallback_update_animation_player_state() -> void:
	if not _forced_anim.is_empty():
		# Direct Animation Playback: Play requested override animation
		_play_anim(_forced_anim)
		return
		
	if not _colonist.is_on_floor():
		# Direct Animation Playback: Play jump animation
		_play_anim("Jump")
		return
	
	var speed := Vector3(_colonist.velocity.x, 0.0, _colonist.velocity.z).length()
	var is_following_path: bool = not _colonist.has_arrived() if (_colonist and _colonist.has_method("has_arrived")) else false
	
	if speed > 6.0:
		# Direct Animation Playback: Play sprint animation
		_play_anim("Sprint")
	elif speed > 0.1 or is_following_path:
		# Direct Animation Playback: Play walk animation
		_play_anim("Walk")
	else:
		# Direct Animation Playback: Play idle animation
		_play_anim("Idle")


## Auxiliary: Re-homes the imported model skeleton's unique name into this scene's scope
func _setup_skeleton() -> void:
	if not _colonist:
		return

	var skeleton := _colonist.find_child("*Skeleton*", true, false) as Skeleton3D
	if skeleton:
		skeleton.owner = _colonist
		if anim_player:
			anim_player.clear_caches()


## Auxiliary: Animations live in scene AnimationPlayer's "animations" library, so playback names resolve as "animations/Idle"
func _play_anim(anim_name: StringName) -> void:
	var target_anim := StringName("animations/" + anim_name)
	if not anim_player.has_animation(target_anim):
		# Fallback Resolution: Resolve substitute animation key when target missing
		target_anim = _fallback_anim(anim_name)
		if target_anim == &"":
			return

	if anim_player.current_animation != target_anim:
		anim_player.play(target_anim)


## Auxiliary: Resolves substitute animation when library lacks requested key
func _fallback_anim(anim_name: StringName) -> StringName:
	var fallback: StringName = _ANIM_FALLBACKS.get(anim_name, &"Idle")
	var fallback_anim := StringName("animations/" + fallback)
	var has_fallback := anim_player.has_animation(fallback_anim)
	if anim_name not in _warned_missing:
		_warned_missing.append(anim_name)
		if has_fallback:
			push_warning("ColonistAnimationController: '" + anim_name + "' missing from library, falling back to '" + fallback + "'.")
		else:
			push_warning("ColonistAnimationController: '" + anim_name + "' missing from library.")
	return fallback_anim if has_fallback else &""
