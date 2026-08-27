## Subsystem: Colonists
## Modular animation controller component attached as a child node to Colonist (CharacterBody3D).
## Automatically binds female mesh model, drives AnimationPlayer, and handles facing orientation.
class_name ColonistAnimationController
extends Node

## Reference to AnimationPlayer (auto-resolves if empty)
@export var anim_player: AnimationPlayer

## Reference to Visuals container node (auto-resolves if empty)
@export var visuals: Node3D

## Rotation lerp speed for facing direction
@export var rotation_speed: float = 15.0

## Cached parent Colonist reference
var _colonist: CharacterBody3D

## Optional forced animation override (driven by BT tasks during work/interaction)
var _forced_anim: StringName = &""

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
	
		if not visuals:
			visuals = _colonist.get_node_or_null("Visuals") as Node3D
			
		if visuals:
			visuals.visible = true
			
		_setup_skeleton()


## Re-homes the imported model skeleton's unique name into this scene's scope.
## BoneMap-retargeted models name their skeleton GeneralSkeleton and register the
## unique name only inside the model's own scene; AnimationLibrary tracks use
## "%GeneralSkeleton:<bone>" paths that resolve once owner points at the body root.
func _setup_skeleton() -> void:
	if not _colonist:
		return

	var skeleton := _colonist.find_child("*Skeleton*", true, false) as Skeleton3D
	if skeleton:
		skeleton.owner = _colonist
		if anim_player:
			anim_player.clear_caches()


func _process(delta: float) -> void:
	if not _colonist:
		return
	
	_update_mesh_rotation(delta)
	_update_animation_state()


## Rotates the visual mesh towards the movement direction of the parent Colonist
func _update_mesh_rotation(delta: float) -> void:
	if not visuals:
		return
	
	var horiz_vel := Vector3(_colonist.velocity.x, 0.0, _colonist.velocity.z)
	if horiz_vel.length() > 0.1:
		var dir := horiz_vel.normalized()
		# For Quaternius models (+Z forward), atan2(dir.x, dir.z) faces the travel direction
		var target_angle := atan2(dir.x, dir.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, rotation_speed * delta)


## Sets a forced animation override (e.g. from BT tasks during work/interaction)
func play_animation_override(anim_name: StringName) -> void:
	_forced_anim = anim_name
	_play_anim(anim_name)


## Clears any active animation override, returning to standard locomotion states
func clear_override() -> void:
	_forced_anim = &""


## Selects and plays animation based on override, parent velocity and floor status
func _update_animation_state() -> void:
	if not anim_player:
		return
	
	if not _forced_anim.is_empty():
		_play_anim(_forced_anim)
		return
		
	# Airborne / Jump state
	if not _colonist.is_on_floor():
		_play_anim("Jump")
		return
	
	# Horizontal locomotion
	var speed := Vector3(_colonist.velocity.x, 0.0, _colonist.velocity.z).length()
	var is_following_path: bool = not _colonist.has_arrived() if (_colonist and _colonist.has_method("has_arrived")) else false
	
	if speed > 6.0:
		_play_anim("Sprint")
	elif speed > 0.1 or is_following_path:
		_play_anim("Walk")
	else:
		_play_anim("Idle")


## Animations live in the scene AnimationPlayer's "animations" library, so playback
## names are library-qualified: "Idle" resolves as "animations/Idle".
func _play_anim(anim_name: StringName) -> void:
	var target_anim := StringName("animations/" + anim_name)
	if not anim_player.has_animation(target_anim):
		target_anim = _fallback_anim(anim_name)
		if target_anim == &"":
			return

	if anim_player.current_animation != target_anim:
		anim_player.play(target_anim)


## Resolves a substitute when the library lacks a key (asset not provided yet).
## Falls back per _ANIM_FALLBACKS, then to Idle; warns once per missing name.
func _fallback_anim(anim_name: StringName) -> StringName:
	var fallback: StringName = _ANIM_FALLBACKS.get(anim_name, &"Idle")
	var fallback_anim := StringName("mixamo/" + fallback)
	var has_fallback := anim_player.has_animation(fallback_anim)
	if anim_name not in _warned_missing:
		_warned_missing.append(anim_name)
		if has_fallback:
			push_warning("ColonistAnimationController: '" + anim_name + "' missing from 'mixamo' library, falling back to '" + fallback + "'.")
		else:
			push_warning("ColonistAnimationController: '" + anim_name + "' missing from 'mixamo' library.")
	return fallback_anim if has_fallback else &""
