extends GdUnitTestSuite

## LookLean (subsystems/core/look_lean.gd): clamps, easing, and the Chest/Head
## split, on a code-built skeleton so no model content is involved.


func test_clamps_look_up_and_down_separately() -> void:
	var lean := _make_lean()
	lean.max_up_deg = 10.0
	lean.max_down_deg = 25.0

	assert_float(rad_to_deg(lean.clamp_pitch(deg_to_rad(60.0)))).is_equal_approx(10.0, 0.001)
	assert_float(rad_to_deg(lean.clamp_pitch(deg_to_rad(-60.0)))).is_equal_approx(-25.0, 0.001)
	assert_float(rad_to_deg(lean.clamp_pitch(deg_to_rad(5.0)))).is_equal_approx(5.0, 0.001)


func test_apply_splits_lean_between_chest_and_head() -> void:
	var skeleton := _make_skeleton()
	var lean := _make_lean()
	lean.chest_share = 0.75
	lean.bind(skeleton)

	# A delta of 0.0 leaves the eased pitch where it's set, so the lean is exact.
	lean._smoothed_pitch = deg_to_rad(20.0)
	lean.apply(deg_to_rad(20.0), 0.0)

	var chest_deg := rad_to_deg(skeleton.get_bone_pose_rotation(skeleton.find_bone("Chest")).get_angle())
	var head_deg := rad_to_deg(skeleton.get_bone_pose_rotation(skeleton.find_bone("Head")).get_angle())
	assert_float(chest_deg).is_equal_approx(15.0, 0.01)
	assert_float(head_deg).is_equal_approx(5.0, 0.01)


func test_apply_eases_toward_target_pitch() -> void:
	var lean := _make_lean()
	lean.bind(_make_skeleton())
	var target := deg_to_rad(30.0)

	lean.apply(target, 0.02)
	assert_float(lean._smoothed_pitch).is_greater(0.0)
	assert_float(lean._smoothed_pitch).is_less(target)

	lean.apply(target, 10.0)
	assert_float(lean._smoothed_pitch).is_equal_approx(target, 0.0001)


func test_skeleton_without_lean_bones_is_left_untouched() -> void:
	var skeleton: Skeleton3D = auto_free(Skeleton3D.new())
	skeleton.add_bone("Hips")
	var lean := _make_lean()
	lean.bind(skeleton)

	assert_bool(lean.is_bound()).is_false()
	lean.apply(deg_to_rad(30.0), 10.0)
	assert_float(lean._smoothed_pitch).is_equal(0.0)


## Auxiliary: A fresh LookLean with default knobs
func _make_lean() -> LookLean:
	return auto_free(LookLean.new())


## Auxiliary: Hips -> Chest -> Head skeleton with identity poses
func _make_skeleton() -> Skeleton3D:
	var skeleton: Skeleton3D = auto_free(Skeleton3D.new())
	skeleton.add_bone("Hips")
	skeleton.add_bone("Chest")
	skeleton.add_bone("Head")
	skeleton.set_bone_parent(skeleton.find_bone("Chest"), skeleton.find_bone("Hips"))
	skeleton.set_bone_parent(skeleton.find_bone("Head"), skeleton.find_bone("Chest"))
	return skeleton
