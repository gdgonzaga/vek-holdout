extends GdUnitTestSuite

## Player look behavior: body facing follows camera yaw, and the torso/head
## look lean follows camera pitch (docs/architecture/player.md, "Look: Facing and Lean").

const PlayerScene = preload("res://subsystems/player/player.tscn")


## Regression: visual body-facing must track the camera's look direction, not
## a frozen last-walked direction -- the source of the "back button turns the
## player around" bug (facing used to be re-derived from movement velocity).
func test_look_direction_tracks_camera_yaw() -> void:
	var player := _spawn_player()

	var yaw := deg_to_rad(37.0)
	player._rig.set_orientation(yaw, 0.0)

	var reference: Node3D = auto_free(Node3D.new())
	add_child(reference)
	reference.rotation.y = yaw
	var expected_dir := -reference.global_transform.basis.z

	var look_dir := player.get_look_direction()
	assert_float(look_dir.x).is_equal_approx(expected_dir.x, 0.001)
	assert_float(look_dir.y).is_equal_approx(0.0, 0.001)
	assert_float(look_dir.z).is_equal_approx(expected_dir.z, 0.001)


## Regression: looking up must lean the head back and looking down must lean
## it forward. The first version had this inverted (the rig bends forward on
## positive local-X rotation) and a "pose changed" assertion couldn't catch it.
func test_look_lean_follows_look_direction() -> void:
	var player := _spawn_player()
	var lean := player.anim_controller.look_lean
	assert_bool(lean.is_bound()).is_true()

	var skel := lean._skeleton
	var baseline_chest := skel.get_bone_pose_rotation(lean._chest_bone_idx)
	var baseline_head := skel.get_bone_pose_rotation(lean._head_bone_idx)

	var level := _head_forward_offset_after_lean(player, 0.0, baseline_chest, baseline_head)
	var looking_up := _head_forward_offset_after_lean(player, deg_to_rad(35.0), baseline_chest, baseline_head)
	var looking_down := _head_forward_offset_after_lean(player, deg_to_rad(-35.0), baseline_chest, baseline_head)

	assert_float(looking_up).is_less(level)
	assert_float(looking_down).is_greater(level)


## Regression guard for the process ordering: the controller is moved ahead of
## the AnimationTree in the scene, so only its process_priority keeps it running
## after the tree. At skeleton_updated (the pose handed to skinning), the Chest
## must sit exactly its share of the lean away from what the tree applied.
func test_look_lean_reaches_skinning_after_animation() -> void:
	var player: Player = PlayerScene.instantiate()
	player.move_child(player.get_node("AnimationController"), player.get_node("AnimationTree").get_index())
	auto_free(player)
	add_child(player)

	var controller := player.anim_controller
	var lean := controller.look_lean
	var skel := lean._skeleton
	var animated_chest: Array[Quaternion] = [Quaternion.IDENTITY]
	var skinned_chest: Array[Quaternion] = [Quaternion.IDENTITY]
	controller.anim_tree.mixer_applied.connect(func() -> void:
		animated_chest[0] = skel.get_bone_pose_rotation(lean._chest_bone_idx))
	skel.skeleton_updated.connect(func() -> void:
		skinned_chest[0] = skel.get_bone_pose_rotation(lean._chest_bone_idx))

	var pitch := deg_to_rad(30.0)
	player._rig.set_orientation(0.0, pitch)
	lean._smoothed_pitch = pitch
	for _i in range(3):
		await get_tree().process_frame

	var expected_deg := rad_to_deg(pitch) * lean.chest_share
	assert_float(rad_to_deg(skinned_chest[0].angle_to(animated_chest[0]))).is_equal_approx(expected_deg, 0.5)


## Auxiliary: Instantiates player.tscn into the test tree
func _spawn_player() -> Player:
	var player: Player = PlayerScene.instantiate()
	auto_free(player)
	add_child(player)
	return player


## Auxiliary: Resets Chest/Head to their animated baseline, applies a converged
## look lean, and returns how far the head sits ahead of the hips along the
## model's facing (+Z is forward for this model inside Visuals).
func _head_forward_offset_after_lean(player: Player, pitch: float, baseline_chest: Quaternion, baseline_head: Quaternion) -> float:
	var lean := player.anim_controller.look_lean
	var skel := lean._skeleton
	skel.set_bone_pose_rotation(lean._chest_bone_idx, baseline_chest)
	skel.set_bone_pose_rotation(lean._head_bone_idx, baseline_head)
	# A delta of 0.0 leaves the eased pitch where it's set, so the lean is deterministic.
	lean._smoothed_pitch = pitch
	lean.apply(pitch, 0.0)
	var head_world := skel.global_transform * skel.get_bone_global_pose(lean._head_bone_idx).origin
	var hips_world := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Hips")).origin
	var model_forward := player.anim_controller.visuals.global_transform.basis.z.normalized()
	return (head_world - hips_world).dot(model_forward)
