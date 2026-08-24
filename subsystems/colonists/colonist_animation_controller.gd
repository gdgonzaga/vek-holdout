## Subsystem: Colonists
## Modular animation controller component attached as a child node to Colonist (CharacterBody3D).
## Automatically binds female mesh model, drives AnimationPlayer, and handles facing orientation.
class_name ColonistAnimationController
extends Node

const FEMALE_MESH_PATHS: Array[String] = [
	"res://assets/quaternius/meshes/female/Superhero_Female_FullBody_Superhero_Female.res",
	"res://assets/quaternius/meshes/female/Superhero_Female_FullBody_Eyes.res",
	"res://assets/quaternius/meshes/female/Superhero_Female_FullBody_Eyebrows.res"
]

## Reference to AnimationPlayer (auto-resolves if empty)
@export var anim_player: AnimationPlayer

## Reference to Visuals container node (auto-resolves if empty)
@export var visuals: Node3D

## Rotation lerp speed for facing direction
@export var rotation_speed: float = 15.0

## Cached parent Colonist reference
var _colonist: CharacterBody3D


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


func _setup_skeleton() -> void:
	if not _colonist:
		return
		
	var skeleton: Skeleton3D = _colonist.find_child("*Skeleton*", true, false) as Skeleton3D
	if skeleton:
		skeleton.name = "GeneralSkeleton"
		skeleton.owner = _colonist
		skeleton.unique_name_in_owner = true
		
		# Hide default imported meshes (e.g. Mannequin) under the skeleton
		for child in skeleton.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).visible = false
				
		# Attach the female meshes if they haven't been added yet
		if not skeleton.has_node("FemaleMesh_0"):
			for i in range(FEMALE_MESH_PATHS.size()):
				var path := FEMALE_MESH_PATHS[i]
				var mesh_res := load(path) as ArrayMesh
				if mesh_res:
					var mi := MeshInstance3D.new()
					mi.name = "FemaleMesh_" + str(i)
					mi.mesh = mesh_res
					mi.skeleton = NodePath("..")
					skeleton.add_child(mi)
		
		# Force AnimationPlayer to re-resolve node paths after renaming/adding meshes
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


## Selects and plays animation based on parent velocity and floor status
func _update_animation_state() -> void:
	if not anim_player:
		return
		
	# Airborne / Jump state
	if not _colonist.is_on_floor():
		_play_anim("Jump")
		return
	
	# Horizontal locomotion
	var speed := Vector3(_colonist.velocity.x, 0.0, _colonist.velocity.z).length()
	
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
