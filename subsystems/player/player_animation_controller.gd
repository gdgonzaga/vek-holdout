## Subsystem: Player
## Modular animation controller component attached as a child node to Player (CharacterBody3D).
## Automatically binds skeleton, drives AnimationPlayer, and handles facing orientation.
class_name PlayerAnimationController
extends Node

## Reference to AnimationPlayer (auto-resolves if empty)
@export var anim_player: AnimationPlayer

## Reference to Visuals container node (auto-resolves if empty)
@export var visuals: Node3D

## Rotation lerp speed for facing direction
@export var rotation_speed: float = 15.0

## Cached parent CharacterBody3D reference
var _player: CharacterBody3D


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	
	if _player:
		# Ensure old prototype capsule mesh is hidden
		var capsule_3d := _player.get_node_or_null("MeshInstance3D") as Node3D
		if capsule_3d:
			capsule_3d.visible = false
			
		if not anim_player:
			anim_player = _player.get_node_or_null("AnimationPlayer") as AnimationPlayer
	
		if not visuals:
			visuals = _player.get_node_or_null("Visuals") as Node3D
			
		if visuals:
			visuals.visible = true
			
		# Ensure the imported skeleton has the unique name 'GeneralSkeleton'
		# so Animation tracks with path '%GeneralSkeleton:...' bind to it immediately.
		_setup_skeleton()


const MALE_MESH_PATHS: Array[String] = [
	"res://assets/quaternius/meshes/male/Superhero_Male_FullBody_Sphere_005_Retopology_004.res",
	"res://assets/quaternius/meshes/male/Superhero_Male_FullBody_Face.res",
	"res://assets/quaternius/meshes/male/Superhero_Male_FullBody_Face_001.res"
]


func _setup_skeleton() -> void:
	if not _player:
		return
		
	var skeleton: Skeleton3D = _player.find_child("*Skeleton*", true, false) as Skeleton3D
	if skeleton:
		skeleton.name = "GeneralSkeleton"
		skeleton.owner = _player
		skeleton.unique_name_in_owner = true
		
		# Hide default imported meshes (e.g. Mannequin) under the skeleton
		for child in skeleton.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).visible = false
				
		# Attach the male meshes if they haven't been added yet
		if not skeleton.has_node("MaleMesh_0"):
			for i in range(MALE_MESH_PATHS.size()):
				var path := MALE_MESH_PATHS[i]
				var mesh_res := load(path) as ArrayMesh
				if mesh_res:
					var mi := MeshInstance3D.new()
					mi.name = "MaleMesh_" + str(i)
					mi.mesh = mesh_res
					mi.skeleton = NodePath("..")
					skeleton.add_child(mi)
		
		# Force AnimationPlayer to re-resolve node paths after renaming
		if anim_player:
			anim_player.clear_caches()


func _process(delta: float) -> void:
	if not _player:
		return
	
	_update_mesh_rotation(delta)
	_update_animation_state()


## Rotates the visual mesh towards the movement direction of the parent CharacterBody3D
func _update_mesh_rotation(delta: float) -> void:
	if not visuals:
		return
	
	var horiz_vel := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
	if horiz_vel.length() > 0.1:
		var dir := horiz_vel.normalized()
		# For Quaternius models (+Z forward), atan2(dir.x, dir.z) faces the travel direction
		var target_angle := atan2(dir.x, dir.z)
		visuals.rotation.y = lerp_angle(visuals.rotation.y, target_angle, rotation_speed * delta)


## Selects and plays animation based on parent velocity and floor status
func _update_animation_state() -> void:
	if not anim_player:
		return
		
	# Airborne / Jump state
	if not _player.is_on_floor():
		_play_anim("Jump")
		return
	
	# Horizontal locomotion
	var speed := Vector3(_player.velocity.x, 0.0, _player.velocity.z).length()
	
	if speed > 6.0:
		_play_anim("Sprint")
	elif speed > 0.1:
		_play_anim("Walk")
	else:
		_play_anim("Idle")


func _play_anim(anim_name: StringName) -> void:
	var target_anim := anim_name
	if not anim_player.has_animation(target_anim):
		target_anim = StringName("ual/" + anim_name)
		if not anim_player.has_animation(target_anim):
			if anim_name == &"Walk" and anim_player.has_animation("ual/Jog_Fwd"):
				target_anim = &"ual/Jog_Fwd"
			elif anim_name == &"Jog_Fwd" and anim_player.has_animation("ual/Walk"):
				target_anim = &"ual/Walk"
			else:
				return

	if anim_player.current_animation != target_anim:
		anim_player.play(target_anim)
