## Subsystem: Colonists
## Modular animation controller component attached as a child node to Colonist (CharacterBody3D).
## Automatically binds skeleton, drives AnimationTree parameters, and handles facing orientation
## and looking at the current work or combat target.
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

## Look lean component fed the pitch toward the look target each frame; its knobs live on that node (auto-resolves if empty)
@export var look_lean: LookLean

## Cached parent Colonist reference
var _colonist: Colonist

## Node being looked at (null when looking at a fixed point or at nothing)
var _look_target: Node3D = null

## _look_target's center mass in its own local space, resolved once when set so a moving target stays tracked
var _look_target_local_center: Vector3 = Vector3.ZERO

## Fixed world point being looked at, valid while _has_look_point is true
var _look_point: Vector3 = Vector3.ZERO
var _has_look_point: bool = false

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
	_colonist = get_parent() as Colonist
	
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

		if not look_lean:
			look_lean = _colonist.get_node_or_null("LookLean") as LookLean
			
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
	if not _colonist:
		return
	
	# 1. Look Point Resolution: Where the colonist looks this frame (null when not working or fighting).
	var look_point: Variant = _resolve_look_point()

	# 2. Mesh Facing Direction: Lerp visual container towards the look point, else the movement vector.
	_update_mesh_rotation(delta, look_point)
	
	# 3. Animation Parameter Evaluation: Update blend position, jump states, and floor status.
	_update_animation_state()

	# 4. Look Lean: Bend the torso/head toward the look point (level without one), on top of the tree's pose.
	if anim_tree and look_lean:
		look_lean.apply(_look_pitch_toward(look_point), delta)


## Triggers an upper-body one-shot action animation (e.g. "Digging", "Interact", "AttackOverhead").
func trigger_action(action_name: StringName) -> void:
	if not anim_tree:
		return
	if action_name == &"Idle" or action_name == &"idle" or action_name.is_empty():
		cancel_action()
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


## Sets a forced animation override (e.g. from BT tasks during work/interaction)
func play_animation_override(anim_name: StringName) -> void:
	_forced_anim = anim_name
	if anim_name == &"Idle" or anim_name == &"idle" or anim_name.is_empty():
		cancel_action()
		return
	if anim_tree:
		trigger_action(anim_name)
	elif anim_player:
		_play_anim(anim_name)


## Clears any active animation override, returning to standard locomotion states
func clear_override() -> void:
	_forced_anim = &""
	if anim_tree:
		cancel_action()


## Rotates the visual container towards target_pos (snapped if delta <= 0.0, lerped if delta > 0.0).
func face_target(target_pos: Vector3, delta: float = -1.0) -> void:
	if not visuals or not _colonist:
		return
	var diff := target_pos - _colonist.global_position
	var horiz := Vector3(diff.x, 0.0, diff.z)
	if horiz.length_squared() < 0.001:
		return
	var dir := horiz.normalized()
	# For models (+Z forward), atan2(dir.x, dir.z) faces the target direction
	var target_angle := atan2(dir.x, dir.z)
	if delta > 0.0:
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, rotation_speed * delta)
	else:
		visuals.rotation.y = target_angle


## Keeps the colonist facing and leaning toward target's center mass until cleared.
## Re-setting the current target is a no-op, so callers may set it every tick.
func set_look_target(target: Node3D) -> void:
	if target == null:
		clear_look_target()
		return
	if _look_target == target:
		return
	_has_look_point = false
	_look_target = target
	# 1. Center Resolution: Cache the center mass in target-local space so a moving target stays tracked.
	_look_target_local_center = target.global_transform.affine_inverse() * VisualBounds.world_center(target)


## Keeps the colonist facing and leaning toward a fixed world point until cleared.
func set_look_point(point: Vector3) -> void:
	_look_target = null
	_look_point = point
	_has_look_point = true


## Returns the colonist to movement facing and eases the lean back to level.
func clear_look_target() -> void:
	_look_target = null
	_has_look_point = false


## Auxiliary: Maps incoming generic action or weapon animation names to valid ActionSelect transition names
func _resolve_action_animation_name(action_name: StringName) -> StringName:
	var name_str := String(action_name).to_lower()
	if name_str in ["attackoverhead", "swing", "attack", "strike", "melee"]:
		return &"AttackOverhead"
	if name_str in ["interact", "fire", "shoot", "use"]:
		return &"Interact"
	if name_str in ["digging", "dig"]:
		return &"Digging"
	return &"Interact"



# =============================================================================
# Auxiliary Functions (Step-down narrative order)
# =============================================================================

## Auxiliary: Current look point, or null with none; a freed or removed target clears itself
func _resolve_look_point() -> Variant:
	if _has_look_point:
		return _look_point
	if not is_instance_valid(_look_target) or not _look_target.is_inside_tree():
		_look_target = null
		return null
	return _look_target.global_transform * _look_target_local_center


## Auxiliary: Rotates the visual mesh towards the look point when there is one, else the movement direction
func _update_mesh_rotation(delta: float, look_point: Variant) -> void:
	if not visuals:
		return
	if look_point is Vector3:
		face_target(look_point, delta)
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


## Auxiliary: Pitch (radians, look-up positive) from the colonist's aim origin to the look point; level with none
func _look_pitch_toward(look_point: Variant) -> float:
	if not (look_point is Vector3):
		return 0.0
	var offset: Vector3 = look_point - _colonist.get_aim_origin()
	return atan2(offset.y, Vector2(offset.x, offset.z).length())


## Auxiliary: Re-homes the imported model skeleton's unique name into this scene's scope
func _setup_skeleton() -> void:
	if not _colonist:
		return

	var skeleton := _colonist.find_child("*Skeleton*", true, false) as Skeleton3D
	if skeleton:
		skeleton.owner = _colonist
		if anim_player:
			anim_player.clear_caches()

		# 1. Lean Binding: Point the look lean at this skeleton's Chest/Head bones.
		if look_lean:
			look_lean.bind(skeleton)


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
